import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import '../settings/widgets.dart';
import '../tailscale/status.dart';
import '../tailscale/tailscale_controller.dart';
import 'devices_view.dart';
import 'exit_nodes_view.dart';

enum MainSection {
  devices('Devices', Icons.devices_outlined),
  exitNodes('Exit Nodes', Icons.logout);

  const MainSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The main window, as the macOS app's "Open Tailscale": the connection
/// switch, the devices of the tailnet and the exit nodes.
class MainWindow extends StatefulWidget {
  const MainWindow({
    super.key,
    required this.tailscale,
    required this.appSettings,
    required this.onOpenSettings,
  });

  final TailscaleController tailscale;
  final AppSettings appSettings;
  final VoidCallback onOpenSettings;

  @override
  State<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends State<MainWindow> {
  MainSection _section = MainSection.devices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            tailscale: widget.tailscale,
            onOpenSettings: widget.onOpenSettings,
          ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 200,
                  color: theme.colorScheme.surfaceContainerLow,
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      for (final section in MainSection.values)
                        ListTile(
                          dense: true,
                          leading: Icon(section.icon),
                          title: Text(section.label),
                          selected: section == _section,
                          selectedTileColor:
                              theme.colorScheme.secondaryContainer,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          onTap: () => setState(() => _section = section),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: ListenableBuilder(
                    listenable: widget.tailscale,
                    builder: (context, _) =>
                        switch (_unavailable(widget.tailscale.status)) {
                          final String message => Center(child: Text(message)),
                          null => switch (_section) {
                            MainSection.devices => DevicesView(
                              tailscale: widget.tailscale,
                              appSettings: widget.appSettings,
                            ),
                            MainSection.exitNodes => ExitNodesView(
                              tailscale: widget.tailscale,
                            ),
                          },
                        },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Why there is nothing to show, or null when there is. Devices and exit
  /// nodes are shown only while connected: otherwise what tailscaled still
  /// holds is out of date.
  static String? _unavailable(TailscaleStatus? status) =>
      switch (status?.backendState) {
        null => 'Tailscale is not running.',
        BackendState.running when status!.self != null => null,
        BackendState.running || BackendState.starting => 'Connecting…',
        BackendState.stopped => 'Tailscale is stopped.',
        BackendState.needsLogin => 'Logged out. Log in from Settings.',
        BackendState.needsMachineAuth => 'Waiting for device approval.',
        BackendState.noState || BackendState.unknown => 'Starting…',
      };
}

/// The connection switch with the tailnet's name, Settings and the account
/// menu.
class _Header extends StatelessWidget {
  const _Header({required this.tailscale, required this.onOpenSettings});

  final TailscaleController tailscale;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: tailscale,
      builder: (context, _) {
        final status = tailscale.status;
        final state = status?.backendState;
        final canToggle =
            state == BackendState.running ||
            state == BackendState.starting ||
            state == BackendState.stopped;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Switch(
                value:
                    state == BackendState.running ||
                    state == BackendState.starting,
                onChanged: canToggle
                    ? (v) => runAction(context, () => tailscale.setConnected(v))
                    : null,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    status?.tailnetName ?? 'Tailscale',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    switch (state) {
                      null => 'Not running',
                      BackendState.running => 'Connected',
                      BackendState.starting => 'Connecting…',
                      BackendState.stopped => 'Disconnected',
                      BackendState.needsLogin => 'Logged out',
                      BackendState.needsMachineAuth => 'Waiting for approval',
                      BackendState.noState ||
                      BackendState.unknown => 'Starting…',
                    },
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final file in tailscale.incomingFiles)
                        _IncomingProgress(file),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.tune),
                onPressed: onOpenSettings,
              ),
              const SizedBox(width: 4),
              _AccountMenu(tailscale: tailscale),
            ],
          ),
        );
      },
    );
  }
}

/// A file being received with Taildrop: its name and a progress bar.
class _IncomingProgress extends StatelessWidget {
  const _IncomingProgress(this.file);

  final IncomingFile file;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Receiving ${file.name}… ${file.progressLabel}',
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: file.fraction),
        ],
      ),
    );
  }
}

/// The current account's avatar; opens a menu to switch or add accounts.
class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.tailscale});

  final TailscaleController tailscale;

  static const _addAccount = '';

  @override
  Widget build(BuildContext context) {
    final current = tailscale.profiles
        .where((p) => p.id == tailscale.currentProfileId)
        .firstOrNull;
    return PopupMenuButton<String>(
      tooltip: 'Accounts',
      enabled: tailscale.status != null,
      onSelected: (id) => runAction(
        context,
        id == _addAccount
            ? tailscale.addAccount
            : () => tailscale.switchProfile(id),
      ),
      itemBuilder: (context) => [
        for (final p in tailscale.profiles)
          CheckedPopupMenuItem(
            value: p.id,
            checked: p.id == current?.id,
            enabled: p.id != current?.id,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(p.user.loginName),
              subtitle: Text(p.tailnet),
            ),
          ),
        if (tailscale.profiles.isNotEmpty) const PopupMenuDivider(),
        const PopupMenuItem(value: _addAccount, child: Text('Add Account…')),
      ],
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: current == null
            ? const CircleAvatar(
                radius: 16,
                child: Icon(Icons.person, size: 18),
              )
            : UserAvatar(current.user, radius: 16),
      ),
    );
  }
}
