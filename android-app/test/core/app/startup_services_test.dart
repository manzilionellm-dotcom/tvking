import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/app/startup_services.dart';
import 'package:tv_king/core/crash/crash_reporting.dart';

class _StartupProbe extends StatefulWidget {
  const _StartupProbe();

  @override
  State<_StartupProbe> createState() => _StartupProbeState();
}

class _StartupProbeState extends State<_StartupProbe> {
  int actions = 0;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Column(children: <Widget>[
            const Text('Interface prête'),
            Text('Actions : $actions'),
            TextButton(
              onPressed: () => setState(() => actions++),
              child: const Text('Continuer'),
            ),
          ]),
        ),
      );
}

void main() {
  testWidgets('un backend sans réponse ne bloque ni l’UI ni le journal local',
      (tester) async {
    final frame = Completer<void>();
    final backend = Completer<bool>(); // Ne sera volontairement jamais terminé.
    int attachCalls = 0;
    bool localReadyAtBody = false;
    bool bootCompleted = false;
    final boot = startWithLocalCrashReporting(
      () async {
        localReadyAtBody = CrashReporting.instance.isReady;
        runApp(const _StartupProbe());
      },
      firstFrameRasterized: frame.future,
      attachRemoteCrashReporting: () {
        attachCalls++;
        return backend.future;
      },
    );
    unawaited(boot.then((_) {
      bootCompleted = true;
    }));
    await tester.pump();
    // On draine aussi un tour de boucle de démarrage, sans délai arbitraire
    // ni attente du backend distant.
    await tester.pump(Duration.zero);
    expect(localReadyAtBody, isTrue);
    expect(bootCompleted, isTrue);
    expect(find.text('Interface prête'), findsOneWidget);
    expect(attachCalls, 0);

    // Le widget est réellement construit et peint par le moteur de test.
    // Seule la notification de rasterisation plateforme est injectée : le
    // binding de widget-test ne fournit pas la sortie physique d'un appareil.
    frame.complete();
    await tester.pump();
    expect(attachCalls, 1);
    expect(backend.isCompleted, isFalse);
    CrashReporting.instance.recordError(
      StateError('erreur locale pendant backend suspendu'),
      StackTrace.current,
      context: 'startup test',
    );
    expect(CrashReporting.instance.recentErrors.last,
        contains('erreur locale pendant backend suspendu'));
    await tester.tap(find.text('Continuer'));
    await tester.pump();
    expect(find.text('Actions : 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await boot;
  });

  testWidgets('un échec tardif du backend est capté et l’UI reste actionnable',
      (tester) async {
    final frame = Completer<void>();
    final backend = Completer<bool>();
    int attachCalls = 0;
    final boot = startWithLocalCrashReporting(
      () async {
        runApp(const _StartupProbe());
      },
      firstFrameRasterized: frame.future,
      attachRemoteCrashReporting: () {
        attachCalls++;
        return backend.future;
      },
    );
    await tester.pump();
    await tester.pump(Duration.zero);
    expect(find.text('Interface prête'), findsOneWidget);
    expect(attachCalls, 0);
    await boot;
    frame.complete();
    await tester.pump();
    expect(attachCalls, 1);

    backend.completeError(
      StateError('échec Firebase tardif de fixture'),
      StackTrace.current,
    );
    await tester.pump();
    await tester.pump(Duration.zero);
    expect(tester.takeException(), isNull);
    expect(CrashReporting.instance.recentErrors.last,
        contains('Crashlytics différé'));
    expect(CrashReporting.instance.recentErrors.last,
        contains('échec Firebase tardif de fixture'));
    await tester.tap(find.text('Continuer'));
    await tester.pump();
    expect(find.text('Actions : 1'), findsOneWidget);
    expect(attachCalls, 1);
  });

  testWidgets('l’attachement configuré est appelé après la première image',
      (tester) async {
    final frame = Completer<void>();
    int attachCalls = 0;
    final boot = startWithLocalCrashReporting(
      () async {
        runApp(const _StartupProbe());
      },
      firstFrameRasterized: frame.future,
      attachRemoteCrashReporting: () async {
        attachCalls++;
        return true;
      },
    );
    await tester.pump();
    await tester.pump(Duration.zero);
    expect(find.text('Interface prête'), findsOneWidget);
    expect(attachCalls, 0);
    await boot;
    frame.complete();
    await tester.pump();
    await tester.pump();
    expect(attachCalls, 1);
    expect(tester.takeException(), isNull);
  });
}
