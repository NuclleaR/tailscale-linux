import 'package:flutter_test/flutter_test.dart';
import 'package:tailscale_linux/tailscale/status.dart';

void main() {
  test('parses GET /localapi/v0/status', () {
    final status = TailscaleStatus.fromJson({
      'BackendState': 'Running',
      'CurrentTailnet': {'Name': 'example.com'},
      'Self': {
        'ID': 'nSelf',
        'HostName': 'laptop',
        'DNSName': 'laptop.tail1234.ts.net.',
        'TailscaleIPs': ['100.80.8.156', 'fd7a:115c:a1e0::1'],
        'Online': true,
        'UserID': 7380287203202048,
        'KeyExpiry': '2026-11-03T12:10:41Z',
      },
      'Peer': {
        'nodekey:1': {
          'ID': 'nPeer',
          'HostName': 'localhost',
          'DNSName': 'server.tail1234.ts.net.',
          'TailscaleIPs': ['100.64.0.2'],
          'Online': false,
          'UserID': 42,
          'ExitNode': true,
          'ExitNodeOption': true,
        },
      },
      'User': {
        '7380287203202048': {
          'ID': 7380287203202048,
          'LoginName': 'me@example.com',
          'DisplayName': 'Me',
        },
      },
    });

    expect(status.isRunning, isTrue);
    expect(status.tailnetName, 'example.com');
    expect(status.self!.name, 'laptop');
    expect(status.self!.ipv4, '100.80.8.156');
    expect(status.self!.keyExpiry, DateTime.utc(2026, 11, 3, 12, 10, 41));
    expect(status.currentUser!.displayName, 'Me');

    final peer = status.peers.single;
    expect(peer.name, 'server', reason: 'MagicDNS name wins over HostName');
    expect(peer.online, isFalse);
    expect(status.exitNode, same(peer));
  });

  test('a missing KeyExpiry means the key never expires', () {
    final node = Node.fromJson({'ID': 'n', 'HostName': 'box'});

    expect(node.keyExpiry, isNull);
    expect(node.name, 'box');
    expect(node.ipv4, isNull);
  });

  test('unknown backend states do not throw', () {
    expect(BackendState.parse('SomethingNew'), BackendState.unknown);
    expect(BackendState.parse(null), BackendState.unknown);
    expect(BackendState.parse('NeedsLogin'), BackendState.needsLogin);
  });

  test('parses a login profile', () {
    final profile = LoginProfile.fromJson({
      'ID': '4494',
      'Name': 'aytm',
      'ControlURL': 'https://controlplane.tailscale.com',
      'NetworkProfile': {'DomainName': 'example.com', 'DisplayName': ''},
      'UserProfile': {
        'ID': 1,
        'LoginName': 'me@example.com',
        'DisplayName': 'Me',
      },
    });

    expect(profile.id, '4494');
    expect(profile.tailnet, 'example.com');
    expect(profile.user.loginName, 'me@example.com');
    expect(profile.user.profilePicUrl, '');
    expect(profile.usesDefaultServer, isTrue);
  });

  test('a custom control server is not the default one', () {
    final profile = LoginProfile.fromJson({
      'ControlURL': 'https://hs.example.com',
      'UserProfile': {'ProfilePicURL': 'https://example.com/me.png'},
    });

    expect(profile.usesDefaultServer, isFalse);
    expect(profile.user.profilePicUrl, 'https://example.com/me.png');
  });

  test('status carries the daemon version and a pending login page', () {
    final status = TailscaleStatus.fromJson({
      'BackendState': 'NeedsLogin',
      'Version': '1.104.4',
      'AuthURL': 'https://login.tailscale.com/a/abc',
    });

    expect(status.version, '1.104.4');
    expect(status.authUrl, 'https://login.tailscale.com/a/abc');
  });

  test('DNS config: only the split DNS routes a user set up', () {
    // As tailscaled 1.104 returns it.
    final config = DnsConfig.fromJson({
      'Routes': {
        'aytm.com': [
          {'Addr': '8.8.8.8'},
          {'Addr': '2001:4860:4860::8888'},
        ],
        'tailac164.ts.net.': null,
        'ts.net.': [
          {'Addr': '199.247.155.53'},
        ],
        'corp.example.': [
          {'Addr': 'https://dns.example/dns-query'},
        ],
      },
      'Domains': ['tailac164.ts.net', 'aytm.com'],
      'Proxied': true,
    });

    expect(config.resolvers, isEmpty);
    expect(config.searchDomains, ['tailac164.ts.net', 'aytm.com']);
    expect(config.splitDnsRoutes, {
      'aytm.com': ['8.8.8.8', '2001:4860:4860::8888'],
      'corp.example': ['https://dns.example/dns-query'],
    });
  });

  test('an update is available only with a newer version known', () {
    expect(
      ClientVersion.fromJson({'RunningLatest': true}).updateAvailable,
      isFalse,
    );
    expect(ClientVersion.fromJson({}).updateAvailable, isFalse);
    expect(
      ClientVersion.fromJson({
        'RunningLatest': false,
        'LatestVersion': '1.106.0',
      }).updateAvailable,
      isTrue,
    );
  });
}
