import 'dart:async';

import 'package:flutter/foundation.dart';

import 'local_api.dart';
import 'status.dart';

/// The app's view of tailscaled, kept current from the IPN notification bus.
class TailscaleController extends ChangeNotifier {
  TailscaleController(
    this._api, {
    this.reconnectDelay = const Duration(seconds: 2),
  });

  final LocalApiClient _api;

  /// How long to wait before re-subscribing after the bus connection drops.
  final Duration reconnectDelay;

  /// Null while tailscaled cannot be reached.
  TailscaleStatus? get status => _status;
  TailscaleStatus? _status;

  List<LoginProfile> get profiles => _profiles;
  List<LoginProfile> _profiles = const [];

  String? get currentProfileId => _currentProfileId;
  String? _currentProfileId;

  StreamSubscription<Object?>? _bus;
  Timer? _reconnect;
  bool _refreshing = false;
  bool _refreshAgain = false;
  bool _disposed = false;

  void start() => _watch();

  Future<void> setConnected(bool connected) =>
      _edit({'WantRunningSet': true, 'WantRunning': connected});

  /// Null [nodeId] stops using an exit node.
  Future<void> setExitNode(String? nodeId) => _edit({
    'ExitNodeIDSet': true,
    'ExitNodeID': nodeId ?? '',
    'ExitNodeIPSet': true,
    'ExitNodeIP': '',
  });

  Future<void> switchProfile(String id) async {
    await _api.switchProfile(id);
    await refresh();
  }

  /// Re-reads status and profiles. Calls made while a refresh is running
  /// collapse into one more pass after it.
  Future<void> refresh() async {
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshAgain = false;
        final status = await _api.status();
        final profiles = await _api.profiles();
        final current = await _api.currentProfile();
        if (_disposed) return;
        _status = status;
        _profiles = profiles;
        _currentProfileId = current.id;
        notifyListeners();
      } while (_refreshAgain);
    } on Exception catch (e) {
      debugPrint('tailscale: refresh failed: $e');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _edit(Map<String, Object?> maskedPrefs) async {
    await _api.editPrefs(maskedPrefs);
    await refresh();
  }

  void _watch() {
    _bus = _api.watchIpnBus().listen(
      (_) => refresh(),
      onError: _onBusLost,
      onDone: () => _onBusLost(null),
      cancelOnError: true,
    );
  }

  void _onBusLost(Object? error) {
    if (_disposed) return;
    if (error != null) debugPrint('tailscale: IPN bus lost: $error');
    _bus = null;
    if (_status != null) {
      _status = null;
      notifyListeners();
    }
    _reconnect = Timer(reconnectDelay, _watch);
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnect?.cancel();
    _bus?.cancel();
    super.dispose();
  }
}
