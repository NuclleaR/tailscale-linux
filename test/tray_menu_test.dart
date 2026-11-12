import 'package:flutter_test/flutter_test.dart';
import 'package:tailscale_linux/tailscale/status.dart';
import 'package:tailscale_linux/tray/tray_menu.dart';

const me = 1;
const colleague = 2;
final now = DateTime.utc(2026, 11, 12, 12);

Node node(
  String name, {
  int user = me,
  bool online = true,
  bool exitOption = false,
  bool isExit = false,
  DateTime? keyExpiry,
}) => Node(
  id: 'id-$name',
  hostName: name,
  dnsName: '$name.example.ts.net.',
  tailscaleIps: ['100.64.0.${name.length}', 'fd7a::1'],
  online: online,
  userId: user,
  exitNodeOption: exitOption,
  isExitNode: isExit,
  keyExpiry: keyExpiry,
);

TailscaleStatus status(
  BackendState state, {
  List<Node> peers = const [],
  DateTime? keyExpiry,
}) => TailscaleStatus(
  backendState: state,
  self: node('laptop', keyExpiry: keyExpiry),
  peers: peers,
  tailnetName: 'example.com',
);

const profiles = [
  LoginProfile(
    id: 'a',
    user: UserProfile(id: me, loginName: 'me@example.com', displayName: 'Me'),
    tailnet: 'example.com',
    controlUrl: 'https://controlplane.tailscale.com',
  ),
  LoginProfile(
    id: 'b',
    user: UserProfile(id: 9, loginName: 'me@home.net', displayName: ''),
    tailnet: 'home.net',
    controlUrl: 'https://hs.home.net',
  ),
];

/// Readable shape of a menu, for asserting on.
List<String> describe(List<TrayEntry> entries, [String indent = '']) => [
  for (final e in entries)
    ...switch (e) {
      TraySeparator() => ['$indent---'],
      TraySubmenu(:final label, :final children) => [
        '$indent$label >',
        ...describe(children, '$indent  '),
      ],
      TrayItem(:final label, :final checked, :final enabled) => [
        '$indent${checked == null
                ? ''
                : checked
                ? '[x] '
                : '[ ] '}'
            '$label${enabled ? '' : ' (disabled)'}',
      ],
    },
];

T commandOf<T extends TrayCommand>(List<TrayEntry> entries, String label) {
  for (final e in entries) {
    if (e is TrayItem && e.label == label) return e.command as T;
    if (e is TraySubmenu) {
      try {
        return commandOf<T>(e.children, label);
      } on StateError {
        continue;
      }
    }
  }
  throw StateError('no item "$label"');
}

List<TrayEntry> submenu(List<TrayEntry> entries, String label) => entries
    .whereType<TraySubmenu>()
    .singleWhere((s) => s.label == label)
    .children;

