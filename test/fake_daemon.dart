import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tailscale_linux/tailscale/local_api.dart';

/// Serves [handler] on a throwaway unix socket, standing in for tailscaled.
Future<LocalApiClient> fakeDaemon(void Function(HttpRequest) handler) async {
  final dir = await Directory.systemTemp.createTemp('localapi_test');
  final path = '${dir.path}/tailscaled.sock';
  final server = await HttpServer.bind(
    InternetAddress(path, type: InternetAddressType.unix),
    0,
  );
  server.listen(handler);
  final client = LocalApiClient(socketPath: path);
  addTearDown(() async {
    client.close();
    await server.close(force: true);
    await dir.delete(recursive: true);
  });
  return client;
}
