import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

/// Puts [text] on the clipboard. False when it cannot be done from here.
///
/// On Wayland a window without keyboard focus may not set the clipboard (KWin
/// ignores it), and the app's window has none after a click in the tray. So
/// on Wayland `wl-copy` sets it, and without `wl-copy` only a focused window
/// can. [environment] and [wlCopy] are for tests.
Future<bool> copyText(
  String text, {
  required bool windowFocused,
  Map<String, String>? environment,
  String wlCopy = 'wl-copy',
}) async {
  final env = environment ?? Platform.environment;
  if ((env['WAYLAND_DISPLAY'] ?? '').isNotEmpty) {
    try {
      final process = await Process.start(wlCopy, ['--', text]);
      // wl-copy leaves a child behind that serves the clipboard until it
      // changes, and the child may hold these open: never wait on them.
      final errors = StringBuffer();
      process.stdout.listen(null);
      process.stderr.transform(utf8.decoder).listen(errors.write);
      final code = await process.exitCode;
      if (code == 0) return true;
      debugPrint('cannot copy: $wlCopy exited with $code: $errors');
    } on ProcessException catch (e) {
      debugPrint('cannot copy with wl-copy: $e');
    }
    if (!windowFocused) return false;
  }
  await Clipboard.setData(ClipboardData(text: text));
  return true;
}

/// True on Wayland when `wl-copy` is not on the `PATH`: copying from the tray
/// then needs a click in the window (see [copyText]).
bool wlCopyMissing([Map<String, String>? environment]) {
  final env = environment ?? Platform.environment;
  if ((env['WAYLAND_DISPLAY'] ?? '').isEmpty) return false;
  for (final dir in (env['PATH'] ?? '').split(':')) {
    if (dir.isEmpty) continue;
    final stat = FileStat.statSync('$dir/wl-copy');
    // Any execute bit.
    if (stat.type == FileSystemEntityType.file && stat.mode & 0x49 != 0) {
      return false;
    }
  }
  return true;
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
