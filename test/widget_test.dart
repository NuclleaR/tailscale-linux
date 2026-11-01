import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailscale_linux/access/access_controller.dart';
import 'package:tailscale_linux/access/access_page.dart';

void main() {
  Future<void> show(WidgetTester tester, AccessController controller) =>
      tester.pumpWidget(MaterialApp(home: AccessPage(controller: controller)));

  testWidgets('denied shows the operator command; Recheck re-runs the check', (
    tester,
  ) async {
    var allowed = false;
    final controller = AccessController(() async => allowed);
    await controller.check();
    await show(tester, controller);

    expect(find.text(r'sudo tailscale set --operator=$USER'), findsOneWidget);

    allowed = true;
    await tester.tap(find.text('Recheck'));
    await tester.pumpAndSettle();

    expect(find.text('Access granted'), findsOneWidget);
    expect(find.text('Recheck'), findsNothing);
  });

  testWidgets('a failed check shows the error and Recheck', (tester) async {
    final controller = AccessController(
      () async => throw const SocketException('connection refused'),
    );
    await controller.check();
    await show(tester, controller);

    expect(find.text("Can't reach tailscaled"), findsOneWidget);
    expect(find.textContaining('connection refused'), findsOneWidget);
    expect(find.text('Recheck'), findsOneWidget);
  });
}
