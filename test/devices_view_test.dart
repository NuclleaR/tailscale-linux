import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailscale_linux/main_window/devices_view.dart';
import 'package:tailscale_linux/settings/app_settings.dart';
import 'package:tailscale_linux/tailscale/local_api.dart';
import 'package:tailscale_linux/tailscale/status.dart';
import 'package:tailscale_linux/tailscale/tailscale_controller.dart';

/// A controller that never talks to tailscaled and always has `status`.
class _FixedStatus extends TailscaleController {
  _FixedStatus(this._fixed)
    : super(LocalApiClient(socketPath: '/nonexistent/tailscaled.sock'));

  final TailscaleStatus _fixed;

  @override
  TailscaleStatus? get status => _fixed;
}

Node _node(String name) => Node(
  id: 'id-$name',
  hostName: name,
  dnsName: '$name.example.ts.net.',
  tailscaleIps: const ['100.64.0.1'],
  online: true,
  userId: 1,
);

void main() {
  testWidgets('a device tile paints its background inside the list', (
    tester,
  ) async {
    final status = TailscaleStatus(
      backendState: BackendState.running,
      self: _node('self'),
      peers: [for (var i = 0; i < 30; i++) _node('peer-$i')],
      users: const {
        1: UserProfile(id: 1, loginName: 'me@x', displayName: 'Me'),
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevicesView(
            tailscale: _FixedStatus(status),
            appSettings: AppSettings(File('/nonexistent/settings.json')),
          ),
        ),
      ),
    );

    // ListTile's selected colour is painted by its nearest Material, not by
    // the tile. Unless that Material covers just the list, a selected tile
    // scrolled out of the list still shows over the search field.
    final material = find
        .ancestor(
          of: find.byType(ListTile).first,
          matching: find.byType(Material),
        )
        .first;
    expect(tester.getRect(material), tester.getRect(find.byType(ListView)));
  });
}
