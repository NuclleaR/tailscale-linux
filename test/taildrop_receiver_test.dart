import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tailscale_linux/platform/desktop.dart';
import 'package:tailscale_linux/tailscale/taildrop_receiver.dart';

import 'fake_daemon.dart';

Future<Directory> tempDir() async {
  final dir = await Directory.systemTemp.createTemp('taildrop_test');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}

void main() {
  test('saves each waiting file, then deletes it from tailscaled', () async {
    final waiting = {'photo.jpg': 'new photo', 'my notes.txt': 'notes'};
    final requests = <String>[];
    final client = await fakeDaemon((req) async {
      requests.add('${req.method} ${req.uri.path}');
      final name = Uri.decodeComponent(req.uri.pathSegments.last);
      switch ((req.method, req.uri.path)) {
        case ('GET', '/localapi/v0/files/'):
          req.response.write(
            jsonEncode([
              for (final MapEntry(:key, :value) in waiting.entries)
                {'Name': key, 'Size': value.length},
            ]),
          );
        case ('GET', _):
          req.response.write(waiting[name]);
        case ('DELETE', _):
          waiting.remove(name);
          req.response.statusCode = HttpStatus.noContent;
      }
      await req.response.close();
    });
    final downloads = await tempDir();
    await File('${downloads.path}/photo.jpg').writeAsString('old photo');
    final saved = <String>[];
    final receiver = TaildropReceiver(
      client,
      downloadDir: () async => downloads,
      onSaved: (name, f) => saved.add('$name -> ${f.uri.pathSegments.last}'),
    );

    await receiver.receiveWaiting();

    expect(saved, [
      'photo.jpg -> photo (1).jpg',
      'my notes.txt -> my notes.txt',
    ]);
    expect(
      await File('${downloads.path}/photo.jpg').readAsString(),
      'old photo',
    );
    expect(
      await File('${downloads.path}/photo (1).jpg').readAsString(),
      'new photo',
    );
    expect(
      await File('${downloads.path}/my notes.txt').readAsString(),
      'notes',
    );
    expect(waiting, isEmpty);
    expect(requests, contains('DELETE /localapi/v0/files/my%20notes.txt'));
    expect(
      downloads.listSync().map((e) => e.uri.pathSegments.last),
      isNot(contains(endsWith('.taildrop-partial'))),
    );
  });

  test(
    'file names cannot leave the folder; taken names get a number',
    () async {
      expect(safeFileName('../../etc/passwd'), 'passwd');
      expect(safeFileName('..'), 'file');

      final dir = await tempDir();
      expect(uniqueFile(dir, 'a.txt').path, '${dir.path}/a.txt');
      await File('${dir.path}/a.txt').create();
      await File('${dir.path}/a (1).txt').create();
      expect(uniqueFile(dir, 'a.txt').path, '${dir.path}/a (2).txt');
      await File('${dir.path}/README').create();
      expect(uniqueFile(dir, 'README').path, '${dir.path}/README (1)');
      await File('${dir.path}/.bashrc').create();
      expect(uniqueFile(dir, '.bashrc').path, '${dir.path}/.bashrc (1)');
    },
  );

  test('the Downloads folder comes from user-dirs.dirs', () async {
    final config = await tempDir();
    final env = {'HOME': '/home/me', 'XDG_CONFIG_HOME': config.path};
    expect((await downloadDirectory(env)).path, '/home/me/Downloads');

    await File('${config.path}/user-dirs.dirs').writeAsString(
      '# comment\n'
      'XDG_DESKTOP_DIR="\$HOME/Стільниця"\n'
      'XDG_DOWNLOAD_DIR="\$HOME/Завантаження"\n',
    );
    expect((await downloadDirectory(env)).path, '/home/me/Завантаження');
  });
}
