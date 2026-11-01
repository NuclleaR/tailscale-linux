import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../settings/widgets.dart';
import '../tailscale/status.dart';
import '../tailscale/tailscale_controller.dart';
import 'device_list.dart';
import 'ping_section.dart';
import 'taildrop_section.dart';

/// One device: its addresses and details.
class DeviceDetails extends StatelessWidget {
  const DeviceDetails({
    super.key,
    required this.tailscale,
    required this.device,
    required this.isSelf,
    required this.pinned,
    required this.onPinned,
  });

  final TailscaleController tailscale;
  final Node device;
  final bool isSelf;
  final bool pinned;
  final void Function(bool pinned) onPinned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = device.hostName.isNotEmpty && device.hostName != device.name
        ? '${device.name} (${device.hostName})'
        : device.name;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(title, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 6),
                    StatusDot(
                      on: device.reachable,
                      label: device.reachable ? 'Connected' : 'Offline',
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: pinned ? 'Unpin' : 'Pin to the top',
                isSelected: pinned,
                icon: const Icon(Icons.push_pin_outlined),
                selectedIcon: const Icon(Icons.push_pin),
                onPressed: () => onPinned(!pinned),
              ),
            ],
          ),
          _Section(
            title: 'Tailscale addresses',
            children: [
              if (device.magicDnsName.isNotEmpty)
                _CopyRow(device.magicDnsName, 'MagicDNS'),
              if (device.ipv4 case final ip?) _CopyRow(ip, 'IPv4'),
              if (device.ipv6 case final ip?) _CopyRow(ip, 'IPv6'),
            ],
          ),
          if (!isSelf && tailscale.fileTargets.contains(device.id)) ...[
            const _SectionTitle('Taildrop'),
            TaildropSection(tailscale: tailscale, nodeId: device.id),
          ],
          if (!isSelf && device.tailscaleIps.isNotEmpty) ...[
            const _SectionTitle('Ping'),
            PingSection(
              tailscale: tailscale,
              ip: device.ipv4 ?? device.tailscaleIps.first,
            ),
          ],
          _Section(
            title: 'Details',
            children: [
              if (device.os.isNotEmpty) _ValueRow('OS', device.os),
              _ValueRow(
                'Key expiry',
                formatKeyExpiry(device.keyExpiry, DateTime.now()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A titled card of rows separated by lines.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(title),
        Card.outlined(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, child) in children.indexed) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                child,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 10),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// An address and its kind; clicking copies the address.
class _CopyRow extends StatelessWidget {
  const _CopyRow(this.value, this.kind);

  final String value;
  final String kind;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(value),
      subtitle: Text(kind),
      trailing: const Icon(Icons.copy, size: 18),
      onTap: () async {
        final messenger = ScaffoldMessenger.of(context);
        await Clipboard.setData(ClipboardData(text: value));
        messenger.showSnackBar(SnackBar(content: Text('Copied $value')));
      },
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // ListTile shrinks trailing text by default; keep it the title's size.
    return ListTile(
      title: Text(label),
      trailing: Text(
        value,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
