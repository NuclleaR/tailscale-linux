/// tailscaled's `BackendState`.
enum BackendState {
  noState('NoState'),
  needsLogin('NeedsLogin'),
  needsMachineAuth('NeedsMachineAuth'),
  stopped('Stopped'),
  starting('Starting'),
  running('Running'),
  unknown('');

  const BackendState(this.wireName);

  final String wireName;

  static BackendState parse(Object? value) => values.firstWhere(
    (s) => s.wireName == value && s != unknown,
    orElse: () => unknown,
  );
}

/// A user known to the tailnet (`tailcfg.UserProfile`).
class UserProfile {
  const UserProfile({
    required this.id,
    required this.loginName,
    required this.displayName,
    this.profilePicUrl = '',
  });

  factory UserProfile.fromJson(Map<String, Object?> json) => UserProfile(
    id: json['ID'] as int? ?? 0,
    loginName: json['LoginName'] as String? ?? '',
    displayName: json['DisplayName'] as String? ?? '',
    profilePicUrl: json['ProfilePicURL'] as String? ?? '',
  );

  final int id;
  final String loginName;
  final String displayName;

  /// Empty when the user has no picture.
  final String profilePicUrl;
}

/// One node of the tailnet as `status` reports it: this device or a peer.
class Node {
  const Node({
    required this.id,
    required this.hostName,
    required this.dnsName,
    required this.tailscaleIps,
    required this.online,
    required this.userId,
    this.isExitNode = false,
    this.exitNodeOption = false,
    this.keyExpiry,
  });

  factory Node.fromJson(Map<String, Object?> json) => Node(
    id: json['ID'] as String? ?? '',
    hostName: json['HostName'] as String? ?? '',
    dnsName: json['DNSName'] as String? ?? '',
    tailscaleIps: [
      for (final ip in json['TailscaleIPs'] as List<Object?>? ?? const [])
        ip as String,
    ],
    online: json['Online'] as bool? ?? false,
    userId: json['UserID'] as int? ?? 0,
    isExitNode: json['ExitNode'] as bool? ?? false,
    exitNodeOption: json['ExitNodeOption'] as bool? ?? false,
    keyExpiry: switch (json['KeyExpiry']) {
      final String s => DateTime.tryParse(s),
      _ => null,
    },
  );

  /// Stable node ID, the value `ExitNodeID` takes.
  final String id;
  final String hostName;
  final String dnsName;
  final List<String> tailscaleIps;
  final bool online;
  final int userId;

  /// This peer is the exit node in use.
  final bool isExitNode;

  /// This peer offers to be an exit node.
  final bool exitNodeOption;

  /// Null when the key never expires.
  final DateTime? keyExpiry;

  /// The MagicDNS machine name, as the admin console shows it.
  String get name {
    final label = dnsName.split('.').first;
    return label.isEmpty ? hostName : label;
  }

  String? get ipv4 => tailscaleIps.where((ip) => ip.contains('.')).firstOrNull;
}

/// A snapshot of `GET /localapi/v0/status`.
class TailscaleStatus {
  const TailscaleStatus({
    required this.backendState,
    this.self,
    this.peers = const [],
    this.tailnetName,
    this.users = const {},
    this.version = '',
    this.authUrl = '',
  });

  factory TailscaleStatus.fromJson(Map<String, Object?> json) {
    final users = <int, UserProfile>{
      for (final u
          in (json['User'] as Map<String, Object?>? ?? const {}).values)
        if (u case final Map<String, Object?> map)
          UserProfile.fromJson(map).id: UserProfile.fromJson(map),
    };
    return TailscaleStatus(
      backendState: BackendState.parse(json['BackendState']),
      self: switch (json['Self']) {
        final Map<String, Object?> map => Node.fromJson(map),
        _ => null,
      },
      peers: [
        for (final p
            in (json['Peer'] as Map<String, Object?>? ?? const {}).values)
          Node.fromJson(p as Map<String, Object?>),
      ],
      tailnetName: switch (json['CurrentTailnet']) {
        final Map<String, Object?> map => map['Name'] as String?,
        _ => null,
      },
      users: users,
      version: json['Version'] as String? ?? '',
      authUrl: json['AuthURL'] as String? ?? '',
    );
  }

  final BackendState backendState;
  final Node? self;
  final List<Node> peers;
  final String? tailnetName;
  final Map<int, UserProfile> users;

  /// tailscaled's version, such as `1.104.4` or `1.104.4-t0123abcd-g4567`.
  final String version;

  /// The login page tailscaled is waiting on; empty when none.
  final String authUrl;

  bool get isRunning => backendState == BackendState.running;

  UserProfile? get currentUser => switch (self) {
    final Node self => users[self.userId],
    null => null,
  };

  Node? get exitNode => peers.where((p) => p.isExitNode).firstOrNull;
}

