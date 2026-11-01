import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tailscale_linux/update/update.dart';
import 'package:tailscale_linux/update/update_controller.dart';

Future<Directory> tempDir() async {
  final dir = await Directory.systemTemp.createTemp('update_test');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}

/// A release archive like CI's, holding `tailscale-linux/tailscale_linux`
/// with [content]; without the executable when [content] is null.
Future<File> archive(Directory dir, String? content) async {
  final src = Directory('${dir.path}/src/$appFolderName')
    ..createSync(recursive: true);
  if (content != null) {
    File('${src.path}/$executableName').writeAsStringSync(content);
  } else {
    File('${src.path}/README').writeAsStringSync('no app here');
  }
  final file = File('${dir.path}/$linuxArchiveName');
  final tar = await Process.run('tar', [
    '-C',
    '${dir.path}/src',
    '-czf',
    file.path,
    appFolderName,
  ]);
  expect(tar.exitCode, 0, reason: '${tar.stderr}');
  return file;
}

class FakeUpdater implements Updater {
  FakeUpdater(this.newest);

  final Release? newest;
  final installed = <String>[];

  @override
  Future<Release?> newestRelease() async => newest;

  @override
  Future<void> install(Release release, Directory appDir) async =>
      installed.add(release.version);

  @override
  Future<void> restart(Directory appDir) async {}
}

Release release(String version) => Release(
  version: version,
  archiveUrl: Uri.parse('https://example.com/$linuxArchiveName'),
  pageUrl: Uri.parse('https://example.com/v$version'),
);

void main() {
  test('semantic version order', () {
    expect(compareVersions('0.1.0', '0.1.0'), 0);
    expect(compareVersions('0.2.0', '0.1.9'), greaterThan(0));
    expect(compareVersions('0.1.10', '0.1.9'), greaterThan(0));
    expect(compareVersions('0.2.0', '0.2.0-beta'), greaterThan(0));
    expect(compareVersions('0.2.0-beta.2', '0.2.0-beta.10'), lessThan(0));
    expect(compareVersions('0.2.0-alpha', '0.2.0-beta'), lessThan(0));
  });

  test('the newest release and its Linux archive', () {
    final body = jsonEncode([
      {
        'tag_name': 'v0.2.0-beta',
        'html_url': 'https://github.com/x/releases/tag/v0.2.0-beta',
        'assets': [
          {'name': 'other.zip', 'browser_download_url': 'https://x/other.zip'},
          {
            'name': linuxArchiveName,
            'browser_download_url': 'https://x/$linuxArchiveName',
          },
        ],
      },
    ]);

    final r = parseNewestRelease(body)!;
    expect(r.version, '0.2.0-beta');
    expect(r.archiveUrl.toString(), 'https://x/$linuxArchiveName');
    expect(parseNewestRelease('[]'), isNull);
    expect(
      parseNewestRelease(
        jsonEncode([
          {'tag_name': 'v1', 'assets': <Object>[]},
        ]),
      ),
      isNull,
      reason: 'a release without the Linux archive',
    );
  });

  test('only the copy install.sh put in place counts as installed', () async {
    final data = await tempDir();
    final app = Directory('${data.path}/$appFolderName');
    Directory('${app.path}/data/flutter_assets').createSync(recursive: true);
    File('${app.path}/data/flutter_assets/version.json')
        .writeAsStringSync('{"app_name":"tailscale_linux","version":"0.1.0"}');

    final installed = AppInstall.at(app, {
      'HOME': '/home/me',
      'XDG_DATA_HOME': data.path,
    });
    expect(installed.version, '0.1.0');
    expect(installed.installed, isTrue);

    final fromSource = AppInstall.at(
      Directory('/home/me/dev/tailscale/build/linux/x64/release/bundle'),
      {'HOME': '/home/me'},
    );
    expect(fromSource.installed, isFalse);
    expect(fromSource.version, '');
  });

  test('installing an archive replaces the app folder', () async {
    final dir = await tempDir();
    final app = Directory('${dir.path}/data/$appFolderName')
      ..createSync(recursive: true);
    File('${app.path}/$executableName').writeAsStringSync('old');
    File('${app.path}/stale-file').writeAsStringSync('from the old version');

    await installArchive(await archive(dir, 'new'), app);

    expect(File('${app.path}/$executableName').readAsStringSync(), 'new');
    expect(File('${app.path}/stale-file').existsSync(), isFalse);
    expect(
      app.parent.listSync().map(
        (e) => e.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
      ),
      [appFolderName],
      reason: 'no staging folder left behind',
    );
  });

  test('a broken archive leaves the app as it was', () async {
    final dir = await tempDir();
    final app = Directory('${dir.path}/data/$appFolderName')
      ..createSync(recursive: true);
    File('${app.path}/$executableName').writeAsStringSync('old');

    await expectLater(
      installArchive(await archive(dir, null), app),
      throwsA(isA<UpdateException>()),
    );
    expect(File('${app.path}/$executableName').readAsStringSync(), 'old');
  });

  test(
    'check, then install only a newer release, only when installed',
    () async {
      final app = AppInstall(
        version: '0.1.0',
        dir: Directory('/x'),
        installed: true,
      );

      final none = UpdateController(
        app: app,
        updater: FakeUpdater(release('0.1.0')),
      );
      await none.check();
      expect(none.stage, UpdateStage.upToDate);

      final updater = FakeUpdater(release('0.2.0'));
      final updates = UpdateController(app: app, updater: updater);
      await updates.check();
      expect(updates.stage, UpdateStage.available);
      await updates.install();
      expect(updates.stage, UpdateStage.installed);
      expect(updater.installed, ['0.2.0']);

      final fromSourceUpdater = FakeUpdater(release('0.2.0'));
      final fromSource = UpdateController(
        app: AppInstall(
          version: '0.1.0',
          dir: Directory('/x'),
          installed: false,
        ),
        updater: fromSourceUpdater,
      );
      await fromSource.check();
      await fromSource.install();
      expect(fromSource.stage, UpdateStage.available);
      expect(fromSourceUpdater.installed, isEmpty);
    },
  );
}
