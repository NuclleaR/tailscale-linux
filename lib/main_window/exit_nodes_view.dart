import 'package:flutter/material.dart';

import '../platform/desktop.dart';
import '../settings/widgets.dart';
import '../tailscale/tailscale_controller.dart';

const _exitNodesHelpUrl = 'https://tailscale.com/kb/1103/exit-nodes';
const _adminMachinesUrl = 'https://login.tailscale.com/admin/machines';

/// The Exit Nodes section: pick the exit node to route traffic through.
class ExitNodesView extends StatelessWidget {
  const ExitNodesView({super.key, required this.tailscale});

  final TailscaleController tailscale;

  /// The value of the "None" choice.
  static const _none = '';

  @override
  Widget build(BuildContext context) {
    final status = tailscale.status!;
    final options = status.peers.where((p) => p.exitNodeOption).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (options.isEmpty) return const _NoExitNodes();

    return RadioGroup<String>(
      groupValue: status.exitNode?.id ?? _none,
      onChanged: (id) => runAction(
        context,
        () => tailscale.setExitNode(id == null || id == _none ? null : id),
      ),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Exit Nodes', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Card.outlined(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                const RadioListTile(
                  value: _none,
                  title: Text('None'),
                  subtitle: Text('Use your own internet connection'),
                ),
                for (final node in options) ...[
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  RadioListTile(
                    value: node.id,
                    title: Text(node.name),
                    subtitle: Text(
                      node.reachable ? node.ipv4 ?? '' : 'Offline',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoExitNodes extends StatelessWidget {
  const _NoExitNodes();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.logout,
            size: 32,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          const Text('No available exit nodes.'),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => openUrl(_exitNodesHelpUrl),
                child: const Text('Learn how to configure an exit node.'),
              ),
              const CopyLinkButton(_exitNodesHelpUrl),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                onPressed: () => openUrl(_adminMachinesUrl),
                child: const Text('Open in Admin Console'),
              ),
              const CopyLinkButton(_adminMachinesUrl),
            ],
          ),
        ],
      ),
    );
  }
}
