import 'dart:io';

import 'package:flutter/material.dart';

import 'access/access_controller.dart';
import 'access/access_page.dart';
import 'app_window.dart';
import 'main_window/main_window.dart';
import 'platform/autostart.dart';
import 'platform/desktop.dart';
import 'settings/app_settings.dart';
import 'settings/settings_window.dart';
import 'settings/widgets.dart';
import 'tailscale/local_api.dart';
import 'tailscale/operator.dart';
import 'tailscale/taildrop_receiver.dart';
import 'tailscale/tailscale_controller.dart';
import 'tray/tray_menu.dart';
import 'tray/tray_presenter.dart';
import 'update/update.dart';
import 'update/update_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = configHome();
  final appSettings = AppSettings(
    File('$config/tailscale_linux/settings.json'),
  );
  await appSettings.load();
  final autostart = Autostart(
    configHome: config,
    executable: Platform.resolvedExecutable,
  );

  final api = LocalApiClient();
  final access = AccessController(api.canWrite);
  late final TailscaleController tailscale;
  final taildrop = TaildropReceiver(
    api,
    downloadDir: downloadDirectory,
    onSaved: (name, file) {
      tailscale.fileSaved(name);
      notify(
        'Received ${file.uri.pathSegments.last} from Taildrop',
        body: 'Saved to ${file.parent.path}',
      );
    },
  );
  final window = AppWindow();
  final navigatorKey = GlobalKey<NavigatorState>();
  // Whether the window has keyboard focus. Without it, Wayland may refuse
  // the app the clipboard (see copyText).
  var windowFocused = false;

  // For text that could not be copied (Wayland without wl-copy, and no
  // focus): shows it in the window, where a click on Copy can copy it.
  Future<void> showInWindow(
    Future<void> Function(BuildContext context) dialog,
  ) async {
    window.show();
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      debugPrint('cannot show a dialog: no window');
      return;
    }
    await dialog(context);
  }

  Future<void> copyLoginLink(String url) async {
    if (await copyText(url, windowFocused: windowFocused)) {
      await notify(
        'Login link copied',
        body: 'Paste it into your browser to log in.',
      );
      return;
    }
    await showInWindow(
      (context) => showCopyDialog(
        context,
        title: 'Log in to Tailscale',
        message: 'Open this link in a browser to log in:',
        text: url,
        copied: 'Login link copied',
        openable: true,
      ),
    );
  }

  // A login page's link is not known until the login starts, so there is no
  // Copy button for it: the setting picks.
  void showLoginPage(String url) {
    switch (appSettings.loginLinks) {
      case LoginLinkAction.open:
        openUrl(url);
      case LoginLinkAction.copy:
        copyLoginLink(url).catchError((Object e) {
          debugPrint('cannot copy the login link: $e');
        });
    }
  }

  tailscale = TailscaleController(
    api,
    openUrl: showLoginPage,
    restoreOperator: setOperatorAsRoot,
    onFilesWaiting: taildrop.receiveWaiting,
  );
  final screen = ValueNotifier(AppScreen.main);

  void showScreen(AppScreen s) {
    screen.value = s;
    window.show();
  }

  // Poll status only while the window is open, focused or not. Closing it
  // hides it (state `hidden`), leaving only the tray, which polls nothing.
  AppLifecycleListener(
    onStateChange: (state) {
      debugPrint('window: $state');
      windowFocused = state == AppLifecycleState.resumed;
      tailscale.setWindowOpen(
        state == AppLifecycleState.resumed ||
            state == AppLifecycleState.inactive,
      );
    },
  );

  // Operator access lost (say, the current profile has no operator): show
  // how to get it back. Once it is back, re-read everything.
  tailscale.addListener(() {
    if (!tailscale.canWrite && access.status == AccessStatus.granted) {
      access.check().then((_) => window.show());
    }
  });
  access.addListener(() {
    if (access.status != AccessStatus.granted) return;
    tailscale.refresh();
    // Files that arrived while the app was not running.
    taildrop.receiveWaiting();
  });

  Future<void> run(TrayCommand command) async {
    try {
      switch (command) {
        case SetConnected(:final connected):
          await tailscale.setConnected(connected);
        case SetExitNode(:final nodeId):
          await tailscale.setExitNode(nodeId);
        case SwitchProfile(:final profileId):
          await tailscale.switchProfile(profileId);
        case Renew():
          await tailscale.renew();
        case CopyText(:final text):
          if (await copyText(text, windowFocused: windowFocused)) {
            await notify('Copied $text');
          } else {
            await showInWindow(
              (context) => showCopyDialog(
                context,
                title: 'Copy to Clipboard',
                message: 'Copy it from here:',
                text: text,
                copied: 'Copied $text',
              ),
            );
          }
        case OpenSettings():
          showScreen(AppScreen.settings);
        case OpenMainWindow():
          showScreen(AppScreen.main);
        case Quit():
          exit(0);
      }
    } on LocalApiException catch (e) {
      if (!e.isForbidden) rethrow;
      // Operator access was lost: show how to get it back.
      await access.check();
      window.show();
    }
  }

  final tray = TrayPresenter(
    onCommand: (command) => run(command).catchError((Object e) {
      debugPrint('tray: $command failed: $e');
    }),
  );

  void updateTray() {
    final status = tailscale.status;
    final connected = status?.isRunning ?? false;
    tray.update(
      iconAsset: appSettings.trayIcon.asset(connected: connected),
      tooltip: switch (status) {
        null => 'Tailscale: not running',
        _ when connected => 'Tailscale: connected',
        _ => 'Tailscale: ${status.backendState.wireName}',
      },
      entries: buildTrayMenu(
        status: status,
        profiles: tailscale.profiles,
        currentProfileId: tailscale.currentProfileId,
        incomingFiles: tailscale.incomingFiles,
      ),
    );
  }

  final hasTray = tray.start();
  if (hasTray) {
    updateTray();
    tailscale.addListener(updateTray);
    appSettings.addListener(updateTray);
  } else {
    debugPrint('tray: not supported here; showing the window instead');
  }
  tailscale.start();

  access.check().then((_) {
    if (!hasTray || access.status != AccessStatus.granted) window.show();
  });

  runApp(
    TailscaleApp(
      access: access,
      tailscale: tailscale,
      appSettings: appSettings,
      autostart: autostart,
      updates: UpdateController(
        app: AppInstall.current(),
        updater: const GitHubUpdater(),
      ),
      screen: screen,
      navigatorKey: navigatorKey,
    ),
  );
}

