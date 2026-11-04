import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailscale_linux/platform/autostart.dart';
import 'package:tailscale_linux/platform/desktop.dart';
import 'package:tailscale_linux/platform/file_picker.dart';
import 'package:tailscale_linux/settings/app_settings.dart';

Future<Directory> tempDir() async {
  final dir = await Directory.systemTemp.createTemp('platform_test');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}

void main() {
  test('configHome follows XDG_CONFIG_HOME, else ~/.config', () {
    expect(configHome({'XDG_CONFIG_HOME': '/xdg', 'HOME': '/home/me'}), '/xdg');
    expect(
      configHome({'XDG_CONFIG_HOME': '', 'HOME': '/home/me'}),
      '/home/me/.config',
    );
    expect(configHome({'HOME': '/home/me'}), '/home/me/.config');
  });

  test('autostart writes and removes the desktop entry', () async {
    final dir = await tempDir();
    final autostart = Autostart(
      configHome: dir.path,
      executable: '/opt/tail scale/tailscale_linux',
    );
    expect(autostart.enabled, isFalse);

    await autostart.setEnabled(true);
    expect(autostart.enabled, isTrue);
    expect(
      autostart.file.path,
      '${dir.path}/autostart/tailscale_linux.desktop',
    );
    expect(
      await autostart.file.readAsString(),
      contains('Exec="/opt/tail scale/tailscale_linux"\n'),
    );

    await autostart.setEnabled(false);
    expect(autostart.enabled, isFalse);
  });

  test('autostart escapes the executable path', () {
    expect(
      Autostart.desktopEntry(r'/a"b/$c/100%/d\e'),
      contains(r'Exec="/a\"b/\$c/100%%/d\\e"'),
    );
  });

  test('app settings: defaults, save and load', () async {
    final file = File('${(await tempDir()).path}/app/settings.json');
    final settings = AppSettings(file);
    await settings.load();
    expect(settings.trayIcon, TrayIconColor.white);
    expect(settings.loginLinks, LoginLinkAction.open);

    await settings.setTrayIcon(TrayIconColor.black);
    await settings.setLoginLinks(LoginLinkAction.copy);
    final reloaded = AppSettings(file);
    await reloaded.load();
    expect(reloaded.trayIcon, TrayIconColor.black);
    expect(reloaded.loginLinks, LoginLinkAction.copy);

    await reloaded.setPinned('nA', true);
    await reloaded.setPinned('nB', true);
    await reloaded.setPinned('nA', false);
    final pins = AppSettings(file);
    await pins.load();
    expect(pins.pinnedDevices, {'nB'});
    expect(pins.trayIcon, TrayIconColor.black);
    expect(pins.loginLinks, LoginLinkAction.copy);

    await file.writeAsString('{"loginLinks": "teleport"}');
    final unknown = AppSettings(file);
    await unknown.load();
    expect(unknown.loginLinks, LoginLinkAction.open);

    await file.writeAsString('not json');
    final broken = AppSettings(file);
    await broken.load();
    expect(broken.trayIcon, TrayIconColor.white);
    expect(broken.loginLinks, LoginLinkAction.open);
  });

  group('copyText', () {
    const wayland = {'WAYLAND_DISPLAY': 'wayland-1'};
    const x11 = {'DISPLAY': ':0'};
    late List<String> clipboard;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      clipboard = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard.add((call.arguments as Map)['text'] as String);
            }
            return null;
          });
    });

    /// A fake `wl-copy` that saves what it was given, or fails.
    Future<(String, File)> fakeWlCopy({bool fails = false}) async {
      final dir = await tempDir();
      final copied = File('${dir.path}/copied');
      final script = File('${dir.path}/wl-copy');
      await script.writeAsString(
        fails
            ? '#!/bin/sh\nexit 1\n'
            : '#!/bin/sh\n[ "\$1" = -- ] && printf %s "\$2" > "${copied.path}"\n',
      );
      await Process.run('chmod', ['+x', script.path]);
      return (script.path, copied);
    }

    test('Wayland: wl-copy, which needs no focus', () async {
      final (wlCopy, copied) = await fakeWlCopy();
      expect(
        await copyText(
          'https://login/a',
          windowFocused: false,
          environment: wayland,
          wlCopy: wlCopy,
        ),
        isTrue,
      );
      expect(await copied.readAsString(), 'https://login/a');
      expect(clipboard, isEmpty);
    });

    test('Wayland without wl-copy: only a focused window copies', () async {
      final missing = '${(await tempDir()).path}/wl-copy';
      expect(
        await copyText(
          'a',
          windowFocused: false,
          environment: wayland,
          wlCopy: missing,
        ),
        isFalse,
      );
      expect(clipboard, isEmpty);

      expect(
        await copyText(
          'b',
          windowFocused: true,
          environment: wayland,
          wlCopy: missing,
        ),
        isTrue,
      );
      expect(clipboard, ['b']);
    });

    test('Wayland, wl-copy fails, no focus: not copied', () async {
      final (wlCopy, _) = await fakeWlCopy(fails: true);
      expect(
        await copyText(
          'a',
          windowFocused: false,
          environment: wayland,
          wlCopy: wlCopy,
        ),
        isFalse,
      );
    });

    test('X11: the clipboard, focused or not', () async {
      expect(
        await copyText(
          'a',
          windowFocused: false,
          environment: x11,
          wlCopy: '/nonexistent/wl-copy',
        ),
        isTrue,
      );
      expect(clipboard, ['a']);
    });
  });

  test('wl-copy is missing only on Wayland, when not on the PATH', () async {
    final empty = await tempDir();
    final bin = await tempDir();
    final wlCopy = File('${bin.path}/wl-copy');
    await wlCopy.writeAsString('#!/bin/sh\n');

    final wayland = {
      'WAYLAND_DISPLAY': 'wayland-1',
      'PATH': '${empty.path}:${bin.path}',
    };
    // Not executable yet.
    expect(wlCopyMissing(wayland), isTrue);
    await Process.run('chmod', ['+x', wlCopy.path]);
    expect(wlCopyMissing(wayland), isFalse);
    expect(
      wlCopyMissing({'WAYLAND_DISPLAY': 'wayland-1', 'PATH': empty.path}),
      isTrue,
    );
    expect(wlCopyMissing({'DISPLAY': ':0', 'PATH': empty.path}), isFalse);
  });

  test('picked files: one path per line', () {
    expect(parsePickedFiles('/home/me/a b.txt\n/home/me/c.png\n'), [
      '/home/me/a b.txt',
      '/home/me/c.png',
    ]);
    expect(parsePickedFiles(''), isEmpty);
  });

  test('tray icon assets', () {
    expect(
      TrayIconColor.white.asset(connected: true),
      'assets/tray/connected.png',
    );
    expect(
      TrayIconColor.black.asset(connected: false),
      'assets/tray/disconnected-black.png',
    );
  });
}
