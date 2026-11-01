import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailscale_linux/tailscale/local_api.dart';
import 'package:tailscale_linux/tailscale/status.dart';
import 'package:tailscale_linux/tailscale/tailscale_controller.dart';

import 'fake_daemon.dart';

/// Just enough of tailscaled for the controller, with the per-profile
/// operator the real one has.
class FakeTailscaled {
  String operator = 'me';
  String backendState = 'Running';
  List<Map<String, Object?>> peers = [];

  /// Profiles that have no operator.
  final noOperator = <String>{};

  final requests = <String>[];
  final _bus = Completer<HttpResponse>();
  late final LocalApiClient client;

  /// The open IPN bus, once the controller has subscribed.
  Future<HttpResponse> get bus => _bus.future;

  Future<void> start() async {
    client = await fakeDaemon(_handle);
  }

  Future<void> _handle(HttpRequest req) async {
    final endpoint = req.uri.path.replaceFirst('/localapi/v0/', '');
    final response = req.response;
    if (endpoint == 'watch-ipn-bus') {
      // Left open: the test writes events to it. Like tailscaled, send each
      // event as soon as it is written.
      response.bufferOutput = false;
      _bus.complete(response);
      return;
    }
    requests.add('${req.method} $endpoint');
    final isOperator = operator == 'me';
    switch ((req.method, endpoint)) {
      case ('GET', 'status'):
        response.write(
          jsonEncode({
            'BackendState': backendState,
            'Peer': {for (final (i, p) in peers.indexed) 'nodekey:$i': p},
          }),
        );
      case ('GET', 'prefs'):
        response.write(jsonEncode({'OperatorUser': operator}));
      case (_, 'profiles/' || 'profiles/current') when !isOperator:
        response.statusCode = HttpStatus.forbidden;
        response.write('profiles access denied');
      case ('GET', 'profiles/'):
        response.write('[{"ID":"a"},{"ID":"b"}]');
      case ('GET', 'profiles/current'):
        response.write('{"ID":"a"}');
      case ('PUT', 'profiles/'):
        // Like tailscaled: a new profile starts from default prefs.
        operator = '';
        backendState = 'NeedsLogin';
      case ('POST', final String path) when path.startsWith('profiles/'):
        final id = path.substring('profiles/'.length);
        if (noOperator.contains(id)) operator = '';
      default:
        response.write('{}');
    }
    await response.close();
  }
}

void main() {
  late FakeTailscaled daemon;
  late List<String> restored;
  late TailscaleController tailscale;

  setUp(() async {
    daemon = FakeTailscaled();
    await daemon.start();
    restored = [];
    tailscale = TailscaleController(
      daemon.client,
      restoreOperator: (user) async {
        restored.add(user);
        daemon.operator = user;
      },
    );
  });

  test('a new account gets the operator back, as root', () async {
    await tailscale.addAccount();

    expect(restored, ['me']);
    expect(daemon.requests.where((r) => !r.startsWith('GET')), [
      'PUT profiles/',
      'PATCH prefs',
      'POST login-interactive',
    ], reason: 'the operator is restored before the prefs edit needs it');
    expect(tailscale.canWrite, isTrue);
  });

  test(
    'switching to a profile with the operator does not ask for root',
    () async {
      await tailscale.switchProfile('b');
      expect(restored, isEmpty);

      daemon.noOperator.add('c');
      await tailscale.switchProfile('c');
      expect(restored, ['me']);
    },
  );

  test('without operator access the state still updates', () async {
    daemon.operator = '';
    daemon.backendState = 'NeedsLogin';

    await tailscale.refresh();

    expect(tailscale.status?.backendState, BackendState.needsLogin);
    expect(tailscale.canWrite, isFalse);
    expect(tailscale.profiles, isEmpty);
    expect(tailscale.currentProfileId, isNull);
  });

  test(
    'a peer offline for the server that answers a ping is reachable',
    () async {
      // An iPhone in the background.
      daemon.peers = [
        {
          'ID': 'nPhone',
          'Online': false,
          'TailscaleIPs': ['100.64.0.7'],
        },
      ];
      await tailscale.refresh();
      expect(tailscale.status!.peers.single.reachable, isFalse);

      expect((await tailscale.ping('100.64.0.7')).ok, isTrue);
      expect(tailscale.status!.peers.single.reachable, isTrue);

      await tailscale.refresh();
      expect(
        tailscale.status!.peers.single.reachable,
        isTrue,
        reason: 'kept across refreshes',
      );
    },
  );

  test('opens a login page only after asking for one', () async {
    final opened = <String>[];
    tailscale = TailscaleController(daemon.client, openUrl: opened.add);
    tailscale.start();
    final events = await daemon.bus;
    addTearDown(() async {
      // End the stream, and let the controller see it end, before the client
      // is closed: closing it mid-read fails the test.
      final lost = nextChange(tailscale);
      await events.close();
      await lost;
      tailscale.dispose();
    });

    Future<void> send(Map<String, Object?> event) async {
      final refreshed = nextChange(tailscale);
      events.write('${jsonEncode(event)}\n');
      await events.flush();
      await refreshed;
    }

    await send({'BrowseToURL': 'https://login/for-another-client'});
    expect(opened, isEmpty);

    await tailscale.renew();
    await send({'BrowseToURL': 'https://login/mine'});
    await send({'BrowseToURL': 'https://login/again'});
    expect(opened, ['https://login/mine']);
  });

  test('transfer progress updates without re-reading the state', () async {
    tailscale.start();
    final events = await daemon.bus;
    addTearDown(() async {
      // As above. The last event leaves a file incoming, so losing the bus
      // changes something and notifies.
      final lost = nextChange(tailscale);
      await events.close();
      await lost;
      tailscale.dispose();
    });

    Future<void> send(Map<String, Object?> event) async {
      final changed = nextChange(tailscale);
      events.write('${jsonEncode(event)}\n');
      await events.flush();
      await changed;
    }

    await send({
      'IncomingFiles': [
        {'Name': 'a.jpg', 'DeclaredSize': 10, 'Received': 5},
      ],
    });
    expect(tailscale.incomingFiles.single.progressLabel, '50%');

    // tailscaled's last word on a file still lists it, as done.
    await send({
      'IncomingFiles': [
        {'Name': 'a.jpg', 'DeclaredSize': 10, 'Received': 10, 'Done': true},
      ],
    });
    expect(tailscale.incomingFiles, isEmpty);

    await send({'IncomingFiles': []});
    expect(tailscale.incomingFiles, isEmpty);

    await send({
      'IncomingFiles': [
        {'Name': 'b.jpg'},
        {'Name': 'c.jpg', 'DeclaredSize': 10, 'Received': 1},
      ],
    });
    // Saving a file ends it even if no notification said so.
    tailscale.fileSaved('c.jpg');
    expect(tailscale.incomingFiles.single.name, 'b.jpg');
    expect(daemon.requests, isEmpty, reason: 'no refresh for progress');
  });
}

Future<void> nextChange(Listenable listenable) {
  final done = Completer<void>();
  void listener() {
    listenable.removeListener(listener);
    done.complete();
  }

  listenable.addListener(listener);
  return done.future;
}