/// What the app's single window shows.
enum AppScreen { main, settings }

class TailscaleApp extends StatelessWidget {
  const TailscaleApp({
    super.key,
    required this.access,
    required this.tailscale,
    required this.appSettings,
    required this.autostart,
    required this.updates,
    required this.screen,
    required this.navigatorKey,
  });

  final AccessController access;
  final TailscaleController tailscale;
  final AppSettings appSettings;
  final Autostart autostart;
  final UpdateController updates;
  final ValueNotifier<AppScreen> screen;

  /// For dialogs shown from outside the widget tree, such as a login link.
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Tailscale',
      theme: ThemeData(colorSchemeSeed: Colors.blue),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
      ),
      home: ListenableBuilder(
        listenable: Listenable.merge([access, screen]),
        builder: (context, _) => access.status != AccessStatus.granted
            ? AccessPage(controller: access)
            : switch (screen.value) {
                AppScreen.main => MainWindow(
                  tailscale: tailscale,
                  appSettings: appSettings,
                  onOpenSettings: () => screen.value = AppScreen.settings,
                ),
                AppScreen.settings => SettingsWindow(
                  tailscale: tailscale,
                  appSettings: appSettings,
                  autostart: autostart,
                  updates: updates,
                  onBack: () => screen.value = AppScreen.main,
                ),
              },
      ),
    );
  }
}
