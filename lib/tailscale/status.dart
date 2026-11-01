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
  });

  factory UserProfile.fromJson(Map<String, Object?> json) => UserProfile(
    id: json['ID'] as int? ?? 0,
    loginName: json['LoginName'] as String? ?? '',
    displayName: json['DisplayName'] as String? ?? '',
  );

  final int id;
  final String loginName;
  final String displayName;
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
    );
  }

  final BackendState backendState;
  final Node? self;
  final List<Node> peers;
  final String? tailnetName;
  final Map<int, UserProfile> users;

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
}
