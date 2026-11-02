import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import '../tailscale/status.dart';
import '../tailscale/tailscale_controller.dart';
import 'device_details.dart';
import 'device_list.dart';

/// The Devices section: a searchable, grouped list, and the selected
/// device's details.
class DevicesView extends StatefulWidget {
  const DevicesView({
    super.key,
    required this.tailscale,
    required this.appSettings,
  });

  final TailscaleController tailscale;
  final AppSettings appSettings;

  @override
  State<DevicesView> createState() => _DevicesViewState();
}

class _DevicesViewState extends State<DevicesView> {
  String _query = '';
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.tailscale, widget.appSettings]),
      builder: (context, _) {
        final status = widget.tailscale.status!;
        final pinned = widget.appSettings.pinnedDevices;
        final groups = groupDevices(status, pinned: pinned, query: _query);
        final all = [?status.self, ...status.peers];
        final selected = all.where((d) => d.id == _selectedId).firstOrNull;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 300,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search…',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (q) => setState(() => _query = q),
                    ),
                  ),
                  Expanded(
                    child: groups.isEmpty
                        ? const Center(child: Text('No devices'))
                        // A tile's selected colour is painted by its nearest
                        // Material. This one keeps it inside the list, so a
                        // tile scrolled out does not show over the search.
                        : Material(
                            type: MaterialType.transparency,
                            child: ListView(
                              padding: const EdgeInsets.only(bottom: 12),
                              children: [
                                for (final group in groups) ...[
                                  _GroupTitle(group.title),
                                  for (final device in group.devices)
                                    _DeviceTile(
                                      device: device,
                                      isSelf: identical(device, status.self),
                                      selected: device.id == _selectedId,
                                      onTap: () => setState(
                                        () => _selectedId = device.id,
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: selected == null
                  ? const Center(child: Text('Select a device'))
                  : DeviceDetails(
                      key: ValueKey(selected.id),
                      tailscale: widget.tailscale,
                      device: selected,
                      isSelf: identical(selected, status.self),
                      pinned: pinned.contains(selected.id),
                      onPinned: (v) =>
                          widget.appSettings.setPinned(selected.id, v),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.isSelf,
    required this.selected,
    required this.onTap,
  });

  final Node device;
  final bool isSelf;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: theme.colorScheme.secondaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        horizontalTitleGap: 8,
        minLeadingWidth: 10,
        leading: Icon(
          Icons.circle,
          size: 10,
          color: device.reachable ? Colors.green : theme.disabledColor,
        ),
        title: Row(
          children: [
            Flexible(child: Text(device.name, overflow: TextOverflow.ellipsis)),
            if (isSelf) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.computer,
                size: 16,
                semanticLabel: 'This device',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
        subtitle: Text(device.ipv4 ?? ''),
        onTap: onTap,
      ),
    );
  }
}
