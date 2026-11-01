import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'access/access_controller.dart';
import 'access/access_page.dart';
import 'app_window.dart';
import 'platform/autostart.dart';
import 'platform/desktop.dart';
import 'settings/app_settings.dart';
import 'settings/settings_window.dart';
import 'tailscale/local_api.dart';
import 'tailscale/operator.dart';
import 'tailscale/tailscale_controller.dart';
import 'tray/tray_menu.dart';
import 'tray/tray_presenter.dart';

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
  final tailscale = TailscaleController(
    api,
    openUrl: openUrl,
    restoreOperator: setOperatorAsRoot,
  );
  final window = AppWindow();

  // Operator access lost (say, the current profile has no operator): show
  // how to get it back. Once it is back, re-read everything.
  tailscale.addListener(() {
    if (!tailscale.canWrite && access.status == AccessStatus.granted) {
      access.check().then((_) => window.show());
    }
  });
  access.addListener(() {
    if (access.status == AccessStatus.granted) tailscale.refresh();
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
          window.show();
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
    ),
  );
}

class TailscaleApp extends StatelessWidget {
  const TailscaleApp({
    super.key,
    required this.access,
    required this.tailscale,
    required this.appSettings,
    required this.autostart,
  });

  final AccessController access;
  final TailscaleController tailscale;
  final AppSettings appSettings;
  final Autostart autostart;

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
        listenable: access,
        builder: (context, _) => access.status == AccessStatus.granted
            ? SettingsWindow(
                tailscale: tailscale,
                appSettings: appSettings,
                autostart: autostart,
              )
            : AccessPage(controller: access),
      ),
    );
  }
}
