import 'dart:io';

import 'package:flutter/foundation.dart';

/// Starts the app on login through an XDG autostart entry,
/// `<config home>/autostart/tailscale_linux.desktop`.
class Autostart extends ChangeNotifier {
  Autostart({required String configHome, required this.executable})
    : file = File('$configHome/autostart/tailscale_linux.desktop');

  final File file;

  /// The binary the entry starts.
  final String executable;

  bool get enabled => file.existsSync();

  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      await file.parent.create(recursive: true);
      await file.writeAsString(desktopEntry(executable));
    } else if (await file.exists()) {
      await file.delete();
    }
    notifyListeners();
  }

  @visibleForTesting
  static String desktopEntry(String executable) =>
      '''
[Desktop Entry]
Type=Application
Name=Tailscale
Comment=Tailscale system tray client
Exec=${_quote(executable)}
Terminal=false
X-GNOME-Autostart-enabled=true
''';

  /// Quotes an `Exec` argument as the Desktop Entry spec asks.
  static String _quote(String argument) {
    final escaped = argument
        .replaceAllMapped(RegExp(r'["`$\\]'), (m) => '\\${m[0]}')
        .replaceAll('%', '%%');
    return '"$escaped"';
  }
}
