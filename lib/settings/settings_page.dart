import 'package:flutter/material.dart';

import '../platform/autostart.dart';
import '../platform/desktop.dart';
import '../tailscale/tailscale_controller.dart';
import 'app_settings.dart';
import 'dns_dialog.dart';
import 'widgets.dart';

const _tailnetLockAdminUrl =
    'https://login.tailscale.com/admin/settings/tailnet-lock';

/// The Settings pane: tailscaled prefs and the app's own options.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.tailscale,
    required this.appSettings,
    required this.autostart,
  });

  final TailscaleController tailscale;
  final AppSettings appSettings;
  final Autostart autostart;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final Future<bool> _tailnetLock = widget.tailscale.tailnetLockEnabled();

  @override
  Widget build(BuildContext context) {
    final tailscale = widget.tailscale;
    final appSettings = widget.appSettings;
    final autostart = widget.autostart;

    return ListenableBuilder(
      listenable: Listenable.merge([tailscale, appSettings, autostart]),
      builder: (context, _) {
        final prefs = tailscale.prefs;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Section(
                label: 'General',
                children: [
                  _Check(
                    label: 'Allow incoming connections',
                    value: prefs == null ? null : !prefs.shieldsUp,
                    onChanged: (v) =>
                        runAction(context, () => tailscale.setAllowIncoming(v)),
                  ),
                  _Check(
                    label: 'Use Tailscale DNS settings',
                    value: prefs?.corpDns,
                    onChanged: (v) => runAction(
                      context,
                      () => tailscale.setUseTailscaleDns(v),
                    ),
                    trailing: OutlinedButton(
                      onPressed: () => showDnsDialog(context, tailscale),
                      child: const Text('Manage…'),
                    ),
                  ),
                  _Check(
                    label: 'Use Tailscale subnets',
                    description:
                        "Route traffic according to your network's rules. "
                        'Some networks require this to access IP addresses '
                        "that don't start with 100.x.y.z.",
                    value: prefs?.routeAll,
                    onChanged: (v) => runAction(
                      context,
                      () => tailscale.setUseTailscaleSubnets(v),
                    ),
                  ),
                  _Check(
                    label: 'Launch Tailscale at login',
                    value: autostart.enabled,
                    onChanged: (v) =>
                        runAction(context, () => autostart.setEnabled(v)),
                  ),
                ],
              ),
              _Section(
                label: 'Tray icon',
                children: [
                  SegmentedButton<TrayIconColor>(
                    segments: const [
                      ButtonSegment(
                        value: TrayIconColor.white,
                        label: Text('White'),
                      ),
                      ButtonSegment(
                        value: TrayIconColor.black,
                        label: Text('Black'),
                      ),
                    ],
                    selected: {appSettings.trayIcon},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) => runAction(
                      context,
                      () => appSettings.setTrayIcon(selection.single),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const _Description(
                    'White suits dark panels, black suits light ones.',
                  ),
                ],
              ),
              _Section(
                label: 'Login links',
                children: [
                  SegmentedButton<LoginLinkAction>(
                    segments: const [
                      ButtonSegment(
                        value: LoginLinkAction.open,
                        label: Text('Open in browser'),
                      ),
                      ButtonSegment(
                        value: LoginLinkAction.copy,
                        label: Text('Copy link'),
                      ),
                    ],
                    selected: {appSettings.loginLinks},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) => runAction(
                      context,
                      () => appSettings.setLoginLinks(selection.single),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const _Description(
                    'The login page for Add Account and Renew. Copy '
                    'puts its link on the clipboard, to paste into the '
                    'browser you want.',
                  ),
                ],
              ),
              _Section(
                label: 'Tailnet Lock',
                children: [
                  Row(
                    children: [
                      FutureBuilder(
                        future: _tailnetLock,
                        builder: (context, snapshot) => StatusDot(
                          on: snapshot.data ?? false,
                          label: switch (snapshot) {
                            AsyncSnapshot(hasError: true) => 'Unknown',
                            AsyncSnapshot(data: true) => 'Enabled',
                            AsyncSnapshot(data: false) => 'Not Enabled',
                            _ => '…',
                          },
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton(
                        onPressed: () => openUrl(_tailnetLockAdminUrl),
                        child: const Text('Manage…'),
                      ),
                      const CopyLinkButton(_tailnetLockAdminUrl),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A labelled group of options, the label right-aligned in its own column and
/// on the same baseline as the first option's text.
class _Section extends StatelessWidget {
  const _Section({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// A checkbox option. A null [value] shows it disabled, for when tailscaled
/// cannot be reached.
class _Check extends StatelessWidget {
  const _Check({
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
    this.trailing,
  });

  final String label;
  final bool? value;
  final void Function(bool value) onChanged;
  final String? description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    return CheckboxListTile(
      value: value ?? false,
      onChanged: value == null ? null : (v) => onChanged(v ?? false),
      title: Text(label),
      subtitle: description == null ? null : _Description(description!),
      secondary: trailing,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }
}

class _Description extends StatelessWidget {
  const _Description(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
