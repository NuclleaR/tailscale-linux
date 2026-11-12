import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/desktop.dart';
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

/// Shows [text] with a Copy button, for when it could not be copied from the
/// tray: there, on Wayland, only `wl-copy` can, and a click in the window
/// can. [openable] adds an Open button, for a link. [copied] is the message
/// once copied.
Future<void> showCopyDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String text,
  required String copied,
  bool openable = false,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        const SizedBox(height: 12),
        SelectableText(text),
        const SizedBox(height: 12),
        Text(
          'Install wl-clipboard (wl-copy) to copy from the tray directly.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      if (openable)
        TextButton(
          onPressed: () {
            openUrl(text);
            Navigator.pop(context);
          },
          child: const Text('Open'),
        ),
      FilledButton(
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          final navigator = Navigator.of(context);
          await Clipboard.setData(ClipboardData(text: text));
          navigator.pop();
          messenger.showSnackBar(SnackBar(content: Text(copied)));
        },
        child: const Text('Copy'),
      ),
    ],
  ),
);

/// Copies [url], to open it in a browser other than the default one. Goes
/// next to the button that opens it.
class CopyLinkButton extends StatelessWidget {
  const CopyLinkButton(this.url, {super.key});

  final String url;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Copy link',
      icon: const Icon(Icons.copy, size: 18),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        await Clipboard.setData(ClipboardData(text: url));
        messenger.showSnackBar(const SnackBar(content: Text('Link copied')));
      },
    );
  }
}

/// When a key that expires at [expiry] does, as the macOS app puts it:
/// "Expires in 18 hours", or "Expired" once it has.
String expiryLabel(DateTime expiry, DateTime now) {
  final left = expiry.difference(now);
  if (left <= Duration.zero) return 'Expired';
  return 'Expires in ${_span(left)}';
}

/// How long ago a key that expired at [expiry] did, as the macOS app's tray
/// puts it: "Expired 1 day ago". Null while the key has not expired.
String? expiredLabel(DateTime expiry, DateTime now) {
  final ago = now.difference(expiry);
  if (ago < Duration.zero) return null;
  return 'Expired ${_span(ago)} ago';
}

/// [duration] in its largest whole unit: "90 days", "18 hours", "1 minute".
String _span(Duration duration) {
  String count(int n, String unit) => '$n $unit${n == 1 ? '' : 's'}';
  if (duration.inDays >= 1) return count(duration.inDays, 'day');
  if (duration.inHours >= 1) return count(duration.inHours, 'hour');
  return count(duration.inMinutes < 1 ? 1 : duration.inMinutes, 'minute');
}

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
