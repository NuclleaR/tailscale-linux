import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailscale_linux/settings/widgets.dart';

void main() {
  late List<String> clipboard;

  setUp(() {
    clipboard = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });

  Future<void> open(WidgetTester tester, {bool openable = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCopyDialog(
                context,
                title: 'Copy to Clipboard',
                message: 'Copy it from here:',
                text: '100.64.0.1',
                copied: 'Copied 100.64.0.1',
                openable: openable,
              ),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
  }

  testWidgets('Copy copies the text, closes and says so', (tester) async {
    await open(tester);
    expect(find.text('100.64.0.1'), findsOneWidget);
    expect(find.text('Open'), findsNothing);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(clipboard, ['100.64.0.1']);
    expect(find.text('Copy to Clipboard'), findsNothing);
    expect(find.text('Copied 100.64.0.1'), findsOneWidget);
  });

  testWidgets('a link can be opened too', (tester) async {
    await open(tester, openable: true);
    expect(find.text('Open'), findsOneWidget);
  });
}
