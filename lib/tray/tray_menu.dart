import '../tailscale/status.dart';

/// What clicking a tray menu item does.
sealed class TrayCommand {
  const TrayCommand();
}

final class SetConnected extends TrayCommand {
  const SetConnected(this.connected);
  final bool connected;
}

final class CopyText extends TrayCommand {
  const CopyText(this.text);
  final String text;
}

/// Null [nodeId] turns the exit node off.
final class SetExitNode extends TrayCommand {
  const SetExitNode(this.nodeId);
  final String? nodeId;
}

final class SwitchProfile extends TrayCommand {
  const SwitchProfile(this.profileId);
  final String profileId;
}

final class OpenSettings extends TrayCommand {
  const OpenSettings();
}

final class Quit extends TrayCommand {
  const Quit();
}

/// A platform-independent description of the tray menu.
sealed class TrayEntry {
  const TrayEntry();
}

final class TrayItem extends TrayEntry {
  const TrayItem(this.label, {this.command, this.checked});

  final String label;

  /// Null makes the item a disabled label.
  final TrayCommand? command;

  /// Non-null makes the item a checkbox.
  final bool? checked;

  bool get enabled => command != null;
}

final class TraySubmenu extends TrayEntry {
  const TraySubmenu(this.label, this.children);

  final String label;
  final List<TrayEntry> children;
}

final class TraySeparator extends TrayEntry {
  const TraySeparator();
}

/// The tray menu for the given state, laid out like the macOS app's.
///
/// [status] is null while tailscaled cannot be reached.
List<TrayEntry> buildTrayMenu({
  required TailscaleStatus? status,
  List<LoginProfile> profiles = const [],
  String? currentProfileId,
}) {
  const footer = [
    TraySeparator(),
    TrayItem('Settings…', command: OpenSettings()),
    TrayItem('Quit', command: Quit()),
  ];
  if (status == null) {
    return const [TrayItem('Tailscale is not running'), ...footer];
  }

  return [
    _connectionItem(status.backendState),
    if (profiles.isNotEmpty) _accountMenu(status, profiles, currentProfileId),
    if (status.isRunning) ...[
      const TraySeparator(),
      ?_thisDeviceItem(status.self),
      _networkDevicesMenu(status),
      _exitNodesMenu(status),
    ],
    ...footer,
  ];
}

TrayItem _connectionItem(BackendState state) => switch (state) {
  BackendState.running => const TrayItem(
    'Connected',
    checked: true,
    command: SetConnected(false),
  ),
  BackendState.starting => const TrayItem(
    'Connecting…',
    checked: true,
    command: SetConnected(false),
  ),
  BackendState.stopped => const TrayItem(
    'Connected',
    checked: false,
    command: SetConnected(true),
  ),
  BackendState.needsLogin => const TrayItem('Logged out'),
  BackendState.needsMachineAuth => const TrayItem(
    'Waiting for device approval',
  ),
  BackendState.noState || BackendState.unknown => const TrayItem('Starting…'),
};

TraySubmenu _accountMenu(
  TailscaleStatus status,
  List<LoginProfile> profiles,
  String? currentProfileId,
) {
  final current = profiles.where((p) => p.id == currentProfileId).firstOrNull;
  final label = current == null
      ? 'Accounts'
      : '${_userName(current.user)} (${current.tailnet})';
  return TraySubmenu(label, [
    for (final p in profiles)
      TrayItem(
        '${_userName(p.user)} (${p.tailnet})',
        checked: p.id == currentProfileId,
        command: p.id == currentProfileId ? null : SwitchProfile(p.id),
      ),
  ]);
}

TrayItem? _thisDeviceItem(Node? self) {
  if (self == null) return null;
  final ip = self.ipv4;
  return ip == null
      ? TrayItem('This Device: ${self.name}')
      : TrayItem('This Device: ${self.name} ($ip)', command: CopyText(ip));
}

TraySubmenu _networkDevicesMenu(TailscaleStatus status) {
  final mine = <Node>[];
  final others = <Node>[];
  for (final peer in status.peers) {
    (peer.userId == status.self?.userId ? mine : others).add(peer);
  }
  return TraySubmenu('Network Devices', [
    if (mine.isNotEmpty) ...[
      const TrayItem('My Devices'),
      ..._sorted(mine).map(_deviceItem),
    ],
    if (mine.isNotEmpty && others.isNotEmpty) const TraySeparator(),
    if (others.isNotEmpty) ...[
      const TrayItem('Tailnet Devices'),
      ..._sorted(others).map(_deviceItem),
    ],
    if (mine.isEmpty && others.isEmpty) const TrayItem('No other devices'),
  ]);
}

TraySubmenu _exitNodesMenu(TailscaleStatus status) {
  final options = _sorted(status.peers.where((p) => p.exitNodeOption));
  return TraySubmenu('Exit Nodes', [
    TrayItem(
      'None',
      checked: status.exitNode == null,
      command: const SetExitNode(null),
    ),
    if (options.isEmpty)
      const TrayItem('No exit nodes available')
    else
      for (final node in options)
        TrayItem(
          _withOnline(node),
          checked: node.isExitNode,
          command: SetExitNode(node.id),
        ),
  ]);
}

TrayItem _deviceItem(Node node) {
  final ip = node.ipv4;
  return TrayItem(_withOnline(node), command: ip == null ? null : CopyText(ip));
}

/// Online first, then by name.
List<Node> _sorted(Iterable<Node> nodes) => nodes.toList()
  ..sort((a, b) {
    if (a.online != b.online) return a.online ? -1 : 1;
    return a.name.compareTo(b.name);
  });

String _withOnline(Node node) =>
    node.online ? node.name : '${node.name} (offline)';

String _userName(UserProfile user) =>
    user.displayName.isNotEmpty ? user.displayName : user.loginName;
