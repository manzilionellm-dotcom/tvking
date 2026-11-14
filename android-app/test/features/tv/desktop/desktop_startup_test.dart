import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/app/startup_trace.dart';
import 'package:tv_king/features/tv/desktop/desktop_startup.dart';

void main() {
  testWidgets('startup paints ZUNO, then a failure offers retry, close, Esc',
      (WidgetTester tester) async {
    final ValueNotifier<DesktopStartupFailure?> failure =
        ValueNotifier<DesktopStartupFailure?>(null);
    int retries = 0;
    int closes = 0;
    await tester.pumpWidget(DesktopStartupScreen(
      failure: failure,
      logPath: r'C:\Users\x\AppData\Local\Zuno\logs\startup.log',
      onRetry: () => retries++,
      onClose: () => closes++,
    ));
    expect(find.text('ZUNO'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    failure.value = const DesktopStartupFailure('StateError: disque');
    await tester.pump();
    expect(find.textContaining('Démarrage impossible'), findsOneWidget);
    expect(find.text('StateError: disque'), findsOneWidget);
    expect(find.textContaining('startup.log'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.byKey(const Key('startup-retry')));
    await tester.tap(find.byKey(const Key('startup-close')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(retries, 1);
    expect(closes, 2);
    await tester.pumpWidget(const SizedBox());
    failure.dispose();
  });

  test('tolerant boot steps never throw and never wait past their timeout',
      () async {
    final List<String> lines = <String>[];
    StartupTrace.sink = lines.add;
    StartupTrace.tolerant = true;
    try {
      await StartupTrace.boot('throws', () async => throw StateError('db'));
      await StartupTrace.boot('hangs', () => Completer<void>().future,
          timeout: const Duration(milliseconds: 20));
      StartupTrace.bootSync('sync', () => throw ArgumentError('x'));
    } finally {
      StartupTrace.tolerant = false;
      StartupTrace.sink = null;
    }
    expect(lines.any((String l) => l.contains('throws.failed StateError')),
        isTrue);
    expect(lines.any((String l) => l.contains('hangs.timeout')), isTrue);
    expect(lines.any((String l) => l.contains('sync.failed ArgumentError')),
        isTrue);
  });

  test('Android keeps historical rethrow behaviour', () async {
    StartupTrace.tolerant = false;
    await expectLater(
        StartupTrace.boot('x', () async => throw StateError('db')),
        throwsStateError);
  });

  test('startup log writes to the given file', () {
    final Directory dir = Directory.systemTemp.createTempSync('zuno-log');
    try {
      final String path = '${dir.path}/logs/startup.log';
      DesktopStartupLog.open(path: path, header: <String>['exe=test']);
      DesktopStartupLog.error('Zone', StateError('boom'), StackTrace.current);
      final String text = File(path).readAsStringSync();
      expect(text, contains('exe=test'));
      expect(text, contains('[ERREUR Zone] StateError'));
    } finally {
      dir.deleteSync(recursive: true);
    }
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
