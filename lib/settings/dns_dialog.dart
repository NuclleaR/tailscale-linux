import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/desktop.dart';
import '../tailscale/local_api.dart';
import '../tailscale/status.dart';
import '../tailscale/tailscale_controller.dart';
import 'widgets.dart';

const _dnsHelpUrl = 'https://tailscale.com/kb/1054/dns';

Future<void> showDnsDialog(
  BuildContext context,
  TailscaleController tailscale,
) => showDialog<void>(
  context: context,
  builder: (_) => DnsDialog(tailscale: tailscale),
);

/// What the tailnet's DNS settings are and whether this computer uses them.
class DnsDialog extends StatefulWidget {
  const DnsDialog({super.key, required this.tailscale});

  final TailscaleController tailscale;

  @override
  State<DnsDialog> createState() => _DnsDialogState();
}

class _DnsDialogState extends State<DnsDialog> {
  late final Future<DnsConfig> _config = widget.tailscale.dnsConfig();

  @override
  Widget build(BuildContext context) {
    final tailscale = widget.tailscale;
    return AlertDialog(
      content: SizedBox(
        width: 480,
        child: ListenableBuilder(
          listenable: tailscale,
          builder: (context, _) {
            final prefs = tailscale.prefs;
            final using = prefs?.corpDns ?? false;
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _UsageCard(using: using),
                  const SizedBox(height: 12),
                  Card.outlined(
                    margin: EdgeInsets.zero,
                    child: SwitchListTile(
                      title: const Text('Use Tailscale DNS Settings'),
                      value: using,
                      onChanged: prefs == null
                          ? null
                          : (v) => runAction(
                              context,
                              () => tailscale.setUseTailscaleDns(v),
                            ),
                    ),
                  ),
                  FutureBuilder(
                    future: _config,
                    builder: (context, snapshot) => switch (snapshot) {
                      AsyncSnapshot(:final error?) => _Note(
                        error is LocalApiException && error.statusCode == 503
                            ? 'DNS settings are not known until Tailscale '
                                  'connects.'
                            : 'Cannot read DNS settings: $error',
                      ),
                      AsyncSnapshot(:final data?) => _ConfigLists(data),
                      _ => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        IconButton(
          tooltip: 'DNS in Tailscale',
          icon: const Icon(Icons.help_outline),
          onPressed: () => openUrl(_dnsHelpUrl),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.using});

  final bool using;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          using ? Icons.check_circle_outline : Icons.remove_circle_outline,
          size: 40,
          color: using ? Colors.green : Theme.of(context).disabledColor,
        ),
        title: Text(using ? 'Using Tailscale DNS' : 'Not using Tailscale DNS'),
        subtitle: Text(
          using
              ? 'This computer is using Tailscale to resolve DNS names.'
              : 'This computer is using its own DNS settings.',
        ),
      ),
    );
  }
}

class _ConfigLists extends StatelessWidget {
  const _ConfigLists(this.config);

  final DnsConfig config;

  @override
  Widget build(BuildContext context) {
    final routes = config.splitDnsRoutes;
    if (config.resolvers.isEmpty &&
        config.searchDomains.isEmpty &&
        routes.isEmpty) {
      return const _Note('This tailnet has no DNS settings.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (config.resolvers.isNotEmpty)
          _CopyList(title: 'Resolvers', items: config.resolvers),
        if (config.searchDomains.isNotEmpty)
          _CopyList(title: 'Search Domains', items: config.searchDomains),
        for (final MapEntry(:key, :value) in routes.entries)
          _CopyList(title: 'Route: $key', items: value),
      ],
    );
  }
}

/// A titled list whose every line can be copied.
class _CopyList extends StatelessWidget {
  const _CopyList({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Card.outlined(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (i, item) in items.indexed) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  dense: true,
                  title: Text(item, style: theme.textTheme.bodyMedium),
                  trailing: IconButton(
                    tooltip: 'Copy',
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: item)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Text(text, textAlign: TextAlign.center),
    );
  }
}
