import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/ads/data/startup_ad_repository.dart';
import 'package:tv_king/features/ads/presentation/tv_startup_ad_gate.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/cast_transport.dart';
import 'package:tv_king/features/cast/data/google_cast_api.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

// Le vrai controller utilise un moteur simulé : aucune TV ni vidéo distante.
class _Video extends NativeVideoBackend {
  late NativeVideoController controller;
  final urls = <String>[];
  bool closed = false;
  @override
  void bind(NativeVideoController controller) {
    this.controller = controller;
  }

  @override
  void open(Map<String, dynamic> args) => urls.add(args['url'] as String);
  @override
  void play() {}
  @override
  void pause() {}
  @override
  void seekTo(Duration position) {}
  @override
  void selectTrack(NativeTrack track) {}
  @override
  void disableSubtitles() {}
  @override
  Widget buildView(BuildContext context) => const Text('Vidéo native');
  @override
  void dispose() {
    closed = true;
  }
}

class _Transport implements CastTransport {
  @override
  Future<void> playStream({
    required String streamUrl,
    String title = 'Test',
    String? imageUrl,
  }) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  final repo = StartupAdRepository.instance;
  late CastManager cast;
  late List<_Video> videos;
  var requests = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    repo.resetForTesting();
    repo.baseUrl = 'https://fixture.invalid';
    requests = 0;
    repo.client = MockClient((_) async {
      requests++;
      return http.Response(
        jsonEncode(<String, Object>{
          'enabled': true,
          'url': 'https://fixture.invalid/ad.mp4',
          'skip': 1,
          'freq': 'daily',
        }),
        200,
      );
    });
    cast = CastManager.forTesting(
      transportFactory: (_) => _Transport(),
      probe: (url) async =>
          StreamProbeResult(originalUrl: url, finalUrl: url, success: true),
    );
    videos = <_Video>[];
    NativeVideoController.audiblePlayers.debugReset();
    NativeVideoController.backendFactory = () {
      final video = _Video();
      videos.add(video);
      return video;
    };
  });
  tearDown(() async {
    repo.resetForTesting();
    await cast.disconnect();
    cast.dispose();
    NativeVideoController.backendFactory = null;
    NativeVideoController.audiblePlayers.debugReset();
  });

  Future<void> startCast() async {
    // La reprise SDK conserve une diffusion choisie par ce profil. Un simple
    // événement natif sans propriétaire ne peut pas autoriser cette lecture.
    await cast.castTo(
      const CastDevice(
        id: 'startup-ad-cast',
        name: 'TV fictive',
        kind: CastDeviceKind.googleCast,
        host: '192.0.2.1',
        port: 8009,
        controlUrl: '',
      ),
      streamUrl: 'https://fixture.invalid/cast.ts',
      title: 'Cast fictif',
    );
  }

  Future<void> mount(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TvStartupAdGate(castManager: cast, child: const Text('Accueil')),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'pub native avant accueil, fréquence marquée seulement à la première image',
    (tester) async {
      await mount(tester);
      expect(find.text('Vidéo native'), findsOneWidget);
      expect(find.text('Accueil'), findsNothing);
      expect(videos.single.urls, <String>['https://fixture.invalid/ad.mp4']);
      expect(
        (await SharedPreferences.getInstance()).getString('ad_last_day'),
        isNull,
      );
      videos.single.controller.applyBackendEvent('firstFrame', null);
      await tester.pump();
      expect(
        (await SharedPreferences.getInstance()).getString('ad_last_day'),
        isNotNull,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Passer'));
      await tester.pump();
      expect(find.text('Accueil'), findsOneWidget);
      expect(videos.single.closed, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'erreur lecteur libère l’accueil sans consommer la fréquence quotidienne',
    (tester) async {
      await mount(tester);
      videos.single.controller.applyBackendEvent('error', 'erreur simulée');
      await tester.pump();
      expect(find.text('Accueil'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getString('ad_last_day'),
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('l’accueil est visible pendant l’attente, sans écran vide', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    repo.client = MockClient((_) => pending.future);
    await mount(tester);
    expect(find.text('Accueil'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    pending.complete(
      http.Response('{"enabled":false,"url":"","skip":5,"freq":"always"}', 200),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Accueil'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('un ordre du panel affiche la pub sans redémarrer', (
    tester,
  ) async {
    repo.client = MockClient((_) async {
      requests++;
      return http.Response(
        '{"enabled":false,"url":"","skip":5,"freq":"always"}',
        200,
      );
    });
    await mount(tester);
    await tester.pump();
    expect(find.text('Accueil'), findsOneWidget);
    final Stopwatch watch = Stopwatch()..start();
    repo.client = MockClient((_) async {
      return http.Response(
        jsonEncode(<String, Object>{
          'enabled': true,
          'url': 'https://fixture.invalid/promo.mp4',
          'skip': 1,
          'freq': 'always',
        }),
        200,
      );
    });
    await repo.fetch();
    await tester.pump();
    expect(find.text('Vidéo native'), findsOneWidget);
    expect(watch.elapsedMilliseconds, lessThan(2000));
    debugPrint('MESURE ad_push_ms=${watch.elapsedMilliseconds}');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('réponse lente ne recouvre jamais l’accueil déjà ouvert', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    repo.client = MockClient((_) => pending.future);
    await mount(tester);
    await tester.pump(const Duration(milliseconds: 2501));
    expect(find.text('Accueil'), findsOneWidget);
    pending.complete(
      http.Response(
        '{"enabled":true,"url":"https://fixture.invalid/ad.mp4"}',
        200,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Accueil'), findsOneWidget);
    expect(videos, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Cast restauré : aucun lecteur pub ni téléchargement de config', (
    tester,
  ) async {
    await startCast();
    cast.debugNativeSessionEvent(const CastNativeSessionEvent('suspended'));
    cast.debugNativeSessionEvent(const CastNativeSessionEvent('resumed'));
    await mount(tester);
    expect(cast.hasActiveSession, isTrue);
    expect(find.text('Accueil'), findsOneWidget);
    expect(videos, isEmpty);
    expect(requests, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Cast commencé pendant la pub la ferme sans arrêter le Cast', (
    tester,
  ) async {
    await mount(tester);
    await startCast();
    await tester.pump();
    expect(cast.hasActiveSession, isTrue);
    expect(find.text('Accueil'), findsOneWidget);
    expect(videos.single.closed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('arrière-plan ferme la pub, retour ne la relance pas', (
    tester,
  ) async {
    await mount(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Accueil'), findsOneWidget);
    expect(videos, hasLength(1));
    expect(videos.single.closed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
