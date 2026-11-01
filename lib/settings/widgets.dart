import 'package:flutter/material.dart';

import '../tailscale/local_api.dart';
import '../tailscale/status.dart';

/// Runs a user action and reports a failure in a snack bar.
Future<void> runAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
  } on Exception catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(_describe(e))));
  }
}

String _describe(Exception e) => switch (e) {
  LocalApiException(isForbidden: true) =>
    'tailscaled refused: this user is not the Tailscale operator.',
  LocalApiException(:final message) => message,
  _ => '$e',
};

/// Asks the user to confirm [action]. True when confirmed.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

String userName(UserProfile user) =>
    user.displayName.isNotEmpty ? user.displayName : user.loginName;

/// The user's profile picture, or their initial while it loads or when there
/// is none.
class UserAvatar extends StatelessWidget {
  const UserAvatar(
    this.user, {
    super.key,
    required this.radius,
    this.active = false,
  });

  final UserProfile user;
  final double radius;

  /// Shows the green badge of the account in use.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final name = userName(user);
    final initial = CircleAvatar(
      radius: radius,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(fontSize: radius * 0.9),
      ),
    );
    final avatar = user.profilePicUrl.isEmpty
        ? initial
        : ClipOval(
            child: Image.network(
              user.profilePicUrl,
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover,
              frameBuilder: (context, child, frame, _) =>
                  frame == null ? initial : child,
              errorBuilder: (context, _, _) => initial,
            ),
          );
    if (!active) return avatar;

    final badge = radius * 0.6;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: badge,
            height: badge,
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A green or grey dot followed by a label.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.on, required this.label});

  final bool on;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.circle,
          size: 10,
          color: on ? Colors.green : Theme.of(context).disabledColor,
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}
