import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/cast_platform.dart';
import 'package:tv_king/features/cast/data/cast_transport.dart';
import 'package:tv_king/features/cast/data/google_cast_api.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';
import 'package:tv_king/features/tv/desktop/desktop_cast_controls.dart';

class LocalPlayer extends NativeVideoController {
  final List<String> events;
  final String name;
  LocalPlayer(this.events, {this.name = 'local'});
  @override
  Future<void> suspendForCast() async { events.add('$name-stop'); }
  @override
  Future<void> resumeAfterCast() async { events.add('$name-resume'); }
}
class Receiver implements CastTransport {
  final List<String> events;
  final List<String> urls = <String>[];
  Receiver(this.events);
  @override
  Future<void> playStream({required String streamUrl, String title = '', String? imageUrl}) async {
    urls.add(streamUrl);
    events.add('remote-play');
  }
  @override
  Future<void> stop() async { events.add('remote-stop'); }
  @override
  Future<void> pause() async { events.add('remote-pause'); }
  @override
  Future<void> resume() async { events.add('remote-resume'); }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  const capability = MethodChannel('com.sevenmotion.zuno/cast-capability');
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(capability, (_) async => true);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(capability, null);
  });

  const google = CastDevice(id: 'google-fixture', name: 'Écran test',
      kind: CastDeviceKind.googleCast, host: '192.0.2.1', port: 8009,
      controlUrl: 'http://192.0.2.1');
  const originalUrl = 'http://stream.invalid/live.ts';
  CastManager managerFor(Receiver receiver, {
    Future<StreamProbeResult> Function(String)? probe,
  }) => CastManager.forTesting(
    transportFactory: (_) => receiver,
    probe: probe ?? (url) async => StreamProbeResult(
        originalUrl: url, finalUrl: url, success: true),
  );
  Future<void> showControls(WidgetTester tester, {
    required LocalPlayer local,
    required CastManager manager,
    String url = originalUrl,
    ZunoCastPicker? picker,
    ValueChanged<bool>? onHandoff,
  }) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('fr'),
      home: Scaffold(body: DesktopCastControls(
        controller: local, manager: manager, streamUrl: url,
        title: 'Chaîne test', picker: picker, onHandoffChanged: onHandoff,
      )),
    ));
    await tester.pump();
  }

  for (final accept in [true, false]) {
    testWidgets(accept ? 'Cast mobile ferme le local avant le récepteur puis reprend au stop' :
        'Fermer le sélecteur reprend le mobile sans lecture distante', (tester) async {
      await CastPlatform.initializeZuno();
      final events = <String>[];
      final local = LocalPlayer(events);
      final receiver = Receiver(events);
      final manager = CastManager.forTesting(transportFactory: (_) => receiver,
        probe: (url) async => StreamProbeResult(originalUrl: url, finalUrl: url, success: true));
      const device = CastDevice(id: 'fixture', name: 'Écran test', kind: CastDeviceKind.roku,
        host: '192.0.2.1', port: 8060, controlUrl: 'http://192.0.2.1');
      addTearDown(() async { await manager.disconnect(); manager.dispose(); local.dispose(); });
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('fr'),
        home: Scaffold(body: DesktopCastControls(controller: local, manager: manager,
          streamUrl: 'http://stream.invalid/live.ts', title: 'Chaîne test',
          picker: (context, {required streamUrl, required title, imageUrl}) async {
            expect(events, ['local-stop']);
            if (accept) await manager.castTo(device, streamUrl: streamUrl, title: title);
          })),
      ));
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();
      if (accept) {
        expect(events.take(2), ['local-stop', 'remote-play']);
        expect(events, isNot(contains('local-resume')));
        await tester.tap(find.byIcon(Icons.stop_circle_outlined));
        await tester.pumpAndSettle();
        expect(events.indexOf('remote-stop'), lessThan(events.indexOf('local-resume')));
      } else {
        expect(events, ['local-stop', 'local-resume']);
      }
      await tester.pumpWidget(const SizedBox());
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('perte Wi-Fi puis reprise SDK : le mobile reste suspendu', (tester) async {
    await CastPlatform.initializeZuno();
    final events = <String>[];
    final handoffs = <bool>[];
    final local = LocalPlayer(events);
    final receiver = Receiver(events);
    final manager = managerFor(receiver);
    addTearDown(() async {
      await manager.disconnect();
      manager.dispose();
      local.dispose();
    });
    await showControls(tester, local: local, manager: manager,
      onHandoff: handoffs.add,
      picker: (context, {required streamUrl, required title, imageUrl}) =>
          manager.castTo(google, streamUrl: streamUrl, title: title),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(events, <String>['local-stop', 'remote-play']);

    manager.debugNativeSessionEvent(const CastNativeSessionEvent('suspended'));
    await tester.pumpAndSettle();
    expect(manager.state, CastState.idle);
    expect(manager.hasActiveSession, isTrue);
    expect(tester.state<DesktopCastControlsState>(find.byType(DesktopCastControls))
        .ownsSession, isTrue);
    expect(events, <String>['local-stop', 'remote-play']);
    expect(handoffs, <bool>[true]);

    manager.debugNativeSessionEvent(const CastNativeSessionEvent('resumed'));
    await tester.pumpAndSettle();
    expect(manager.isCasting, isTrue);
    expect(events, <String>['local-stop', 'remote-play']);
    expect(handoffs, <bool>[true]);

    manager.debugNativeSessionEvent(const CastNativeSessionEvent('ended'));
    await tester.pumpAndSettle();
    expect(manager.hasActiveSession, isFalse);
    expect(events, <String>['local-stop', 'remote-play', 'local-resume']);
    expect(handoffs, <bool>[true, false]);
    manager.debugNativeSessionEvent(const CastNativeSessionEvent('ended'));
    await tester.pumpAndSettle();
    expect(events, <String>['local-stop', 'remote-play', 'local-resume'],
        reason: 'une fin SDK répétée ne doit pas rouvrir le local deux fois');
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('quitter puis rouvrir le lecteur conserve le Cast sans changer son URL', (tester) async {
    await CastPlatform.initializeZuno();
    final events = <String>[];
    final local = LocalPlayer(events);
    final reopened = LocalPlayer(events, name: 'nouveau');
    final receiver = Receiver(events);
    final manager = managerFor(receiver);
    addTearDown(() async {
      await manager.disconnect();
      manager.dispose();
      local.dispose();
      reopened.dispose();
    });
    await showControls(tester, local: local, manager: manager,
      picker: (context, {required streamUrl, required title, imageUrl}) =>
          manager.castTo(google, streamUrl: streamUrl, title: title),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(manager.isCasting, isTrue);
    expect(events, <String>['local-stop', 'remote-play']);

    final handoffs = <bool>[];
    await showControls(tester, local: reopened, manager: manager,
      url: 'http://stream.invalid/another.ts', onHandoff: handoffs.add);
    await tester.pumpAndSettle();
    expect(events, <String>['local-stop', 'remote-play', 'nouveau-stop']);
    expect(receiver.urls, <String>[originalUrl],
        reason: 'ouvrir une route ne doit pas envoyer sa chaîne à la TV');
    expect(handoffs, <bool>[true]);
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.stop_circle_outlined));
    await tester.pumpAndSettle();
    expect(events, <String>[
      'local-stop', 'remote-play', 'nouveau-stop', 'remote-stop', 'nouveau-resume',
    ]);
    expect(handoffs, <bool>[true, false]);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('échec de reprise SDK : fin du handoff et une seule reprise locale', (tester) async {
    await CastPlatform.initializeZuno();
    final events = <String>[];
    final handoffs = <bool>[];
    final local = LocalPlayer(events);
    final receiver = Receiver(events);
    final manager = managerFor(receiver);
    addTearDown(() async {
      await manager.disconnect();
      manager.dispose();
      local.dispose();
    });
    await showControls(tester, local: local, manager: manager,
      onHandoff: handoffs.add,
      picker: (context, {required streamUrl, required title, imageUrl}) =>
          manager.castTo(google, streamUrl: streamUrl, title: title),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    manager.debugNativeSessionEvent(const CastNativeSessionEvent('suspended'));
    await tester.pumpAndSettle();
    expect(manager.hasActiveSession, isTrue);
    expect(events, <String>['local-stop', 'remote-play']);
    expect(handoffs, <bool>[true]);

    manager.debugNativeSessionEvent(const CastNativeSessionEvent('resume_failed', 8));
    await tester.pumpAndSettle();
    expect(manager.state, CastState.error);
    expect(manager.hasActiveSession, isFalse);
    expect(tester.state<DesktopCastControlsState>(find.byType(DesktopCastControls))
        .ownsSession, isFalse);
    expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);
    expect(events.where((event) => event == 'local-resume'), hasLength(1));
    expect(handoffs, <bool>[true, false]);

    // Certains SDK répètent le même échec : aucun nouveau flux local.
    manager.debugNativeSessionEvent(const CastNativeSessionEvent('resume_failed', 8));
    await tester.pumpAndSettle();
    expect(manager.hasActiveSession, isFalse);
    expect(events.where((event) => event == 'local-resume'), hasLength(1));
    expect(receiver.urls, <String>[originalUrl]);
    expect(handoffs, <bool>[true, false]);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final removeRoute in <bool>[false, true]) {
    testWidgets(removeRoute
        ? 'route fermée pendant la connexion : la tentative tardive est annulée'
        : 'sélecteur fermé pendant la connexion : annulation puis reprise locale', (tester) async {
      await CastPlatform.initializeZuno();
      final events = <String>[];
      final local = LocalPlayer(events);
      final receiver = Receiver(events);
      final probe = Completer<StreamProbeResult>();
      final closePicker = Completer<void>();
      final manager = managerFor(receiver, probe: (_) => probe.future);
      bool attemptStarted = false;
      bool attemptCompleted = false;
      Future<void> drainAttempt() async {
        // Le Future naît dans le callback UI, sous l'horloge fakeAsync.
        // Le drainer ici évite de l'attendre dans addTearDown, après la fin
        // du pompage. Pas d'avance d'une seconde : le timeout du manager
        // ne doit pas se substituer à la vraie annulation attendue.
        for (int i = 0; i < 10 && attemptStarted && !attemptCompleted; i++) {
          await tester.pump();
        }
      }

      try {
        await showControls(tester, local: local, manager: manager,
          picker: (context, {required streamUrl, required title, imageUrl}) {
            attemptStarted = true;
            unawaited(manager.castTo(google, streamUrl: streamUrl, title: title)
                .then<void>((_) {
                      attemptCompleted = true;
                    },
                    onError: (Object _, StackTrace __) {
                      attemptCompleted = true;
                    }));
            return closePicker.future;
          },
        );
        await tester.tap(find.byType(TextButton));
        await tester.pump();
        expect(manager.state, CastState.connecting);
        expect(events, <String>['local-stop']);
        if (removeRoute) await tester.pumpWidget(const SizedBox());
        closePicker.complete();
        await tester.pump();
        expect(manager.hasActiveSession, isFalse);
        expect(events, removeRoute
            ? <String>['local-stop']
            : <String>['local-stop', 'local-resume']);

        probe.complete(const StreamProbeResult(
            originalUrl: originalUrl, finalUrl: originalUrl, success: true));
        await drainAttempt();
        expect(attemptCompleted, isTrue,
            reason: 'la réponse tardive doit terminer la tentative annulée, sans attendre son timeout');
        expect(receiver.urls, isEmpty,
            reason: 'la réponse tardive du réseau ne doit pas lancer le récepteur');
        expect(manager.hasActiveSession, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        // Même une assertion ratée libère les portes et leurs microtâches
        // dans le test courant ; la variante suivante reçoit une zone saine.
        await manager.disconnect();
        if (!probe.isCompleted) probe.complete(const StreamProbeResult(
            originalUrl: originalUrl, finalUrl: originalUrl, success: true));
        if (!closePicker.isCompleted) closePicker.complete();
        await drainAttempt();
        await tester.pumpWidget(const SizedBox());
        manager.dispose();
        local.dispose();
      }
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }
}
