import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Which tray icon to show, so it stays visible on the panel.
enum TrayIconColor {
  /// For dark panels.
  white('white', ''),

  /// For light panels.
  black('black', '-black');

  const TrayIconColor(this.wireName, this._assetSuffix);

  final String wireName;
  final String _assetSuffix;

  String asset({required bool connected}) =>
      'assets/tray/${connected ? 'connected' : 'disconnected'}$_assetSuffix.png';

  static TrayIconColor parse(Object? value) =>
      values.firstWhere((c) => c.wireName == value, orElse: () => white);
}

/// What to do with a login page tailscaled asks the app to show (Add Account,
/// Renew). Its link is not known until the login starts, so the setting
/// decides.
enum LoginLinkAction {
  /// Open it in the default browser.
  open('open'),

  /// Copy it to the clipboard, to paste into the browser of one's choice.
  copy('copy');

  const LoginLinkAction(this.wireName);

  final String wireName;

  static LoginLinkAction parse(Object? value) =>
      values.firstWhere((a) => a.wireName == value, orElse: () => open);
}

/// The app's own settings, kept in a JSON file. Tailscale's settings live in
/// tailscaled, not here.
class AppSettings extends ChangeNotifier {
  AppSettings(this.file);

  final File file;

  TrayIconColor get trayIcon => _trayIcon;
  TrayIconColor _trayIcon = TrayIconColor.white;

  LoginLinkAction get loginLinks => _loginLinks;
  LoginLinkAction _loginLinks = LoginLinkAction.open;

  /// Stable node IDs of the devices pinned to the top of the device list.
  Set<String> get pinnedDevices => Set.unmodifiable(_pinnedDevices);
  Set<String> _pinnedDevices = {};

  /// Reads the file. A missing or unreadable file leaves the defaults.
  Future<void> load() async {
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, Object?>) {
        _trayIcon = TrayIconColor.parse(json['trayIcon']);
        _loginLinks = LoginLinkAction.parse(json['loginLinks']);
        _pinnedDevices = {
          for (final id in json['pinnedDevices'] as List<Object?>? ?? const [])
            if (id is String) id,
        };
      }
    } on FileSystemException {
      return;
    } on FormatException catch (e) {
      debugPrint('settings: ignoring ${file.path}: $e');
      return;
    }
    notifyListeners();
  }

  Future<void> setTrayIcon(TrayIconColor color) async {
    _trayIcon = color;
    notifyListeners();
    await _save();
  }

  Future<void> setLoginLinks(LoginLinkAction action) async {
    _loginLinks = action;
    notifyListeners();
    await _save();
  }

  Future<void> setPinned(String deviceId, bool pinned) async {
    if (pinned) {
      _pinnedDevices.add(deviceId);
    } else {
      _pinnedDevices.remove(deviceId);
    }
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'trayIcon': _trayIcon.wireName,
        'loginLinks': _loginLinks.wireName,
        'pinnedDevices': _pinnedDevices.toList()..sort(),
      }),
    );
  }
}
