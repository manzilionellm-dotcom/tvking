import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:tv_king/core/app/zuno_edition.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/cast_platform.dart';
import 'package:tv_king/features/cast/data/cast_transport.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';
import 'package:tv_king/features/cast/presentation/cast_button.dart';
import 'package:tv_king/features/cast/presentation/cast_mini_bar.dart';
import 'package:tv_king/features/cast/presentation/cast_picker_sheet.dart';
import 'package:tv_king/features/tv/desktop/desktop_cast_controls.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

class _Local extends NativeVideoController {
  _Local(this.events);
  final List<String> events;
  Completer<void>? stopGate;
  bool failStop = false;
  bool held = false;
  int resumes = 0;
  @override
  bool get castSuspended => held;
  @override
  Future<void> suspendForCast() async {
    events.add('local.stop.request');
    held = true;
    if (stopGate != null) await stopGate!.future;
    if (failStop) throw StateError('stop failed');
    events.add('local.closed');
  }

  @override
  Future<void> resumeAfterCast() async {
    events.add('local.resume');
    held = false;
    resumes++;
  }
}

class _Remote implements CastTransport {
  _Remote(this.events);
  final List<String> events;
  final List<String> urls = <String>[];
  Completer<void>? playGate;
  Completer<void>? stopGate;
  Completer<void>? pauseGate;
  int stops = 0;
  @override
  Future<void> playStream(
      {required String streamUrl,
      String title = 'Test',
      String? imageUrl}) async {
    urls.add(streamUrl);
    events.add('remote.play');
    if (playGate != null) await playGate!.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    events.add('remote.stop.request');
    if (stopGate != null) await stopGate!.future;
    events.add('remote.closed');
  }

  @override
  Future<void> pause() async {
    if (pauseGate != null) await pauseGate!.future;
  }

  @override
  Future<void> resume() async {}
}

class _Manager extends CastManager {
  _Manager(_Remote remote)
      : super.forTesting(
          transportFactory: (_) => remote,
          probe: (url) async =>
              StreamProbeResult(originalUrl: url, finalUrl: url, success: true),
          timeout: const Duration(seconds: 5),
        );
  int subscriptions = 0;
  @override
  void addListener(VoidCallback listener) {
    subscriptions++;
    super.addListener(listener);
  }
}

const _receiver = CastDevice(
    id: 'fixture',
    name: 'Récepteur de test au nom très long',
    kind: CastDeviceKind.roku,
    host: '192.0.2.1',
    port: 8060,
    controlUrl: 'http://192.0.2.1');
