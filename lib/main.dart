import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'access/access_controller.dart';
import 'access/access_page.dart';
import 'app_window.dart';
import 'settings/accounts_page.dart';
import 'tailscale/local_api.dart';
import 'tailscale/tailscale_controller.dart';
import 'tray/tray_menu.dart';
import 'tray/tray_presenter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final api = LocalApiClient();
  final access = AccessController(api.canWrite);
  final tailscale = TailscaleController(api);
  final window = AppWindow();

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
      iconAsset: connected
          ? 'assets/tray/connected.png'
          : 'assets/tray/disconnected.png',
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
  } else {
    debugPrint('tray: not supported here; showing the window instead');
  }
  tailscale.start();

  access.check().then((_) {
    if (!hasTray || access.status != AccessStatus.granted) window.show();
  });

  runApp(TailscaleApp(access: access, tailscale: tailscale));
}

class TailscaleApp extends StatelessWidget {
  const TailscaleApp({
    super.key,
    required this.access,
    required this.tailscale,
  });

  final AccessController access;
  final TailscaleController tailscale;

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
            ? AccountsPage(tailscale: tailscale)
            : AccessPage(controller: access),
      ),
    );
  }
}
