import 'package:flutter_test/flutter_test.dart';
import 'package:tailscale_linux/main_window/device_list.dart';
import 'package:tailscale_linux/tailscale/status.dart';

const me = 1;
const arseniy = 2;
const evgeny = 3;
const taggedUser = 4;

Node node(
  String name, {
  int user = me,
  List<String> tags = const [],
  String ip = '100.64.0.1',
}) => Node(
  id: 'id-$name',
  hostName: name,
  dnsName: '$name.example.ts.net.',
  tailscaleIps: [ip],
  online: true,
  userId: user,
  tags: tags,
);

final status = TailscaleStatus(
  backendState: BackendState.running,
  self: node('serhii-arch'),
  peers: [
    node('lbox'),
    node('iphone-13-pro', ip: '100.80.8.190'),
    node('base4', user: taggedUser, tags: ['tag:server']),
    node('lframe', user: arseniy),
    node('evgeny-xps', user: evgeny),
    node('mfram3', user: arseniy),
  ],
  users: const {
    me: UserProfile(id: me, loginName: 'me@x', displayName: 'Serhii Koreniuk'),
    arseniy: UserProfile(
      id: arseniy,
      loginName: 'a@x',
      displayName: 'Arseniy Yakushev',
    ),
    evgeny: UserProfile(id: evgeny, loginName: 'evgeny@x', displayName: ''),
  },
);

/// Readable shape of the groups, for asserting on.
List<String> describe(List<DeviceGroup> groups) => [
  for (final g in groups)
    '${g.title}: ${g.devices.map((d) => d.name).join(', ')}',
];

void main() {
  test('this device first in its group, then by name; tagged after mine', () {
    expect(describe(groupDevices(status)), [
      'Serhii Koreniuk: serhii-arch, iphone-13-pro, lbox',
      'Tagged Devices: base4',
      'Arseniy Yakushev: lframe, mfram3',
      'evgeny@x: evgeny-xps',
    ]);
  });

  test('pinned devices move to their own group on top', () {
    expect(describe(groupDevices(status, pinned: {'id-base4', 'id-lbox'})), [
      'Pinned: base4, lbox',
      'Serhii Koreniuk: serhii-arch, iphone-13-pro',
      'Arseniy Yakushev: lframe, mfram3',
      'evgeny@x: evgeny-xps',
    ]);
  });

  test('search matches names and IPs, ignoring case', () {
    expect(describe(groupDevices(status, query: 'FRAM')), [
      'Arseniy Yakushev: lframe, mfram3',
    ]);
    expect(describe(groupDevices(status, query: '8.190')), [
      'Serhii Koreniuk: iphone-13-pro',
    ]);
    expect(groupDevices(status, query: 'nothing'), isEmpty);
  });

  test('key expiry as the macOS app words it', () {
    final now = DateTime.utc(2026, 11, 1, 12);
    expect(formatKeyExpiry(null, now), 'Never');
    expect(
      formatKeyExpiry(now.subtract(const Duration(hours: 1)), now),
      'Expired',
    );
    expect(
      formatKeyExpiry(now.add(const Duration(hours: 30)), now),
      'in 1 day',
    );
    expect(
      formatKeyExpiry(now.add(const Duration(days: 90)), now),
      'in 90 days',
    );
    expect(
      formatKeyExpiry(now.add(const Duration(hours: 2)), now),
      'in 2 hours',
    );
    expect(
      formatKeyExpiry(now.add(const Duration(seconds: 20)), now),
      'in 1 minute',
    );
  });

  test('status parses OS and tags', () {
    final n = Node.fromJson({
      'ID': 'n1',
      'DNSName': 'base4.example.ts.net.',
      'OS': 'linux',
      'Tags': ['tag:server'],
      'TailscaleIPs': ['100.80.0.4', 'fd7a:115c:a1e0::73ef:3a0f'],
    });
    expect(n.os, 'linux');
    expect(n.tags, ['tag:server']);
    expect(n.magicDnsName, 'base4.example.ts.net');
    expect(n.ipv6, 'fd7a:115c:a1e0::73ef:3a0f');
  });
}
