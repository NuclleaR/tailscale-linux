import 'package:flutter/material.dart';

import '../tailscale/status.dart';
import '../tailscale/tailscale_controller.dart';
import 'widgets.dart';

/// The Accounts pane: accounts on the left, the selected one's details on the
/// right.
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
        final currentId = tailscale.currentProfileId;
        final status = tailscale.status;
        final loggedIn =
            status != null && status.backendState != BackendState.needsLogin;
        final selected =
            profiles.where((p) => p.id == _selectedId).firstOrNull ??
            profiles.where((p) => p.id == currentId).firstOrNull ??
            profiles.firstOrNull;
        final theme = Theme.of(context);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 260,
              child: Column(
                children: [
                  Expanded(
                    // Keeps the selected tile's colour, which its nearest
                    // Material paints, inside the list when it scrolls.
                    child: Material(
                      type: MaterialType.transparency,
                      child: ListView(
                        padding: const EdgeInsets.all(8),
                        children: [
                          for (final p in profiles)
                            ListTile(
                              selected: p.id == selected?.id,
                              selectedTileColor:
                                  theme.colorScheme.secondaryContainer,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              leading: UserAvatar(
                                p.user,
                                radius: 18,
                                active: p.id == currentId && loggedIn,
                              ),
                              title: Text(
                                p.user.loginName,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                p.tailnet,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => setState(() => _selectedId = p.id),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: status == null
                            ? null
                            : () => runAction(context, tailscale.addAccount),
                        child: const Text('Add Account…'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: selected == null
                  ? const Center(child: Text('No accounts'))
                  : _AccountDetails(
                      tailscale: tailscale,
                      profile: selected,
                      isCurrent: selected.id == currentId,
                      loggedIn: selected.id == currentId && loggedIn,
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _AccountDetails extends StatelessWidget {
  const _AccountDetails({
    required this.tailscale,
    required this.profile,
    required this.isCurrent,
    required this.loggedIn,
  });

  final TailscaleController tailscale;
  final LoginProfile profile;
  final bool isCurrent;

  /// This is the account in use, and it is logged in.
  final bool loggedIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final self = isCurrent ? tailscale.status?.self : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                UserAvatar(profile.user, radius: 36),
                const SizedBox(height: 12),
                Text(
                  userName(profile.user),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                Table(
                  columnWidths: const {
                    0: IntrinsicColumnWidth(),
                    1: IntrinsicColumnWidth(),
                  },
                  children: [
                    _row(context, 'Tailnet', Text(profile.tailnet)),
                    _row(context, 'Email', Text(profile.user.loginName)),
                    _row(
                      context,
                      'Status',
                      _WithButton(
                        StatusDot(
                          on: loggedIn,
                          label: !isCurrent
                              ? 'Not active'
                              : loggedIn
                              ? 'Logged In'
                              : 'Logged Out',
                        ),
                        isCurrent && loggedIn
                            ? OutlinedButton(
                                onPressed: () => _logOut(context),
                                child: const Text('Log Out…'),
                              )
                            : isCurrent
                            ? OutlinedButton(
                                onPressed: tailscale.status == null
                                    ? null
                                    : () => runAction(context, tailscale.login),
                                child: const Text('Log In…'),
                              )
                            : OutlinedButton(
                                onPressed: () => runAction(
                                  context,
                                  () => tailscale.switchProfile(profile.id),
                                ),
                                child: const Text('Switch to user'),
                              ),
                      ),
                    ),
                    if (!profile.usesDefaultServer)
                      _row(context, 'Server', Text(profile.controlUrl)),
                    _row(
                      context,
                      'Expiry',
                      _WithButton(
                        Text(
                          self == null
                              ? '—'
                              : self.keyExpiry == null
                              ? 'Never'
                              : _formatDate(self.keyExpiry!),
                        ),
                        OutlinedButton(
                          onPressed: loggedIn
                              ? () => runAction(context, tailscale.renew)
                              : null,
                          child: const Text('Renew…'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: () => _remove(context),
              child: const Text('Remove Account…'),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _logOut(BuildContext context) async {
    final confirmed = await confirm(
      context,
      title: 'Log out of ${profile.tailnet}?',
      message:
          'You will need to log in again to use this account on this '
          'computer. The account is also removed from this list.',
      action: 'Log Out',
    );
    if (confirmed && context.mounted) {
      await runAction(context, tailscale.logout);
    }
  }

  Future<void> _remove(BuildContext context) async {
    final confirmed = await confirm(
      context,
      title: 'Remove ${profile.user.loginName}?',
      message:
          'The account is removed from this computer but not logged out: '
          'this device stays in ${profile.tailnet} until its key expires. '
          'To sign the device out, use Log Out instead.',
      action: 'Remove',
    );
    if (confirmed && context.mounted) {
      await runAction(context, () => tailscale.removeProfile(profile.id));
    }
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

/// A value with a button under it.
class _WithButton extends StatelessWidget {
  const _WithButton(this.value, this.button);

  final Widget value;
  final Widget button;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [value, const SizedBox(height: 8), button],
    );
  }
}

String _formatDate(DateTime time) {
  final t = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
