import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/subscription/data/gold_trial_backend.dart';
import 'package:tv_king/features/subscription/data/gold_trial_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const GoldTrialIdentity identity = GoldTrialIdentity(
      mac:'MK:11:22:33:44:55', androidId:'test-id', appVersion:'1.2.3');
  late ValueNotifier<bool> subscription;
  late ValueNotifier<int> push;
  late GoldTrialController controller;
  late StreamController<List<Playlist>> playlistEvents;
  List<Playlist> savedPlaylists = <Playlist>[];
  Completer<List<Playlist>>? pendingPlaylists;
  bool playlistReadFails = false;
  int posts = 0;
  int gets = 0;
  int imports = 0;
  bool assigned = false;
  bool loaded = false;
  int status = 201;
  String body = '';
  Completer<http.Response>? pending;

  GoldTrialController create() => GoldTrialController(
    backend: GoldTrialBackend(clientFactory: () => MockClient((request) async {
      if (request.method == 'POST') {
        posts++;
        if (pending != null) return await pending!.future;
        return http.Response(body, status);
      }
      gets++;
      return http.Response(assigned
          ? '{"source":{"label":"7 MOTION Essai"}}' : '{"source":null}', 200);
    })),
    loadIdentity: () async => identity,
    sourceHeaders: () async => <String, String>{},
    importSource: () async { imports++; loaded=true; return RemoteSyncResult.loaded; },
    hasSubscription: () => subscription.value,
    hasLoadedTrial: () => loaded,
    subscriptionChanges: subscription, sourceChanges: push,
    loadPlaylists: () async {
      if (playlistReadFails) throw StateError('database unavailable');
      return pendingPlaylists == null ? savedPlaylists : await pendingPlaylists!.future;
    },
    playlistChanges: playlistEvents.stream,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    subscription = ValueNotifier<bool>(false);
    push = ValueNotifier<int>(0);
    playlistEvents = StreamController<List<Playlist>>.broadcast(sync: true);
    savedPlaylists = <Playlist>[]; pendingPlaylists = null; playlistReadFails = false;
    posts=0; gets=0; imports=0; assigned=false; loaded=false;
    status=201; body='{"ok":true,"expire":1793102400}'; pending=null;
    controller=create();
  });
  tearDown(() async {
    controller.dispose(); subscription.dispose(); push.dispose();
    await playlistEvents.close();
  });

  for (final PlaylistType type in PlaylistType.values) {
    test('$type enregistré : caché sans licence payante, même vide/inactif et après retour', () async {
      savedPlaylists = <Playlist>[Playlist(
        id: 1, name: 'Mon abonnement', type: type, createdAt: 1,
        channelCount: 0, isActive: false,
      )];
      await controller.initialize();
      expect(subscription.value, isFalse);
      expect(controller.visible, isFalse);
      await controller.request();
      expect(posts, 0);
      controller.dispose(); controller = create();
      await controller.initialize();
      expect(controller.visible, isFalse);
      expect(controller.canRequest, isFalse);
    });
  }

  test('boot : aucune offre avant SQLite ; événement récent prioritaire', () async {
    pendingPlaylists = Completer<List<Playlist>>();
    final Future<void> boot = controller.initialize();
    expect(controller.visible, isFalse);
    playlistEvents.add(<Playlist>[const Playlist(
      id: 1, name: 'Mon abonnement', type: PlaylistType.m3u, createdAt: 1,
    )]);
    pendingPlaylists!.complete(<Playlist>[]);
    await boot;
    expect(controller.visible, isFalse);
  });

  test('base illisible : offre cachée jusqu’à un état fiable des playlists', () async {
    playlistReadFails = true;
    await controller.initialize();
    expect(controller.visible, isFalse);
    await controller.request();
    expect(posts, 0);
    playlistEvents.add(<Playlist>[]);
    expect(controller.visible, isTrue);
  });

  test('source enregistrée avant son événement UI : aucun POST au clic', () async {
    await controller.initialize();
    expect(controller.visible, isTrue);
    savedPlaylists = <Playlist>[const Playlist(
      id: 1, name: 'Mon abonnement', type: PlaylistType.xtream, createdAt: 1,
    )];
    await controller.request();
    expect(posts, 0);
    expect(controller.visible, isFalse);
    expect(controller.busy, isFalse);
  });

  test('abonné : bouton absent avant et après une notification', () async {
    subscription.value=true;
    await controller.initialize();
    expect(controller.visible, isFalse);
    await controller.request();
    expect(posts, 0);
    subscription.value=false;
    expect(controller.visible, isTrue);
    subscription.value=true;
    expect(controller.visible, isFalse);
  });

  testWidgets('double clic : un seul POST puis arrivée automatique de la liste', (tester) async {
    await controller.initialize();
    pending=Completer<http.Response>();
    final Future<void> first=controller.request();
    final Future<void> second=controller.request();
    await tester.pump();
    expect(posts, 1);
    expect(controller.requesting, isTrue);
    expect(controller.canRequest, isFalse);
    pending!.complete(http.Response(body, status));
    await first; await second;
    expect(controller.result.outcome, GoldTrialOutcome.activated);
    await tester.pump();
    expect(gets, 1); expect(imports, 0);
    assigned=true;
    await tester.pump(const Duration(seconds: 2));
    expect(imports, 1); expect(loaded, isTrue);
    expect(controller.busy, isFalse);
    await tester.pump(const Duration(seconds: 40));
    expect(gets, 2); expect(posts, 1);
  });

  testWidgets('push box : relecture immédiate, sans attendre 2 secondes', (tester) async {
    await controller.initialize();
    await controller.request();
    await tester.pump();
    assigned=true;
    push.value++;
    await tester.pump();
    expect(gets, 2); expect(imports, 1);
    expect(controller.sourceLoaded, isTrue);
  });

  testWidgets('un abonnement reçu remplace la confirmation et arrête le sondage d’essai', (tester) async {
    await controller.initialize();
    await controller.request();
    playlistEvents.add(<Playlist>[const Playlist(
      id: 1, name: kGoldTrialPlaylistName, type: PlaylistType.m3u, createdAt: 1,
    )]);
    expect(controller.visible, isFalse);
    expect(controller.showConfirmation, isTrue);
    playlistEvents.add(<Playlist>[const Playlist(
      id: 2, name: 'Mon abonnement', type: PlaylistType.xtream, createdAt: 2,
    )]);
    expect(controller.showConfirmation, isFalse);
    expect(controller.waitingForSource, isFalse);
    final int readsBefore = gets;
    await tester.pump(const Duration(seconds: 40));
    expect(gets, readsBefore);
  });

  testWidgets('licence arrivée avant 201 : confirmation conservée, bouton caché', (tester) async {
    await controller.initialize();
    pending=Completer<http.Response>();
    final Future<void> request=controller.request();
    await tester.pump();
    subscription.value=true;
    expect(controller.visible, isFalse);
    pending!.complete(http.Response(body, 201));
    await request;
    expect(controller.showConfirmation, isTrue);
    expect(controller.canRequest, isFalse);
    assigned=true;
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('sondage arrêté à 30 secondes ; reprise sans second POST', (tester) async {
    await controller.initialize(); await controller.request();
    for (int i=0; i<16; i++) { await tester.pump(const Duration(seconds: 2)); }
    final int total=gets;
    expect(total, inInclusiveRange(14, 21));
    expect(controller.busy, isFalse);
    expect(controller.sourceFailed, isTrue);
    await tester.pump(const Duration(seconds: 60));
    expect(gets, total);
    assigned=true; controller.retrySource();
    await tester.pump(const Duration(seconds: 2));
    expect(imports, 1); expect(posts, 1);
  });

  test('already_customer reste masqué après retour à l’accueil', () async {
    status=409; body='{"error":"already_customer"}';
    await controller.initialize(); await controller.request();
    expect(controller.visible, isFalse);
    controller.dispose(); controller=create();
    await controller.initialize();
    expect(controller.visible, isFalse);
    await controller.request(); expect(posts, 1);
  });

  testWidgets('in_progress attend la source et interdit les doubles POST', (tester) async {
    status=409; body='{"error":"in_progress"}';
    await controller.initialize(); await controller.request();
    expect(controller.waitingForSource, isTrue);
    await controller.request(); expect(posts, 1);
    assigned=true; await tester.pump(const Duration(seconds: 2));
    expect(imports, 1);
  });

  testWidgets('quitter pendant le POST ne démarre aucun sondage tardif', (tester) async {
    await controller.initialize(); pending=Completer<http.Response>();
    final Future<void> request=controller.request();
    await tester.pump();
    controller.dispose();
    pending!.complete(http.Response(body, 201));
    await request;
    controller=create();
    final int readsBefore = gets;
    await tester.pump(const Duration(seconds: 40));
    expect(gets, readsBefore); expect(imports, 0);
  });
}
