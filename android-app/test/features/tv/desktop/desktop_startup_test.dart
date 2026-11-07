import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/desktop/desktop_startup.dart';

void main() {
  testWidgets(
      'startup paints ZUNO before async bootstrap and shows explicit failure',
      (WidgetTester tester) async {
    final ValueNotifier<bool> failed = ValueNotifier<bool>(false);
    await tester.pumpWidget(DesktopStartupScreen(failed: failed));
    expect(find.text('ZUNO'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    failed.value = true;
    await tester.pump();
    expect(find.textContaining('Démarrage impossible'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
    failed.dispose();
  });
  test('smoke blocks HTTP before any panel connection', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final HttpClient client = HttpClient();
      try {
        await expectLater(
            client.getUrl(Uri.parse('https://example.invalid/registration')),
            throwsA(isA<SocketException>()));
      } finally {
        client.close(force: true);
      }
    }, DesktopSmokeHttpOverrides());
  });
}
