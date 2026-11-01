import 'dart:convert';
import 'dart:io';

import 'status.dart';

/// tailscaled answered a LocalAPI request with a non-2xx status.
class LocalApiException implements Exception {
  LocalApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get isForbidden => statusCode == HttpStatus.forbidden;

  @override
  String toString() => 'LocalAPI error $statusCode: $message';
}

/// HTTP client for tailscaled's LocalAPI, served over a unix socket.
///
/// This is the same API the `tailscale` CLI talks to.
class LocalApiClient {
  LocalApiClient({this.socketPath = defaultSocketPath}) {
    _http.connectionFactory = (uri, proxyHost, proxyPort) =>
        Socket.startConnect(
          InternetAddress(socketPath, type: InternetAddressType.unix),
          0,
        );
  }

  static const defaultSocketPath = '/var/run/tailscale/tailscaled.sock';

  /// tailscaled rejects LocalAPI requests carrying any other Host header.
  static const _host = 'local-tailscaled.sock';

  final String socketPath;
  final HttpClient _http = HttpClient();

  Future<Object?> getJson(String endpoint) async =>
      jsonDecode(await _send('GET', endpoint));

  Future<String> post(String endpoint, Object? body) =>
      _send('POST', endpoint, body);

  Future<TailscaleStatus> status() async =>
      TailscaleStatus.fromJson(await getJson('status') as Map<String, Object?>);

  Future<List<LoginProfile>> profiles() async => [
    for (final p in await getJson('profiles/') as List<Object?>)
      LoginProfile.fromJson(p as Map<String, Object?>),
  ];

  Future<LoginProfile> currentProfile() async => LoginProfile.fromJson(
    await getJson('profiles/current') as Map<String, Object?>,
  );

  Future<void> switchProfile(String id) async {
    await _send('POST', 'profiles/${Uri.encodeComponent(id)}');
  }

  /// Creates an empty profile and switches to it, ready for a new login.
  Future<void> newProfile() async {
    await _send('PUT', 'profiles/');
  }

  /// Forgets an account on this device without logging it out. Deleting the
  /// current profile switches tailscaled to an empty one.
  Future<void> deleteProfile(String id) async {
    await _send('DELETE', 'profiles/${Uri.encodeComponent(id)}');
  }

  /// Logs the current account out. tailscaled also deletes its profile.
  Future<void> logout() async {
    await _send('POST', 'logout');
  }

  /// Asks the control server for a login page. Its URL arrives on the IPN bus
  /// as `BrowseToURL`. When already logged in, this re-authenticates, which
  /// renews the node key.
  Future<void> startLoginInteractive() async {
    await _send('POST', 'login-interactive');
  }

  Future<TailscalePrefs> prefs() async =>
      TailscalePrefs.fromJson(await getJson('prefs') as Map<String, Object?>);

  /// Applies a `MaskedPrefs` edit: each changed field `X` comes with `XSet: true`.
  Future<void> editPrefs(Map<String, Object?> maskedPrefs) async {
    await _send('PATCH', 'prefs', maskedPrefs);
  }

  /// Fails with `503` until tailscaled has a network map.
  Future<DnsConfig> dnsConfig() async =>
      DnsConfig.fromJson(await getJson('dns-config') as Map<String, Object?>);

  Future<bool> tailnetLockEnabled() async {
    final status = await getJson('tka/status') as Map<String, Object?>;
    return status['Enabled'] == true;
  }

  Future<ClientVersion> checkForUpdate() async => ClientVersion.fromJson(
    await getJson('update/check') as Map<String, Object?>,
  );

  /// tailscaled's notification stream: one JSON object per state change.
  ///
  /// The first event carries the current state. The stream ends when the
  /// daemon closes the connection (for example, when it restarts).
  Stream<Map<String, Object?>> watchIpnBus() async* {
    const notifyInitialState = 2;
    const notifyNoPrivateKeys = 16;
    final request = await _http.getUrl(
      Uri.http(_host, '/localapi/v0/watch-ipn-bus', {
        'mask': '${notifyInitialState | notifyNoPrivateKeys}',
      }),
    );
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      final text = await response.transform(utf8.decoder).join();
      throw LocalApiException(response.statusCode, text.trim());
    }
    final lines = response
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.isNotEmpty) yield jsonDecode(line) as Map<String, Object?>;
    }
  }

  /// Whether the current user may change tailscaled's state: true for root
  /// and for the user set with `tailscale set --operator`.
  ///
  /// Asks the daemon to validate its own current prefs. `check-prefs` is
  /// gated on write access but applies nothing, so the call has no effect.
  Future<bool> canWrite() async {
    final prefs = await getJson('prefs');
    try {
      await post('check-prefs', prefs);
      return true;
    } on LocalApiException catch (e) {
      if (e.isForbidden) return false;
      rethrow;
    }
  }

  void close() => _http.close(force: true);

  Future<String> _send(String method, String endpoint, [Object? body]) async {
    final request = await _http.openUrl(
      method,
      Uri.http(_host, '/localapi/v0/$endpoint'),
    );
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LocalApiException(response.statusCode, text.trim());
    }
    return text;
  }
}
