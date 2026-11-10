import 'dart:async';

import 'package:flutter/material.dart';
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
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/tv/desktop/desktop_cast_controls.dart';
import 'package:tv_king/features/tv/presentation/tv_scaled_viewport.dart';

class LocalPlayer extends NativeVideoController {
  final List<String> events;
  final String name;
  LocalPlayer(this.events, {this.name = 'local'});
  @override
  Future<void> suspendForCast() async {
    events.add('$name-stop');
  }

  @override
  Future<void> resumeAfterCast() async {
    events.add('$name-resume');
  }
}

class _DeferredLocalPlayer extends LocalPlayer {
  _DeferredLocalPlayer(super.events, this.released);
  final Completer<void> released;

  @override
  Future<void> suspendForCast() async {
    events.add('local-stopping');
    await released.future;
    events.add('local-stop');
  }
}

class Receiver implements CastTransport {
  final List<String> events;
  final List<String> urls = <String>[];
  Receiver(this.events);
  @override
  Future<void> playStream(
      {required String streamUrl, String title = '', String? imageUrl}) async {
    urls.add(streamUrl);
    events.add('remote-play');
  }

  @override
  Future<void> stop() async {
    events.add('remote-stop');
  }

  @override
  Future<void> pause() async {
    events.add('remote-pause');
  }

  @override
  Future<void> resume() async {
    events.add('remote-resume');
  }
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

