import 'package:flutter/material.dart';

import '../tailscale/status.dart';
import '../tailscale/tailscale_controller.dart';

/// The Accounts pane of the settings window: accounts on the left,
/// the selected one's details on the right.
class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key, required this.tailscale});

  final TailscaleController tailscale;

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.tailscale,
      builder: (context, _) {
        final tailscale = widget.tailscale;
        final profiles = tailscale.profiles;
        final selected =
            profiles.where((p) => p.id == _selectedId).firstOrNull ??
            profiles
                .where((p) => p.id == tailscale.currentProfileId)
                .firstOrNull;
        final theme = Theme.of(context);

        return Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 240,
                child: ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    for (final p in profiles)
                      ListTile(
                        selected: p.id == selected?.id,
                        selectedTileColor: theme.colorScheme.secondaryContainer,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        leading: _Avatar(p.user, radius: 18),
                        title: Text(_userName(p.user)),
                        subtitle: Text(p.tailnet),
                        onTap: () => setState(() => _selectedId = p.id),
                      ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: selected == null
                    ? const Center(child: Text('No accounts'))
                    : _AccountDetails(
                        profile: selected,
                        isCurrent: selected.id == tailscale.currentProfileId,
                        status: tailscale.status,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AccountDetails extends StatelessWidget {
  const _AccountDetails({
    required this.profile,
    required this.isCurrent,
    required this.status,
  });

  final LoginProfile profile;
  final bool isCurrent;
  final TailscaleStatus? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loggedIn =
        isCurrent &&
        status != null &&
        status!.backendState != BackendState.needsLogin;
    final self = isCurrent ? status?.self : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          _Avatar(profile.user, radius: 36),
          const SizedBox(height: 12),
          Text(_userName(profile.user), style: theme.textTheme.titleMedium),
          const SizedBox(height: 24),
          Table(
            columnWidths: const {
              0: IntrinsicColumnWidth(),
              1: IntrinsicColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              _row(context, 'Tailnet', Text(profile.tailnet)),
              _row(context, 'Email', Text(profile.user.loginName)),
              _row(
                context,
                'Status',
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 10,
                      color: loggedIn ? Colors.green : theme.disabledColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      !isCurrent
                          ? 'Not active'
                          : loggedIn
                          ? 'Logged In'
                          : 'Logged Out',
                    ),
                  ],
                ),
              ),
              _row(context, 'Server', Text(profile.controlUrl)),
              _row(
                context,
                'Key Expiry',
                Text(
                  self == null
                      ? '—'
                      : self.keyExpiry == null
                      ? 'Never'
                      : _formatDate(self.keyExpiry!),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  TableRow _row(BuildContext context, String label, Widget value) {
    final labelStyle = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(fontWeight: FontWeight.w600);
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 16, top: 6, bottom: 6),
          child: Text(label, textAlign: TextAlign.right, style: labelStyle),
        ),
        Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: value),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.user, {required this.radius});

  final UserProfile user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final name = _userName(user);
    return CircleAvatar(
      radius: radius,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(fontSize: radius * 0.9),
      ),
    );
  }
}

String _userName(UserProfile user) =>
    user.displayName.isNotEmpty ? user.displayName : user.loginName;

String _formatDate(DateTime time) {
  final t = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