/// An account tailscaled knows about (`ipn.LoginProfile`).
class LoginProfile {
  const LoginProfile({
    required this.id,
    required this.user,
    required this.tailnet,
    required this.controlUrl,
  });

  factory LoginProfile.fromJson(Map<String, Object?> json) {
    final network = json['NetworkProfile'] as Map<String, Object?>? ?? const {};
    final displayName = network['DisplayName'] as String? ?? '';
    return LoginProfile(
      id: json['ID'] as String? ?? '',
      user: UserProfile.fromJson(
        json['UserProfile'] as Map<String, Object?>? ?? const {},
      ),
      tailnet: displayName.isNotEmpty
          ? displayName
          : network['DomainName'] as String? ?? '',
      controlUrl: json['ControlURL'] as String? ?? '',
    );
  }

  final String id;
  final UserProfile user;
  final String tailnet;
  final String controlUrl;

  /// Whether the account lives on Tailscale's own coordination server rather
  /// than a custom one, such as Headscale.
  bool get usesDefaultServer =>
      controlUrl.isEmpty ||
      controlUrl == 'https://controlplane.tailscale.com' ||
      controlUrl == 'https://login.tailscale.com';
}

/// The prefs the Settings pane shows, from `GET /localapi/v0/prefs`.
class TailscalePrefs {
  const TailscalePrefs({
    this.shieldsUp = false,
    this.corpDns = false,
    this.routeAll = false,
    this.operatorUser = '',
  });

  factory TailscalePrefs.fromJson(Map<String, Object?> json) => TailscalePrefs(
    shieldsUp: json['ShieldsUp'] as bool? ?? false,
    corpDns: json['CorpDNS'] as bool? ?? false,
    routeAll: json['RouteAll'] as bool? ?? false,
    operatorUser: json['OperatorUser'] as String? ?? '',
  );

  /// The user allowed to change tailscaled's state without root. Each
  /// profile has its own; a new profile has none.
  final String operatorUser;

  /// Block incoming connections.
  final bool shieldsUp;

  /// Use the tailnet's DNS settings.
  final bool corpDns;

  /// Accept subnet routes from other nodes.
  final bool routeAll;
}

/// The tailnet's DNS settings, from `GET /localapi/v0/dns-config`
/// (a `tailcfg.DNSConfig`).
class DnsConfig {
  const DnsConfig({
    this.resolvers = const [],
    this.routes = const {},
    this.searchDomains = const [],
  });

  factory DnsConfig.fromJson(Map<String, Object?> json) => DnsConfig(
    resolvers: _addresses(json['Resolvers']),
    routes: {
      for (final MapEntry(:key, :value)
          in (json['Routes'] as Map<String, Object?>? ?? const {}).entries)
        key: _addresses(value),
    },
    searchDomains: [
      for (final d in json['Domains'] as List<Object?>? ?? const [])
        if (d is String) d,
    ],
  );

  /// Resolvers for every name, when the tailnet overrides the system's.
  final List<String> resolvers;

  /// Split DNS: domain suffix to the resolvers for names under it.
  /// An empty list means tailscaled answers those names itself.
  final Map<String, List<String>> routes;

  final List<String> searchDomains;

  /// The split DNS routes to show the user, without trailing dots.
  ///
  /// Leaves out routes tailscaled answers itself (MagicDNS names) and the
  /// route Tailscale adds for its own `ts.net` domain.
  Map<String, List<String>> get splitDnsRoutes => {
    for (final MapEntry(:key, :value) in routes.entries)
      if (value.isNotEmpty && !_isTsNet(key)) _trimDot(key): value,
  };

  static bool _isTsNet(String domain) {
    final d = _trimDot(domain);
    return d == 'ts.net' || d.endsWith('.ts.net');
  }

  static String _trimDot(String domain) =>
      domain.endsWith('.') ? domain.substring(0, domain.length - 1) : domain;

  /// Each resolver is `{"Addr": "8.8.8.8"}`; the address may also be a
  /// DoH URL.
  static List<String> _addresses(Object? resolvers) => [
    for (final r in resolvers as List<Object?>? ?? const [])
      if (r case {'Addr': final String addr}) addr,
  ];
}

/// Whether a newer tailscaled exists, from `GET /localapi/v0/update/check`
/// (a `tailcfg.ClientVersion`).
class ClientVersion {
  const ClientVersion({this.runningLatest = false, this.latestVersion = ''});

  factory ClientVersion.fromJson(Map<String, Object?> json) => ClientVersion(
    runningLatest: json['RunningLatest'] as bool? ?? false,
    latestVersion: json['LatestVersion'] as String? ?? '',
  );

  final bool runningLatest;

  /// Empty when unknown.
  final String latestVersion;

  bool get updateAvailable => !runningLatest && latestVersion.isNotEmpty;
}