  const google = CastDevice(
      id: 'google-fixture',
      name: 'Écran test',
      kind: CastDeviceKind.googleCast,
      host: '192.0.2.1',
      port: 8009,
      controlUrl: 'http://192.0.2.1');
  const originalUrl = 'http://stream.invalid/live.ts';
  CastManager managerFor(
    Receiver receiver, {
    Future<StreamProbeResult> Function(String)? probe,
  }) =>
      CastManager.forTesting(
        transportFactory: (_) => receiver,
        probe: probe ??
            (url) async => StreamProbeResult(
                originalUrl: url, finalUrl: url, success: true),
      );
  Future<void> showControls(
    WidgetTester tester, {
    required LocalPlayer local,
    required CastManager manager,
    String url = originalUrl,
    bool castOnOpen = false,
    ZunoCastPicker? picker,
    ValueChanged<bool>? onHandoff,
  }) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('fr'),
      home: Scaffold(
          body: DesktopCastControls(
        controller: local,
        manager: manager,
        streamUrl: url,
        castOnOpen: castOnOpen,
        title: 'Chaîne test',
        picker: picker,
        onHandoffChanged: onHandoff,
      )),
    ));
    await tester.pump();
  }

  testWidgets(
      'ZUNO TV ne montre aucun contrôle Cast et ne suspend pas son lecteur',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(capability, (_) async => false);
    await CastPlatform.initializeZuno();
    final events = <String>[];
    final local = LocalPlayer(events);
    final manager = managerFor(Receiver(events));
    addTearDown(() async {
      await manager.disconnect();
      manager.dispose();
      local.dispose();
    });
    await showControls(
      tester,
      local: local,
      manager: manager,
      picker: (context,
          {required streamUrl, required title, imageUrl, adultAccess}) async {
        fail('une TV ne doit pas ouvrir le sélecteur Cast');
      },
    );
    expect(CastPlatform.canSendFromZuno, isFalse);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byIcon(Icons.cast), findsNothing);
    expect(find.byIcon(Icons.cast_connected), findsNothing);
    expect(events, isEmpty);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('un fichier local ne déclenche ni passation ni tentative Cast',
      (tester) async {
    await CastPlatform.initializeZuno();
    final events = <String>[];
    final local = LocalPlayer(events);
    final receiver = Receiver(events);
    final manager = managerFor(receiver)..selectDevice(google);
    try {
      for (final url in <String>[
        '/data/user/0/app/files/movie.mp4',
        'file:///data/user/0/app/files/movie.mp4',
        'content://downloads/movie',
      ]) {
        await showControls(tester,
            local: local, manager: manager, url: url, castOnOpen: true);
        // Une notification du moteur ne doit pas non plus suspendre le
        // fichier hors ligne alors que ses contrôles Cast sont masqués.
        manager.selectDevice(google);
        await tester.pump();
        expect(events, isEmpty);
        expect(receiver.urls, isEmpty);
        expect(manager.hasTarget, isTrue);
        expect(find.byType(TextButton), findsNothing);
      }

      // La même route peut ensuite recevoir un vrai flux réseau.
      await showControls(tester,
          local: local, manager: manager, url: originalUrl, castOnOpen: true);
      await tester.pumpAndSettle();
      expect(events, <String>['local-stop', 'remote-play']);
      expect(receiver.urls, <String>[originalUrl]);

      // Revenir à un chemin local ne doit jamais le pousser à la TV ni
      // arrêter sa session réseau déjà établie.
      await showControls(tester,
          local: local,
          manager: manager,
          url: '/data/user/0/app/files/movie.mp4',
          castOnOpen: true);
      await tester.pump();
      expect(events, <String>['local-stop', 'remote-play']);
      expect(receiver.urls, <String>[originalUrl]);
      expect(manager.isCasting, isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await manager.disconnect();
      manager.dispose();
      local.dispose();
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final accept in [true, false]) {
    testWidgets(
        accept
            ? 'Cast mobile ferme le local puis attend une reprise après Stop'
            : 'Fermer le sélecteur reprend le mobile sans lecture distante',
        (tester) async {
      await CastPlatform.initializeZuno();
      final events = <String>[];
      final local = LocalPlayer(events);
      final receiver = Receiver(events);
      final manager = CastManager.forTesting(
          transportFactory: (_) => receiver,
          probe: (url) async => StreamProbeResult(
              originalUrl: url, finalUrl: url, success: true));
      const device = CastDevice(
          id: 'fixture',
          name: 'Écran test',
          kind: CastDeviceKind.roku,
          host: '192.0.2.1',
          port: 8060,
          controlUrl: 'http://192.0.2.1');
      addTearDown(() async {
        await manager.disconnect();
        manager.dispose();
        local.dispose();
      });
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('fr'),
        home: Scaffold(
            body: DesktopCastControls(
                controller: local,
                manager: manager,
                streamUrl: 'http://stream.invalid/live.ts',
                title: 'Chaîne test',
                picker: (context,
                    {required streamUrl,
                    required title,
                    imageUrl,
                    adultAccess}) async {
                  expect(events, ['local-stop']);
                  if (accept) {
                    await manager.castTo(device,
                        streamUrl: streamUrl, title: title);
                  }
                })),
      ));
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();
      if (accept) {
        expect(events.take(2), ['local-stop', 'remote-play']);
        expect(events, isNot(contains('local-resume')));
        await tester.tap(find.byIcon(Icons.stop_circle_outlined));
        await tester.pumpAndSettle();
        expect(events, isNot(contains('local-resume')),
            reason: 'la recette 7motion laisse un arrêt volontaire arrêté');
        await tester.tap(find.byIcon(Icons.play_arrow_rounded));
        await tester.pumpAndSettle();
        expect(events.indexOf('remote-stop'),
            lessThan(events.indexOf('local-resume')));
      } else {
        expect(events, ['local-stop', 'local-resume']);
      }
      await tester.pumpWidget(const SizedBox());
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('perte Wi-Fi puis reprise SDK : le mobile reste suspendu',
      (tester) async {
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
    await showControls(
      tester,
      local: local,
      manager: manager,
      onHandoff: handoffs.add,
      picker: (context,
              {required streamUrl, required title, imageUrl, adultAccess}) =>
          manager.castTo(google, streamUrl: streamUrl, title: title),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(events, <String>['local-stop', 'remote-play']);

    manager.debugNativeSessionEvent(const CastNativeSessionEvent('suspended'));
    await tester.pumpAndSettle();
    expect(manager.state, CastState.idle);
    expect(manager.hasActiveSession, isTrue);
    expect(
        tester
            .state<DesktopCastControlsState>(find.byType(DesktopCastControls))
            .ownsSession,
        isTrue);
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
    expect(events, <String>['local-stop', 'remote-play']);
    expect(handoffs, <bool>[true]);
    manager.debugNativeSessionEvent(const CastNativeSessionEvent('ended'));
    await tester.pumpAndSettle();
    expect(events, <String>['local-stop', 'remote-play'],
        reason: 'une fin SDK répétée ne doit pas rouvrir le local');
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();
    expect(events, <String>['local-stop', 'remote-play', 'local-resume']);
    expect(handoffs, <bool>[true, false]);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
      'quitter puis rouvrir le lecteur conserve le Cast sans changer son URL',
      (tester) async {
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
    await showControls(
      tester,
      local: local,
      manager: manager,
      picker: (context,
              {required streamUrl, required title, imageUrl, adultAccess}) =>
          manager.castTo(google, streamUrl: streamUrl, title: title),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(manager.isCasting, isTrue);
    expect(events, <String>['local-stop', 'remote-play']);

    final handoffs = <bool>[];
    await showControls(tester,
        local: reopened,
        manager: manager,
        url: 'http://stream.invalid/another.ts',
        onHandoff: handoffs.add);
    await tester.pumpAndSettle();
    expect(events, <String>['local-stop', 'remote-play', 'nouveau-stop']);
    expect(receiver.urls, <String>[originalUrl],
        reason: 'ouvrir une route ne doit pas envoyer sa chaîne à la TV');
    expect(handoffs, <bool>[true]);
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.stop_circle_outlined));
    await tester.pumpAndSettle();
    expect(events, isNot(contains('nouveau-resume')));
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();
    expect(events, <String>[
      'local-stop',
      'remote-play',
      'nouveau-stop',
      'remote-stop',
      'nouveau-resume',
    ]);
    expect(handoffs, <bool>[true, false]);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('le Cast attend la fermeture native effective du flux local',
      (tester) async {
    await CastPlatform.initializeZuno();
    final released = Completer<void>();
    final events = <String>[];
    final local = _DeferredLocalPlayer(events, released);
    final receiver = Receiver(events);
    final manager = managerFor(receiver);
    try {
      await showControls(tester,
          local: local,
          manager: manager,
          picker: (context,
                  {required streamUrl,
                  required title,
                  imageUrl,
                  adultAccess}) =>
              manager.castTo(google, streamUrl: streamUrl, title: title));
      await tester.tap(find.byType(TextButton));
      await tester.pump();
      expect(events, <String>['local-stopping']);
      expect(receiver.urls, isEmpty);
      released.complete();
      await tester.pumpAndSettle();
      expect(events, <String>['local-stopping', 'local-stop', 'remote-play']);
      expect(tester.takeException(), isNull);
    } finally {
      if (!released.isCompleted) released.complete();
      await tester.pumpWidget(const SizedBox());
      await manager.disconnect();
      manager.dispose();
      local.dispose();
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('zap mobile pendant Cast : nouvelle URL distante, local suspendu',
      (tester) async {
    await CastPlatform.initializeZuno();
    final events = <String>[];
    final local = LocalPlayer(events);
    final receiver = Receiver(events);
    final manager = managerFor(receiver);
    try {
      await showControls(
        tester,
        local: local,
        manager: manager,
        picker: (context,
                {required streamUrl, required title, imageUrl, adultAccess}) =>
            manager.castTo(google, streamUrl: streamUrl, title: title),
      );
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();
      expect(receiver.urls, <String>[originalUrl]);
      expect(events, <String>['local-stop', 'remote-play']);
      // Le lecteur 117 garde le même contrôleur après un geste et met à jour
      // son URL. Ce vrai didUpdateWidget doit charger uniquement le récepteur.
      const next = 'http://stream.invalid/next.ts';
      await showControls(tester, local: local, manager: manager, url: next);
      await tester.pumpAndSettle();
      expect(receiver.urls, <String>[originalUrl, next]);
      expect(manager.hasActiveSession, isTrue);
      expect(events.where((event) => event == 'local-stop'), hasLength(1));
      expect(events, isNot(contains('local-resume')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(manager.hasActiveSession, isTrue,
          reason: 'le retour quitte le lecteur et conserve le Cast');
      expect(events, isNot(contains('local-resume')));
    } finally {
      await tester.pumpWidget(const SizedBox());
      await manager.disconnect();
      manager.dispose();
      local.dispose();
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
      'échec de reprise SDK : fin du handoff et une seule reprise locale',
      (tester) async {
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
    await showControls(
      tester,
      local: local,
      manager: manager,
      onHandoff: handoffs.add,
      picker: (context,
              {required streamUrl, required title, imageUrl, adultAccess}) =>
          manager.castTo(google, streamUrl: streamUrl, title: title),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    manager.debugNativeSessionEvent(const CastNativeSessionEvent('suspended'));
    await tester.pumpAndSettle();
    expect(manager.hasActiveSession, isTrue);
    expect(events, <String>['local-stop', 'remote-play']);
    expect(handoffs, <bool>[true]);

    manager.debugNativeSessionEvent(
        const CastNativeSessionEvent('resume_failed', 8));
    await tester.pumpAndSettle();
    expect(manager.state, CastState.error);
    expect(manager.hasActiveSession, isFalse);
    expect(
        tester
            .state<DesktopCastControlsState>(find.byType(DesktopCastControls))
            .ownsSession,
        isFalse);
    expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);
    expect(events.where((event) => event == 'local-resume'), hasLength(1));
    expect(handoffs, <bool>[true, false]);

    // Certains SDK répètent le même échec : aucun nouveau flux local.
    manager.debugNativeSessionEvent(
        const CastNativeSessionEvent('resume_failed', 8));
    await tester.pumpAndSettle();
    expect(manager.hasActiveSession, isFalse);
    expect(events.where((event) => event == 'local-resume'), hasLength(1));
    expect(receiver.urls, <String>[originalUrl]);
    expect(handoffs, <bool>[true, false]);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
      'les commandes Cast complètes tiennent sur mobile 360dp avec le canevas117',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await CastPlatform.initializeZuno();
    final events = <String>[];
    final local = LocalPlayer(events);
    final receiver = Receiver(events);
    final manager = managerFor(receiver);
    const longName = CastDevice(
        id: 'long',
        name: 'Télévision du salon avec un nom volontairement très long',
        kind: CastDeviceKind.googleCast,
        host: '192.0.2.2',
        port: 8009,
        controlUrl: 'http://192.0.2.2');
    const channels = <Channel>[
      Channel(
          id: 'one',
          name: 'Information',
          category: 'Info',
          streamUrl: originalUrl,
          isLive: true),
      Channel(
          id: 'two',
          name: 'Sport',
          category: 'Sport',
          streamUrl: 'http://stream.invalid/next.ts',
          isLive: true),
    ];
    await manager.castTo(longName,
        streamUrl: originalUrl, title: 'Information');
    manager.setCastPlaylist(channels, channels.first);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (_, child) => TvScaledViewport(child: child!),
      home: Scaffold(
          body: Stack(fit: StackFit.expand, children: <Widget>[
        Positioned(
            top: 24,
            right: 48,
            child: DesktopCastControls(
                manager: manager,
                controller: local,
                streamUrl: originalUrl,
                title: 'Information',
                channels: channels,
                channel: channels.first)),
      ])),
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    expect(find.byIcon(Icons.screen_share_rounded), findsOneWidget);
    final rect = tester.getRect(find.byType(DesktopCastControls));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await manager.disconnect();
    manager.dispose();
    local.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
      'fermer un ancien picker conserve la nouvelle connexion du même profil',
      (tester) async {
    await CastPlatform.initializeZuno();
    final events = <String>[];
    final local = LocalPlayer(events);
    final receiver = Receiver(events);
    final firstProbe = Completer<StreamProbeResult>();
    final nextProbe = Completer<StreamProbeResult>();
    final close = Completer<void>();
    const nextUrl = 'http://stream.invalid/new-selection.ts';
    final manager = managerFor(receiver,
        probe: (url) =>
            url == originalUrl ? firstProbe.future : nextProbe.future);
    Future<void>? first;
    await showControls(tester, local: local, manager: manager, picker: (context,
        {required streamUrl, required title, imageUrl, adultAccess}) {
      first = manager.castTo(google, streamUrl: streamUrl, title: title);
      return close.future;
    });
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    final next =
        manager.castTo(google, streamUrl: nextUrl, title: 'Nouvelle chaîne');
    await tester.pump();
    close.complete();
    await tester.pump();
    expect(manager.state, CastState.connecting,
        reason:
            'le wrapper ne possède pas le jeton de cette nouvelle tentative');
    expect(events, isNot(contains('local-resume')));
    firstProbe.complete(const StreamProbeResult(
        originalUrl: originalUrl, finalUrl: originalUrl, success: true));
    nextProbe.complete(const StreamProbeResult(
        originalUrl: nextUrl, finalUrl: nextUrl, success: true));
    await Future.wait(<Future<void>>[first!, next]);
    await tester.pumpAndSettle();
    expect(receiver.urls, <String>[nextUrl]);
    expect(manager.isCasting, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await manager.disconnect();
    manager.dispose();
    local.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final removeRoute in <bool>[false, true]) {
    testWidgets(
        removeRoute
            ? 'route fermée pendant la connexion : la tentative tardive est annulée'
            : 'sélecteur fermé pendant la connexion : annulation puis reprise locale',
        (tester) async {
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
        await showControls(
          tester,
          local: local,
          manager: manager,
          picker: (context,
              {required streamUrl, required title, imageUrl, adultAccess}) {
            attemptStarted = true;
            unawaited(manager
                .castTo(google, streamUrl: streamUrl, title: title)
                .then<void>((_) {
              attemptCompleted = true;
            }, onError: (Object _, StackTrace __) {
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
        expect(
            events,
            removeRoute
                ? <String>['local-stop']
                : <String>['local-stop', 'local-resume']);

        probe.complete(const StreamProbeResult(
            originalUrl: originalUrl, finalUrl: originalUrl, success: true));
        await drainAttempt();
        expect(attemptCompleted, isTrue,
            reason:
                'la réponse tardive doit terminer la tentative annulée, sans attendre son timeout');
        expect(receiver.urls, isEmpty,
            reason:
                'la réponse tardive du réseau ne doit pas lancer le récepteur');
        expect(manager.hasActiveSession, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        // Même une assertion ratée libère les portes et leurs microtâches
        // dans le test courant ; la variante suivante reçoit une zone saine.
        await manager.disconnect();
        if (!probe.isCompleted) {
          probe.complete(const StreamProbeResult(
              originalUrl: originalUrl, finalUrl: originalUrl, success: true));
        }
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