const _firstUrl = 'https://stream.invalid/first.ts';
const _lastUrl = 'https://stream.invalid/last.ts';

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('fr'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  late List<String> events;
  late _Local local;
  late _Remote remote;
  late _Manager manager;
  late GlobalKey<DesktopCastControlsState> key;
  late List<bool> handoffs;

  void castTest(String description, Future<void> Function(WidgetTester) body,
      {TestVariant<Object?> variant = const DefaultTestVariant()}) {
    testWidgets(description, (tester) async {
      CastPlatform.configureZuno(ZunoEdition.touch);
      NativeVideoController.backendFactory = null;
      events = <String>[];
      handoffs = <bool>[];
      local = _Local(events);
      remote = _Remote(events);
      manager = _Manager(remote);
      key = GlobalKey<DesktopCastControlsState>();
      try {
        await body(tester);
      } finally {
        // La fermeture fait partie du scénario, dans la même horloge que
        // les gestes. Même une assertion en échec ne laisse pas de minuterie.
        for (final gate in <Completer<void>?>[
          local.stopGate,
          remote.playGate,
          remote.stopGate,
          remote.pauseGate,
        ]) {
          if (gate != null && !gate.isCompleted) gate.complete();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        manager.stopDiscovery();
        final stopping = manager.disconnect();
        await tester.pump();
        await stopping;
        manager.dispose();
        local.dispose();
        CastPlatform.resetForTesting();
      }
    }, variant: variant);
  }

  Future<void> send(BuildContext context,
      {required String streamUrl,
      required String title,
      String? imageUrl,
      required CastManager manager,
      required Object owner}) async {
    events.add('picker');
    await manager.castTo(_receiver,
        streamUrl: streamUrl, title: title, owner: owner);
  }

  Widget controls({String url = _firstUrl, CastPickerLauncher? picker}) =>
      DesktopCastControls(
        key: key,
        controller: local,
        streamUrl: url,
        title: 'Test',
        manager: manager,
        picker: picker ?? send,
        onHandoffChanged: handoffs.add,
      );
  Future<void> start(WidgetTester tester, {CastPickerLauncher? picker}) async {
    await tester.pumpWidget(_app(controls(picker: picker)));
    await tester.tap(find.byIcon(Icons.cast));
    await tester.pumpAndSettle();
  }

  castTest(
      'édition TV : aucun contrôle, même sur un petit écran, sans abonnement manager',
      (tester) async {
    CastPlatform.configureZuno(ZunoEdition.television);
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(Column(children: <Widget>[
      controls(),
      const CastButton(),
      const CastMiniBar(),
      CastPickerSheet(manager: manager),
    ])));
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(manager.subscriptions, 0);
    expect(events, isEmpty);
  });

  for (final scenario in <(String, ZunoEdition, TargetPlatform, Size)>[
    ('mobile', ZunoEdition.touch, TargetPlatform.android, const Size(360, 740)),
    (
      'grande tablette',
      ZunoEdition.touch,
      TargetPlatform.android,
      const Size(1366, 1024)
    ),
    (
      'ordinateur',
      ZunoEdition.desktop,
      TargetPlatform.windows,
      const Size(1440, 900)
    ),
  ]) {
    castTest('${scenario.$1} : Cast accessible et commandes sans débordement',
        (tester) async {
      CastPlatform.configureZuno(scenario.$2);
      tester.view.physicalSize = scenario.$4;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await start(tester);
      expect(manager.isCasting, isTrue,
          reason: 'events=$events; state=${manager.state}');
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(scenario.$3));
  }

  castTest('aucun envoi avant confirmation de la fermeture locale',
      (tester) async {
    local.stopGate = Completer<void>();
    await start(tester);
    expect(events, <String>['local.stop.request']);
    expect(handoffs, <bool>[true]);
    local.stopGate!.complete();
    await tester.pumpAndSettle();
    expect(events.take(4), <String>[
      'local.stop.request',
      'local.closed',
      'picker',
      'remote.play'
    ]);
    expect(local.resumes, 0);
  });

  castTest('vrai sélecteur mobile : grand texte système sans débordement',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(MediaQuery(
      data: const MediaQueryData(
        size: Size(360, 740),
        textScaler: TextScaler.linear(2),
      ),
      child: CastPickerSheet(manager: manager),
    )));
    await tester.pump();
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  castTest('Stop attend le récepteur avant de reprendre en local',
      (tester) async {
    await start(tester);
    remote.stopGate = Completer<void>();
    await tester.tap(find.byIcon(Icons.stop_circle_outlined));
    await tester.pumpAndSettle();
    expect(local.resumes, 0);
    expect(handoffs, <bool>[true]);
    remote.stopGate!.complete();
    await tester.pumpAndSettle();
    expect(events.indexOf('remote.closed'),
        lessThan(events.indexOf('local.resume')));
    expect(handoffs, <bool>[true, false]);
    expect(local.resumes, 1);
  });

  castTest('recherche pendant pause distante ne relance pas le local',
      (tester) async {
    await start(tester);
    await key.currentState!.pause();
    manager.startDiscovery();
    await tester.pump();
    manager.stopDiscovery();
    await tester.pumpAndSettle();
    expect(manager.state, CastState.paused);
    expect(local.resumes, 0);
    expect(key.currentState!.ownsSession, isTrue);
  });

  castTest('fermer le picker pendant connexion annule cette tentative',
      (tester) async {
    remote.playGate = Completer<void>();
    final closePicker = Completer<void>();
    Future<void>? pending;
    await start(tester, picker: (context,
        {required streamUrl,
        required title,
        imageUrl,
        required manager,
        required owner}) async {
      pending = manager.castTo(_receiver,
          streamUrl: streamUrl, title: title, owner: owner);
      await closePicker.future;
    });
    expect(manager.state, CastState.connecting);
    closePicker.complete();
    await tester.pumpAndSettle();
    expect(remote.stops, 1);
    expect(local.resumes, 1);
    remote.playGate!.complete();
    await pending;
    await tester.pumpAndSettle();
    expect(manager.state, CastState.idle);
    expect(local.resumes, 1);
  });

  castTest('ancienne route et ancien picker ne stoppent pas un nouveau Cast',
      (tester) async {
    final closePicker = Completer<void>();
    await start(tester, picker: (context,
        {required streamUrl,
        required title,
        imageUrl,
        required manager,
        required owner}) async {
      await closePicker.future;
    });
    await tester.pumpWidget(_app(const SizedBox.shrink()));
    await tester.pump();
    final nextOwner = Object();
    await manager.castTo(_receiver,
        streamUrl: _lastUrl, title: 'Nouveau', owner: nextOwner);
    final before = remote.stops;
    closePicker.complete();
    await tester.pumpAndSettle();
    expect(manager.ownsSession(nextOwner), isTrue);
    expect(manager.isCasting, isTrue);
    expect(remote.stops, before);
    expect(local.resumes, 0);
  });

  castTest('les zaps pendant connexion envoient seulement le dernier choix',
      (tester) async {
    remote.playGate = Completer<void>();
    await start(tester);
    await tester
        .pumpWidget(_app(controls(url: 'https://stream.invalid/obsolete.ts')));
    await tester.pumpWidget(_app(controls(url: _lastUrl)));
    remote.playGate!.complete();
    await tester.pumpAndSettle();
    expect(remote.urls, <String>[_firstUrl, _lastUrl]);
    expect(local.resumes, 0);
  });

  castTest('un zap pendant la commande Pause atteint aussi le récepteur',
      (tester) async {
    await start(tester);
    remote.pauseGate = Completer<void>();
    final pause = key.currentState!.pause();
    await tester.pumpWidget(_app(controls(url: _lastUrl)));
    remote.pauseGate!.complete();
    await pause;
    await tester.pumpAndSettle();
    expect(remote.urls, <String>[_firstUrl, _lastUrl]);
    expect(local.resumes, 0);
  });

  castTest('échec du Stop local : aucune tentative de Cast', (tester) async {
    local.failStop = true;
    await start(tester);
    expect(remote.urls, isEmpty);
    expect(events, isNot(contains('picker')));
    expect(manager.isCasting, isFalse);
  });
}
