import 'dart:io';

import 'package:flutter/foundation.dart';

/// The user's config directory: `$XDG_CONFIG_HOME`, or `~/.config` when it
/// is unset.
String configHome([Map<String, String>? environment]) {
  final env = environment ?? Platform.environment;
  final xdg = env['XDG_CONFIG_HOME'] ?? '';
  return xdg.isNotEmpty ? xdg : '${env['HOME']}/.config';
}

/// Opens [url] in the default browser.
Future<void> openUrl(String url) async {
  try {
    await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
  } on ProcessException catch (e) {
    debugPrint('cannot open $url: $e');
  }
}
