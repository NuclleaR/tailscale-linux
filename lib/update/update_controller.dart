import 'dart:io';

import 'package:flutter/foundation.dart';

import 'update.dart';

/// Finds, installs and starts new releases.
abstract interface class Updater {
  Future<Release?> newestRelease();
  Future<void> install(Release release, Directory appDir);

  /// Starts the app at [appDir] again and ends this process.
  Future<void> restart(Directory appDir);
}

/// Knows of no releases: the default, so tests never reach the network.
/// `main` passes [GitHubUpdater].
class NoUpdater implements Updater {
  const NoUpdater();

  @override
  Future<Release?> newestRelease() async => null;

  @override
  Future<void> install(Release release, Directory appDir) async =>
      throw const UpdateException('updates are off');

  @override
  Future<void> restart(Directory appDir) async {}
}

class GitHubUpdater implements Updater {
  const GitHubUpdater();

  @override
  Future<Release?> newestRelease() => fetchNewestRelease();

  @override
  Future<void> install(Release release, Directory appDir) async {
    final tmp = await Directory.systemTemp.createTemp('$appFolderName-');
    try {
      await installArchive(await downloadRelease(release, tmp), appDir);
    } finally {
      await tmp.delete(recursive: true);
    }
  }

  @override
  Future<void> restart(Directory appDir) async {
    await Process.start(
      '${appDir.path}/$executableName',
      const [],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }
}

enum UpdateStage {
  idle,
  checking,
  upToDate,
  available,
  installing,
  installed,
  failed,
}

/// The About pane's Check for Updates: check, install, restart.
class UpdateController extends ChangeNotifier {
  UpdateController({required this.app, Updater updater = const NoUpdater()})
    // A private field cannot be a named parameter.
    // ignore: prefer_initializing_formals
    : _updater = updater;

  final AppInstall app;
  final Updater _updater;

  UpdateStage get stage => _stage;
  UpdateStage _stage = UpdateStage.idle;

  /// The newer release once one is found.
  Release? get release => _release;
  Release? _release;

  /// Why the last check or install failed.
  String? get error => _error;
  String? _error;

  bool get busy =>
      _stage == UpdateStage.checking || _stage == UpdateStage.installing;

  /// Asks GitHub for a release newer than this one.
  Future<void> check() async {
    if (busy) return;
    _set(UpdateStage.checking);
    try {
      final newest = await _updater.newestRelease();
      if (newest != null && compareVersions(newest.version, app.version) > 0) {
        _release = newest;
        _set(UpdateStage.available);
      } else {
        _set(UpdateStage.upToDate);
      }
    } on Exception catch (e) {
      _set(UpdateStage.failed, error: '$e');
    }
  }

  /// Downloads the release found by [check] and puts it in place of the
  /// installed app. Only a copy installed with `install.sh` is replaced.
  Future<void> install() async {
    final release = _release;
    if (_stage != UpdateStage.available || release == null || !app.installed) {
      return;
    }
    _set(UpdateStage.installing);
    try {
      await _updater.install(release, app.dir);
      _set(UpdateStage.installed);
    } on Exception catch (e) {
      _set(UpdateStage.failed, error: '$e');
    }
  }

  /// Starts the new version and quits this one.
  Future<void> restart() => _updater.restart(app.dir);

  void _set(UpdateStage stage, {String? error}) {
    _stage = stage;
    _error = error;
    notifyListeners();
  }
}
