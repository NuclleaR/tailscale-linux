import 'dart:io';

import 'package:flutter/foundation.dart';

/// The user's config directory: `$XDG_CONFIG_HOME`, or `~/.config` when it
/// is unset.
String configHome([Map<String, String>? environment]) {
  final env = environment ?? Platform.environment;
  final xdg = env['XDG_CONFIG_HOME'] ?? '';
  return xdg.isNotEmpty ? xdg : '${env['HOME']}/.config';
}

/// The user's Downloads folder, as `user-dirs.dirs` names it (it may be
/// localized, such as `~/Завантаження`), or `~/Downloads`.
Future<Directory> downloadDirectory([Map<String, String>? environment]) async {
  final env = environment ?? Platform.environment;
  final home = env['HOME'] ?? '';
  try {
    final lines = await File('${configHome(env)}/user-dirs.dirs').readAsLines();
    for (final line in lines) {
      final match = RegExp(r'^XDG_DOWNLOAD_DIR="(.+)"$')
          .firstMatch(line.trim());
      if (match != null) {
        return Directory(match[1]!.replaceFirst(r'$HOME', home));
      }
    }
  } on FileSystemException {
    // No user-dirs.dirs: use the default.
  }
  return Directory('$home/Downloads');
}

/// Opens [url] in the default browser.
Future<void> openUrl(String url) async {
  try {
    await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
  } on ProcessException catch (e) {
    debugPrint('cannot open $url: $e');
  }
}

/// Shows a desktop notification through `notify-send`.
Future<void> notify(String summary, {String body = ''}) async {
  try {
    await Process.run('notify-send', [
      '--app-name=Tailscale',
      summary,
      if (body.isNotEmpty) body,
    ]);
  } on ProcessException catch (e) {
    debugPrint('cannot notify: $e');
  }
}
