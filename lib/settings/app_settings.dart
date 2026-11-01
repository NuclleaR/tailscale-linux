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

/// The app's own settings, kept in a JSON file. Tailscale's settings live in
/// tailscaled, not here.
class AppSettings extends ChangeNotifier {
  AppSettings(this.file);

  final File file;

  TrayIconColor get trayIcon => _trayIcon;
  TrayIconColor _trayIcon = TrayIconColor.white;

  /// Reads the file. A missing or unreadable file leaves the defaults.
  Future<void> load() async {
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, Object?>) {
        _trayIcon = TrayIconColor.parse(json['trayIcon']);
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

  Future<void> _save() async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ')
          .convert({'trayIcon': _trayIcon.wireName}),
    );
  }
}
