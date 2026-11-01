import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tailscale_linux/tailscale/local_api.dart';

import 'fake_daemon.dart';

void main() {
  test('account endpoints', () async {
    final seen = <String>[];
    final client = await fakeDaemon((req) {
      seen.add('${req.method} ${req.uri.path}');
      req.response.statusCode = HttpStatus.noContent;
      req.response.close();
    });

    await client.newProfile();
    await client.deleteProfile('203a');
    await client.logout();
    await client.startLoginInteractive();

    expect(seen, [
      'PUT /localapi/v0/profiles/',
      'DELETE /localapi/v0/profiles/203a',
      'POST /localapi/v0/logout',
      'POST /localapi/v0/login-interactive',
    ]);
  });

  test('settings and about endpoints', () async {
    final client = await fakeDaemon((req) {
      req.response.write(switch (req.uri.path) {
        '/localapi/v0/tka/status' => '{"Enabled":true,"Head":null}',
        '/localapi/v0/update/check' =>
          '{"RunningLatest":false,"LatestVersion":"1.106.0"}',
        '/localapi/v0/dns-config' => '{"Domains":["example.com"]}',
        '/localapi/v0/prefs' => '{"ShieldsUp":true,"CorpDNS":true}',
        _ => '{}',
      });
      req.response.close();
    });

    expect(await client.tailnetLockEnabled(), isTrue);
    expect((await client.checkForUpdate()).latestVersion, '1.106.0');
    expect((await client.dnsConfig()).searchDomains, ['example.com']);
    final prefs = await client.prefs();
    expect(
      [prefs.shieldsUp, prefs.corpDns, prefs.routeAll],
      [true, true, false],
    );
  });

  test('canWrite is false when check-prefs is forbidden', () async {
    final seen = <String>[];
    final client = await fakeDaemon((req) {
      seen.add('${req.method} ${req.uri.path} host=${req.headers.host}');
      if (req.uri.path == '/localapi/v0/prefs') {
        req.response.write('{"WantRunning":true}');
      } else {
        req.response.statusCode = HttpStatus.forbidden;
        req.response.write('checkprefs access denied');
      }
      req.response.close();
    });

    expect(await client.canWrite(), isFalse);
    expect(seen, [
      'GET /localapi/v0/prefs host=local-tailscaled.sock',
      'POST /localapi/v0/check-prefs host=local-tailscaled.sock',
    ]);
  });

  test('canWrite is true when check-prefs succeeds', () async {
    final client = await fakeDaemon((req) {
      req.response.write('{}');
      req.response.close();
    });

    expect(await client.canWrite(), isTrue);
  });

  test('editPrefs sends a PATCH with the masked prefs', () async {
    String? seen;
    final client = await fakeDaemon((req) async {
      seen = '${req.method} ${req.uri.path} ${await utf8.decodeStream(req)}';
      req.response.write('{}');
      await req.response.close();
    });

    await client.editPrefs({'WantRunningSet': true, 'WantRunning': false});

    expect(
      seen,
      'PATCH /localapi/v0/prefs {"WantRunningSet":true,"WantRunning":false}',
    );
  });

  test('watchIpnBus yields one event per line', () async {
    String? query;
    final client = await fakeDaemon((req) async {
      query = req.uri.query;
      req.response.write('{"State":6}\n');
      await req.response.flush();
      req.response.write('{"BrowseToURL":"https://login"}\n');
      await req.response.close();
    });

    final events = await client.watchIpnBus().toList();

    expect(query, 'mask=18');
    expect(events, [
      {'State': 6},
      {'BrowseToURL': 'https://login'},
    ]);
  });

  test('other errors propagate', () async {
    final client = await fakeDaemon((req) {
      req.response.statusCode = HttpStatus.internalServerError;
      req.response.write('boom');
      req.response.close();
    });

    await expectLater(
      client.canWrite(),
      throwsA(
        isA<LocalApiException>().having((e) => e.statusCode, 'status', 500),
      ),
    );
  });
}
