import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'access/access_controller.dart';
import 'access/access_page.dart';
import 'app_window.dart';
import 'main_window/main_window.dart';
import 'platform/autostart.dart';
import 'platform/desktop.dart';
import 'settings/app_settings.dart';
import 'settings/settings_window.dart';
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
  tailscale = TailscaleController(
    api,
    openUrl: openUrl,
    restoreOperator: setOperatorAsRoot,
    onFilesWaiting: taildrop.receiveWaiting,
  );
  final window = AppWindow();
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
        case CopyText(:final text):
          await Clipboard.setData(ClipboardData(text: text));
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
  });

  final AccessController access;
  final TailscaleController tailscale;
  final AppSettings appSettings;
  final Autostart autostart;
  final UpdateController updates;
  final ValueNotifier<AppScreen> screen;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
