import 'dart:io';

/// After a profile change this user is no longer the operator, and setting
/// it again as root failed or was cancelled.
class OperatorNotRestored implements Exception {
  OperatorNotRestored(this.user, [this.reason = '']);

  final String user;
  final String reason;

  @override
  String toString() =>
      'Could not make $user the Tailscale operator again'
      '${reason.isEmpty ? '' : ' ($reason)'}. '
      'Run: sudo tailscale set --operator=$user';
}

/// Makes [user] the operator of tailscaled's current profile.
///
/// Needs root, so it runs `tailscale set` through polkit's `pkexec`, which
/// asks for a password. This is the one place the app runs the CLI: the
/// LocalAPI refuses the change to a user who is not the operator.
Future<void> setOperatorAsRoot(String user) async {
  final ProcessResult result;
  try {
    result = await Process.run('pkexec', [
      'tailscale',
      'set',
      '--operator=$user',
    ]);
  } on ProcessException catch (e) {
    throw OperatorNotRestored(user, 'cannot run pkexec: ${e.message}');
  }
  if (result.exitCode == 0) return;
  throw OperatorNotRestored(user, switch (result.exitCode) {
    126 => 'the password dialog was dismissed',
    127 => 'not authorized',
    _ => '${result.stderr}'.trim(),
  });
}
