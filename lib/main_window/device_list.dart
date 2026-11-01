import '../tailscale/status.dart';

/// A titled group in the device list.
class DeviceGroup {
  const DeviceGroup(this.title, this.devices);

  final String title;
  final List<Node> devices;
}

/// The device list of the main window, as data.
///
/// Groups, in order: pinned devices, this user's devices, tagged devices,
/// then each other user's devices by name. A pinned device shows only under
/// Pinned. Within a group this device comes first, then the rest by name.
/// [query] keeps the devices whose name, host name, MagicDNS name or an IP
/// contains it, ignoring case.
List<DeviceGroup> groupDevices(
  TailscaleStatus status, {
  Set<String> pinned = const {},
  String query = '',
}) {
  final self = status.self;
  final q = query.trim().toLowerCase();
  final devices = [
    ?self,
    ...status.peers,
  ].where((d) => q.isEmpty || _matches(d, q)).toList();

  final pinnedDevices = <Node>[];
  final mine = <Node>[];
  final tagged = <Node>[];
  final byUser = <int, List<Node>>{};
  for (final d in devices) {
    if (pinned.contains(d.id)) {
      pinnedDevices.add(d);
    } else if (d.tags.isNotEmpty) {
      tagged.add(d);
    } else if (self != null && d.userId == self.userId) {
      mine.add(d);
    } else {
      byUser.putIfAbsent(d.userId, () => []).add(d);
    }
  }

  List<Node> sorted(List<Node> nodes) => nodes
    ..sort((a, b) {
      if (identical(a, self) != identical(b, self)) {
        return identical(a, self) ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });

  String userTitle(int userId) => switch (status.users[userId]) {
    final UserProfile u when u.displayName.isNotEmpty => u.displayName,
    final UserProfile u when u.loginName.isNotEmpty => u.loginName,
    _ => 'Other devices',
  };

  final others = [
    for (final MapEntry(:key, :value) in byUser.entries)
      DeviceGroup(userTitle(key), sorted(value)),
  ]..sort((a, b) => a.title.compareTo(b.title));

  return [
    if (pinnedDevices.isNotEmpty) DeviceGroup('Pinned', sorted(pinnedDevices)),
    if (mine.isNotEmpty)
      DeviceGroup(
        self == null ? 'My Devices' : userTitle(self.userId),
        sorted(mine),
      ),
    if (tagged.isNotEmpty) DeviceGroup('Tagged Devices', sorted(tagged)),
    ...others,
  ];
}

bool _matches(Node d, String q) =>
    d.name.toLowerCase().contains(q) ||
    d.hostName.toLowerCase().contains(q) ||
    d.dnsName.toLowerCase().contains(q) ||
    d.tailscaleIps.any((ip) => ip.contains(q));

/// When a node key expires, as the macOS app words it: "in 3 days",
/// "Never", "Expired".
String formatKeyExpiry(DateTime? expiry, DateTime now) {
  if (expiry == null) return 'Never';
  final left = expiry.difference(now);
  if (left.isNegative) return 'Expired';
  String plural(int n, String unit) => 'in $n $unit${n == 1 ? '' : 's'}';
  if (left.inDays >= 1) return plural(left.inDays, 'day');
  if (left.inHours >= 1) return plural(left.inHours, 'hour');
  return plural(left.inMinutes < 1 ? 1 : left.inMinutes, 'minute');
}
