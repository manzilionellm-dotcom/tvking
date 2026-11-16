// =========================================================
//  Intégration : le client NovaTube TV contre le VRAI Worker Atlas (local)
// =========================================================
//  Ignoré par défaut. Pour le lancer :
//    1. node ci/novatube_tv/atlas_local_server.mjs <dossier_cloudflare> /tmp/atlas.json
//       (code serveur des routes /api/novatube4k/*, base D1 locale vide,
//        aucun réseau sortant)
//    2. NOVATUBE_ATLAS_LOCAL=/tmp/atlas.json flutter test \
//         --dart-define=NOVATUBE_TV=true test/novatube_tv/atlas_local_integration_test.dart
//  Aucune requête ne part vers la production.
// =========================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/novatube_tv_edition.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/device/data/novatube_identity.dart';
import 'package:tv_king/features/subscription/data/novatube_atlas.dart';
import 'package:tv_king/features/subscription/data/remote_activation_watch.dart';
import 'package:tv_king/features/subscription/data/subscription_backend.dart';
import 'package:tv_king/features/subscription/data/subscription_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final String? infoPath = Platform.environment['NOVATUBE_ATLAS_LOCAL'];
  final String? skip = (infoPath == null || !kNovatubeTv)
      ? 'Atlas local absent (NOVATUBE_ATLAS_LOCAL) ou build Zuno'
      : null;
  late String base;
  late String adminSecret;

  setUpAll(() {
    if (skip != null) return;
    // flutter_test bloque le réseau par défaut : ici on parle au Worker LOCAL.
    HttpOverrides.global = null;
    final Map<String, dynamic> info =
        jsonDecode(File(infoPath!).readAsStringSync()) as Map<String, dynamic>;
    base = info['url'] as String;
    adminSecret = info['adminSecret'] as String;
    NovatubeAtlas.baseUrl = base;
    NovatubeAtlas.clientFactory = http.Client.new;
  });

  setUp(() {
    // Une « box » neuve par test : graine aléatoire, préférences vides.
    final String seed = List<int>.generate(12, (_) => Random.secure().nextInt(256))
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NovatubeIdentity.seedProvider = () async => seed;
    NovatubeIdentity.instance.resetForTesting();
    NovatubeAtlas.instance.resetForTesting();
  });

  Future<int> activateAsAdmin(String mac) async {
    final http.Response login = await http.post(
      Uri.parse('$base/api/v1/auth/login'),
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(<String, String>{'email': 'admin', 'password': adminSecret}),
    );
    final String token = (jsonDecode(login.body) as Map<String, dynamic>)['token'] as String;
    final http.Response r = await http.post(
      Uri.parse('$base/api/v1/activate'),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'Idempotency-Key': 'novatube-tv-${DateTime.now().microsecondsSinceEpoch}',
      },
      body: jsonEncode(<String, String>{'mac': mac, 'plan': 'yearly', 'app_id': 'app_7motion'}),
    );
    return r.statusCode;
  }

  test('nouvelle box : fiche NovaTube, essai SERVEUR de 10 jours, même code que le panel',
      () async {
    final RemoteStatusRead read = await NovatubeAtlas.instance.readStatus();
    expect(read.reached, isTrue);
    expect(read.status.exists, isTrue);
    expect(read.status.pending, isFalse);
    expect(read.status.paid, isFalse);
    expect(read.status.daysLeft, 10);
    final NovatubeReply state = await NovatubeAtlas.instance.post('state', const <String, Object?>{});
    expect(state.body!['app_id'], 'app_novatube4k');
    expect(state.body!['plan'], 'trial10');
    expect(state.body!['mac'], await NovatubeIdentity.instance.mac);
  }, skip: skip);

  test('activation par l\'administrateur Atlas : la box voit une licence payée', () async {
    await NovatubeAtlas.instance.readStatus();
    expect(await activateAsAdmin(await NovatubeIdentity.instance.mac), 201);
    final RemoteStatusRead read = await NovatubeAtlas.instance.readStatus();
    expect(read.status.paid, isTrue);
    expect(read.status.paidUntil, greaterThan(DateTime.now().millisecondsSinceEpoch));
  }, skip: skip);

  test('le renouvellement du serveur réveille la box en moins de 5 secondes', () async {
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    final state = SubscriptionState.instance;
    await state.initialize();
    expect(await state.syncWithBackend(), RemoteSyncOutcome.applied);
    expect(state.status, SubscriptionStatus.trialActive);
    final paid = Completer<void>();
    void observe() {
      if (state.status == SubscriptionStatus.paid && !paid.isCompleted) {
        paid.complete();
      }
    }
    state.addListener(observe);
    final watch = RemoteActivationWatch.instance;
    watch.start(allowSourceImport: false);
    try {
      final mac = await NovatubeIdentity.instance.mac;
      final clock = Stopwatch()..start();
      expect(await activateAsAdmin(mac), 201);
      await paid.future.timeout(const Duration(seconds: 5));
      expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
    } finally {
      watch.stop();
      state.removeListener(observe);
    }
  }, skip: skip);

  test('données effacées (nouvelle clé) : la fiche reste protégée, réassociation', () async {
    await NovatubeAtlas.instance.readStatus();
    final String mac = await NovatubeIdentity.instance.mac;
    // Simule l'effacement des données : même ANDROID_ID, nouvelle clé.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(NovatubeIdentity.kDeviceKeyKey, 'b' * 64);
    NovatubeIdentity.instance.resetForTesting();
    NovatubeAtlas.instance.resetForTesting();
    expect(await NovatubeIdentity.instance.mac, mac); // même code affiché
    final RemoteStatusRead read = await NovatubeAtlas.instance.readStatus();
    expect(read.reached, isTrue);
    expect(read.status.pending, isTrue); // aucun accès avec une clé étrangère
    expect(read.status.paid, isFalse);
  }, skip: skip);

  test('SubscriptionState : statut de l\'app = essai serveur (porte ouverte)', () async {
    await SubscriptionState.instance.initialize();
    final RemoteSyncOutcome outcome = await SubscriptionState.instance.syncWithBackend();
    expect(outcome, RemoteSyncOutcome.applied);
    expect(SubscriptionState.instance.status, SubscriptionStatus.trialActive);
  }, skip: skip);
}
