import 'dart:async';

import 'package:flutter/foundation.dart';

import 'local_api.dart';
import 'operator.dart';
import 'status.dart';

/// The app's view of tailscaled, kept current from the IPN notification bus.
class TailscaleController extends ChangeNotifier {
  TailscaleController(
    this._api, {
    this.reconnectDelay = const Duration(seconds: 2),
    void Function(String url)? openUrl,
    Future<void> Function(String user)? restoreOperator,
  }) : _openUrl = openUrl ?? _ignoreUrl,
       _restoreOperator = restoreOperator ?? _cannotRestoreOperator;

  final LocalApiClient _api;

  /// How long to wait before re-subscribing after the bus connection drops.
  final Duration reconnectDelay;

  /// Opens a login page in the browser.
  final void Function(String url) _openUrl;

  /// Makes `user` the operator of the current profile, as root.
  final Future<void> Function(String user) _restoreOperator;

  /// False when tailscaled refuses changes from this user: it is not the
  /// operator of the current profile.
  bool get canWrite => _canWrite;
  bool _canWrite = true;

  /// Null while tailscaled cannot be reached.
  TailscaleStatus? get status => _status;
  TailscaleStatus? _status;

  /// Null while tailscaled cannot be reached.
  TailscalePrefs? get prefs => _prefs;
  TailscalePrefs? _prefs;

  List<LoginProfile> get profiles => _profiles;
  List<LoginProfile> _profiles = const [];

  String? get currentProfileId => _currentProfileId;
  String? _currentProfileId;

  StreamSubscription<Object?>? _bus;
  Timer? _reconnect;
  bool _refreshing = false;
  bool _refreshAgain = false;
  bool _disposed = false;

  /// This app asked for a login page and has not opened one yet. Login pages
  /// that other clients ask for are not opened.
  bool _awaitingLoginUrl = false;

  void start() => _watch();

  Future<void> setConnected(bool connected) =>
      _edit({'WantRunningSet': true, 'WantRunning': connected});

  Future<void> setAllowIncoming(bool allow) =>
      _edit({'ShieldsUpSet': true, 'ShieldsUp': !allow});

  Future<void> setUseTailscaleDns(bool use) =>
      _edit({'CorpDNSSet': true, 'CorpDNS': use});

  Future<void> setUseTailscaleSubnets(bool use) =>
      _edit({'RouteAllSet': true, 'RouteAll': use});

  /// Null [nodeId] stops using an exit node.
  Future<void> setExitNode(String? nodeId) => _edit({
    'ExitNodeIDSet': true,
    'ExitNodeID': nodeId ?? '',
    'ExitNodeIPSet': true,
    'ExitNodeIP': '',
  });

  Future<void> switchProfile(String id) =>
      _changeProfile(() => _api.switchProfile(id));

  /// Logs the current account out; tailscaled forgets it too.
  Future<void> logout() => _changeProfile(_api.logout);

  /// Forgets an account on this device without logging it out.
  Future<void> removeProfile(String id) =>
      _changeProfile(() => _api.deleteProfile(id));

  /// Switches to a new, empty account and opens its login page. The account
  /// connects once the login completes.
  Future<void> addAccount() async {
    await _changeProfile(_api.newProfile);
    await _api.editPrefs({'WantRunningSet': true, 'WantRunning': true});
    await _login();
  }

  /// Runs [action], which may switch tailscaled to another profile.
  ///
  /// The operator is a per-profile pref, and a new profile has none, so after
  /// a switch this user could lose the right to change anything, even to
  /// switch back. When that happens the operator is set again, as root.
  Future<void> _changeProfile(Future<void> Function() action) async {
    final operator = (await _api.prefs()).operatorUser;
    await action();
    if (operator.isNotEmpty && (await _api.prefs()).operatorUser != operator) {
      await _restoreOperator(operator);
    }
    await refresh();
  }

  /// Logs the current account in again, which renews its node key.
  Future<void> renew() => _login();

  Future<DnsConfig> dnsConfig() => _api.dnsConfig();

  Future<bool> tailnetLockEnabled() => _api.tailnetLockEnabled();

  Future<ClientVersion> checkForUpdate() => _api.checkForUpdate();

  Future<void> _login() async {
    _awaitingLoginUrl = true;
    try {
      await _api.startLoginInteractive();
    } on Exception {
      _awaitingLoginUrl = false;
      rethrow;
    }
    await refresh();
  }

  void _onLoginUrl(String url) {
    if (!_awaitingLoginUrl || url.isEmpty) return;
    _awaitingLoginUrl = false;
    _openUrl(url);
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
        final prefs = await _api.prefs();
        var canWrite = true;
        var profiles = const <LoginProfile>[];
        String? currentId;
        try {
          profiles = await _api.profiles();
          currentId = (await _api.currentProfile()).id;
        } on LocalApiException catch (e) {
          // Only the operator may list profiles.
          if (!e.isForbidden) rethrow;
          canWrite = false;
        }
        if (_disposed) return;
        _status = status;
        _prefs = prefs;
        _canWrite = canWrite;
        _profiles = profiles;
        _currentProfileId = currentId;
        // In case the bus event carrying the URL was missed.
        _onLoginUrl(status.authUrl);
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
      (event) {
        if (event['BrowseToURL'] case final String url) _onLoginUrl(url);
        refresh();
      },
      onError: _onBusLost,
      onDone: () => _onBusLost(null),
      cancelOnError: true,
    );
  }

  void _onBusLost(Object? error) {
    if (_disposed) return;
    if (error != null) debugPrint('tailscale: IPN bus lost: $error');
    _bus = null;
    if (_status != null || _prefs != null) {
      _status = null;
      _prefs = null;
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

void _ignoreUrl(String url) {}

Future<void> _cannotRestoreOperator(String user) async =>
    throw OperatorNotRestored(user);
