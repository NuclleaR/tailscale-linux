import 'dart:async';
import 'dart:io';

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
    this.onFilesWaiting,
  }) : _openUrl = openUrl ?? _ignoreUrl,
       _restoreOperator = restoreOperator ?? _cannotRestoreOperator;

  /// Called when tailscaled holds files received with Taildrop.
  final VoidCallback? onFilesWaiting;

  final LocalApiClient _api;

  /// How long to wait before re-subscribing after the bus connection drops.
  final Duration reconnectDelay;

  /// Shows a login page: opens it in the browser or copies its link.
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

  /// Stable IDs of the devices Taildrop can send to. Empty unless connected.
  Set<String> get fileTargets => _fileTargets;
  Set<String> _fileTargets = const {};

  /// Files being received with Taildrop right now.
  List<IncomingFile> get incomingFiles => _incomingFiles;
  List<IncomingFile> _incomingFiles = const [];

  /// See [setWindowOpen].
  static const openRefreshInterval = Duration(seconds: 60);

  StreamSubscription<Object?>? _bus;
  Timer? _reconnect;
  Timer? _openRefresh;
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

  /// A peer that answers shows as reachable for [Node.recentFor], even when
  /// the coordination server says it is offline.
  Future<PingResult> ping(String ip) async {
    final result = await _api.ping(ip);
    final status = _status;
    final peer = status?.peers
        .where((p) => p.tailscaleIps.contains(ip))
        .firstOrNull;
    if (result.ok && status != null && peer != null) {
      _pingReplies[peer.id] = DateTime.now();
      if (!peer.reachable) {
        _status = _withPingReplies(status);
        notifyListeners();
      }
    }
    return result;
  }

  /// The received file [name] has been saved: it is no longer incoming,
  /// whatever the last notification said.
  void fileSaved(String name) {
    final before = _incomingFiles.length;
    _incomingFiles = _incomingFiles.where((f) => f.name != name).toList();
    if (_incomingFiles.length != before) notifyListeners();
  }

  /// When each peer last answered a ping from this app, by stable ID.
  final Map<String, DateTime> _pingReplies = {};

  TailscaleStatus _withPingReplies(TailscaleStatus status) {
    final now = DateTime.now();
    _pingReplies.removeWhere((_, t) => now.difference(t) > Node.recentFor);
    return _pingReplies.isEmpty
        ? status
        : status.withAnsweredPings(_pingReplies.keys.toSet());
  }

  /// While the window is open, re-reads status every [openRefreshInterval],
  /// and once right away when it opens. tailscaled does not report
  /// handshakes, which decide whether a peer shows as reachable. With only
  /// the tray up, nothing is polled.
  void setWindowOpen(bool open) {
    if (open == (_openRefresh != null)) return;
    _openRefresh?.cancel();
    _openRefresh = null;
    if (!open) return;
    refresh();
    _openRefresh = Timer.periodic(openRefreshInterval, (_) => refresh());
  }

  /// Sends [file] with Taildrop to the device [nodeId].
  Future<void> sendFile(
    String nodeId,
    File file, {
    void Function(int sent, int total)? onProgress,
  }) => _api.putFile(
    nodeId,
    file.uri.pathSegments.last,
    file,
    onProgress: onProgress,
  );

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
        var fileTargets = const <String>{};
        if (status.isRunning) {
          try {
            fileTargets = await _api.fileTargets();
          } on Exception catch (e) {
            // Taildrop may be off for this tailnet; the rest still works.
            debugPrint('tailscale: no Taildrop targets: $e');
          }
        }
        if (_disposed) return;
        _status = _withPingReplies(status);
        _prefs = prefs;
        _canWrite = canWrite;
        _profiles = profiles;
        _currentProfileId = currentId;
        _fileTargets = fileTargets;
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
        if (event['FilesWaiting'] != null) onFilesWaiting?.call();
        // Absent means "no change"; an empty list means nothing is incoming.
        if (event['IncomingFiles'] case final List<Object?> files) {
          _incomingFiles = [
            for (final f in files)
              if (f is Map<String, Object?>) IncomingFile.fromJson(f),
          ].where((f) => !f.finished).toList();
          notifyListeners();
        }
        // Transfer progress arrives often and changes nothing else.
        if (event.isNotEmpty &&
            event.keys.every(_transferProgressKeys.contains)) {
          return;
        }
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
    if (_status != null || _prefs != null || _incomingFiles.isNotEmpty) {
      _status = null;
      _prefs = null;
      _incomingFiles = const [];
      notifyListeners();
    }
    _reconnect = Timer(reconnectDelay, _watch);
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnect?.cancel();
    _openRefresh?.cancel();
    _bus?.cancel();
    super.dispose();
  }
}

const _transferProgressKeys = {'IncomingFiles', 'OutgoingFiles'};

void _ignoreUrl(String url) {}

Future<void> _cannotRestoreOperator(String user) async =>
    throw OperatorNotRestored(user);