void main() {
  test('running: full menu, like the macOS app', () {
    final menu = buildTrayMenu(
      now: now,
      status: status(
        BackendState.running,
        peers: [
          node('server', exitOption: true),
          node('phone', online: false),
          node('desk', user: colleague),
        ],
      ),
      profiles: profiles,
      currentProfileId: 'a',
    );

    expect(describe(menu), [
      '[x] Connected',
      '---',
      'Me (example.com) >',
      '  [x] Me (example.com) (disabled)',
      '  [ ] me@home.net (home.net)',
      '---',
      'This Device: laptop (100.64.0.6)',
      'Network Devices >',
      '  My Devices (disabled)',
      '  server',
      '  phone (offline)',
      '  ---',
      '  Tailnet Devices (disabled)',
      '  desk',
      'Exit Nodes >',
      '  [x] None',
      '  [ ] server',
      '---',
      'Settings…',
      'Open Tailscale',
      '---',
      'Quit',
    ]);
    expect(commandOf<SetConnected>(menu, 'Connected').connected, isFalse);
    expect(commandOf<CopyText>(menu, 'phone (offline)').text, '100.64.0.5');
    final exitNodes = submenu(menu, 'Exit Nodes');
    expect(commandOf<SetExitNode>(exitNodes, 'server').nodeId, 'id-server');
    expect(commandOf<SetExitNode>(exitNodes, 'None').nodeId, isNull);
    expect(
      commandOf<SwitchProfile>(menu, 'me@home.net (home.net)').profileId,
      'b',
    );
  });

  test('the exit node in use is checked', () {
    final menu = buildTrayMenu(
      now: now,
      status: status(
        BackendState.running,
        peers: [node('server', exitOption: true, isExit: true)],
      ),
    );

    expect(describe(submenu(menu, 'Exit Nodes')), ['[ ] None', '[x] server']);
  });

  test('stopped: a Connected checkbox that connects, no devices', () {
    final menu = buildTrayMenu(now: now, status: status(BackendState.stopped));

    expect(describe(menu), [
      '[ ] Connected',
      '---',
      'Settings…',
      'Open Tailscale',
      '---',
      'Quit',
    ]);
    expect(commandOf<SetConnected>(menu, 'Connected').connected, isTrue);
  });

  test('logged out: a disabled label', () {
    final menu = buildTrayMenu(
      now: now,
      status: status(BackendState.needsLogin),
    );

    expect(describe(menu).first, 'Logged out (disabled)');
  });

  test('key expired, account still here: when, and Renew Session', () {
    final menu = buildTrayMenu(
      now: now,
      status: status(
        BackendState.needsLogin,
        keyExpiry: now.subtract(const Duration(days: 1, hours: 5)),
      ),
      profiles: profiles,
      currentProfileId: 'a',
    );

    expect(describe(menu), [
      'Needs Authentication (disabled)',
      'Expired 1 day ago (disabled)',
      'Renew Session…',
      '---',
      'Me (example.com) >',
      '  [x] Me (example.com) (disabled)',
      '  [ ] me@home.net (home.net)',
      '---',
      'Settings…',
      'Open Tailscale',
      '---',
      'Quit',
    ]);
    expect(commandOf<TrayCommand>(menu, 'Renew Session…'), isA<Renew>());
  });

  test('session ended before the key expired: no expiry line', () {
    final menu = buildTrayMenu(
      now: now,
      status: status(
        BackendState.needsLogin,
        keyExpiry: now.add(const Duration(days: 30)),
      ),
      profiles: profiles,
      currentProfileId: 'a',
    );

    expect(describe(menu).take(3), [
      'Needs Authentication (disabled)',
      'Renew Session…',
      '---',
    ]);
  });

  test('after a logout there is no Renew: the new profile is not listed', () {
    final menu = buildTrayMenu(
      now: now,
      status: status(
        BackendState.needsLogin,
        keyExpiry: now.subtract(const Duration(days: 1)),
      ),
      profiles: profiles,
      currentProfileId: '',
    );

    expect(describe(menu).take(3), [
      'Logged out (disabled)',
      '---',
      'Accounts >',
    ]);
  });

  test('logged out: nothing of the previous account shows', () {
    // What tailscaled 1.104 reports after a logout: this host, and peers the
    // engine still remembers, with no names, IPs or users.
    final status = TailscaleStatus.fromJson({
      'BackendState': 'NeedsLogin',
      'Self': {'ID': '', 'HostName': 'serhii-arch', 'TailscaleIPs': null},
      'Peer': {
        'nodekey:1': {'ID': '', 'HostName': '', 'TailscaleIPs': null},
      },
      'User': null,
    });

    expect(describe(buildTrayMenu(now: now, status: status)), [
      'Logged out (disabled)',
      '---',
      'Settings…',
      'Open Tailscale',
      '---',
      'Quit',
    ]);
  });

  test('files being received show their progress', () {
    final menu = buildTrayMenu(
      now: now,
      status: status(BackendState.stopped),
      incomingFiles: const [
        IncomingFile(name: 'photo.jpg', declaredSize: 200, received: 90),
        IncomingFile(name: 'stream.bin', received: 2500000),
      ],
    );

    expect(describe(menu), [
      '[ ] Connected',
      '---',
      'Receiving photo.jpg… 45% (disabled)',
      'Receiving stream.bin… 2.5 MB (disabled)',
      '---',
      'Settings…',
      'Open Tailscale',
      '---',
      'Quit',
    ]);
  });

  test('daemon unreachable', () {
    expect(describe(buildTrayMenu(now: now, status: null)), [
      'Tailscale is not running (disabled)',
      '---',
      'Settings…',
      'Open Tailscale',
      '---',
      'Quit',
    ]);
  });
}
