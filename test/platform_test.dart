import 'dart:io';

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

    await settings.setTrayIcon(TrayIconColor.black);
    final reloaded = AppSettings(file);
    await reloaded.load();
    expect(reloaded.trayIcon, TrayIconColor.black);

    await reloaded.setPinned('nA', true);
    await reloaded.setPinned('nB', true);
    await reloaded.setPinned('nA', false);
    final pins = AppSettings(file);
    await pins.load();
    expect(pins.pinnedDevices, {'nB'});
    expect(pins.trayIcon, TrayIconColor.black);

    await file.writeAsString('not json');
    final broken = AppSettings(file);
    await broken.load();
    expect(broken.trayIcon, TrayIconColor.white);
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
