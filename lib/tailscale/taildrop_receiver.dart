import 'dart:io';

import 'package:flutter/foundation.dart';

import 'local_api.dart';

/// Moves files received with Taildrop out of tailscaled into a folder.
///
/// On Linux tailscaled keeps received files to itself until a client fetches
/// them; this is that client.
class TaildropReceiver {
  TaildropReceiver(
    this._api, {
    required this.downloadDir,
    required this.onSaved,
  });

  final LocalApiClient _api;

  /// Where received files go.
  final Future<Directory> Function() downloadDir;

  /// Called with each file's name as sent and where it was saved.
  final void Function(String name, File saved) onSaved;

  bool _receiving = false;
  bool _receiveAgain = false;

  /// Saves every waiting file, then removes it from tailscaled. Calls made
  /// while this runs collapse into one more pass after it.
  Future<void> receiveWaiting() async {
    if (_receiving) {
      _receiveAgain = true;
      return;
    }
    _receiving = true;
    try {
      do {
        _receiveAgain = false;
        final files = await _api.waitingFiles();
        if (files.isEmpty) continue;
        final dir = await downloadDir();
        await dir.create(recursive: true);
        for (final file in files) {
          final saved = await _save(file.name, dir);
          await _api.deleteWaitingFile(file.name);
          onSaved(file.name, saved);
        }
      } while (_receiveAgain);
    } on Exception catch (e) {
      debugPrint('taildrop: receiving failed: $e');
    } finally {
      _receiving = false;
    }
  }

  /// Downloads to a hidden partial file first, so a half-received file
  /// never shows under its real name.
  Future<File> _save(String name, Directory dir) async {
    final safe = safeFileName(name);
    final partial = File('${dir.path}/.$safe.taildrop-partial');
    try {
      await _api.downloadWaitingFile(name, partial);
    } on Exception {
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
    return partial.rename(uniqueFile(dir, safe).path);
  }
}

/// [name] without any directory part, so a file cannot land outside the
/// download folder.
@visibleForTesting
String safeFileName(String name) {
  final base = name.split('/').last;
  return base.isEmpty || base == '.' || base == '..' ? 'file' : base;
}

/// A file in [dir] named [name], or `name (1).ext`, `name (2).ext`… when
/// that is taken.
@visibleForTesting
File uniqueFile(Directory dir, String name) {
  var file = File('${dir.path}/$name');
  final dot = name.lastIndexOf('.');
  final (stem, ext) = dot > 0
      ? (name.substring(0, dot), name.substring(dot))
      : (name, '');
  for (var i = 1; file.existsSync(); i++) {
    file = File('${dir.path}/$stem ($i)$ext');
  }
  return file;
}
