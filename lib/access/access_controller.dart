import 'package:flutter/foundation.dart';

enum AccessStatus { checking, granted, denied, error }

/// Tracks whether this user may manage tailscaled (root or operator).
class AccessController extends ChangeNotifier {
  AccessController(this._checkAccess);

  /// Resolves to true when the user has write access to tailscaled.
  final Future<bool> Function() _checkAccess;

  AccessStatus _status = AccessStatus.checking;
  String? _error;

  AccessStatus get status => _status;

  /// Why the last check failed; set only when [status] is [AccessStatus.error].
  String? get error => _error;

  Future<void> check() async {
    _status = AccessStatus.checking;
    _error = null;
    notifyListeners();
    try {
      _status = await _checkAccess()
          ? AccessStatus.granted
          : AccessStatus.denied;
    } on Exception catch (e) {
      _status = AccessStatus.error;
      _error = '$e';
    }
    notifyListeners();
  }
}
