// =========================================================
//  tv_simulator_harness.dart — SIMULATEUR DE TV (harnais partagé)
// =========================================================
//  Première couverture de l'UI TV RÉELLE : ce harnais sait
//    1. préparer un environnement de test complet SANS plateforme native :
//       SQLite réel (sqflite_common_ffi, MODE SANS ISOLATE — indispensable
//       sous testWidgets/FakeAsync, sinon les réponses inter-isolates ne
//       reviennent jamais), path_provider factice (dossier temporaire),
//       SharedPreferences mockées, flavor posé, canal `flutter/platform`
//       neutralisé (HapticFeedback / SystemNavigator.pop) ;
//    2. SEMER de fausses données : playlist active + ~30 chaînes réparties
//       en catégories, EPG now/next, favoris, historique « Récemment » ;
//    3. INJECTER un FAUX LECTEUR plein écran via `registerTvPlayer` (le
//       point d'injection officiel des plateformes, cf. tv_player_screen) :
//       il journalise (chaîne, index, taille de liste) pour assertion et ne
//       touche JAMAIS une PlatformView ;
//    4. MONTER chaque template d'accueil (classic / launcher / rails /
//       tivimate) dans une MaterialApp localisée FR (mêmes délégués gen-l10n
//       que la prod) sur un écran TV 1920×1080 ;
//    5. PILOTER une télécommande simulée : flèches D-pad, OK (Enter),
//       OK long (favori), BACK système (`popRoute`, comme la vraie touche
//       Retour Android TV).
//
//  PIÈGES GÉRÉS (lire avant de modifier) :
//    • pumpAndSettle est INTERDIT ici : plusieurs écrans TV affichent des
//      spinners/tickers permanents → il partirait en timeout. On utilise
//      `tvSettle` (pompes BORNÉES).
//    • Les métriques de police de test (Ahem : chaque glyphe = carré em)
//      sont plus LARGES que les vraies polices → de faux débordements
//      RenderFlex de quelques pixels. `_tolerateAhemOverflow` filtre CES
//      erreurs-là uniquement (toute autre exception fait échouer le test).
//    • CHAQUE test doit finir par `unmountTv` : les écrans portent des
//      timers périodiques (horloges 20-30 s, resync 12 s, veille 10 min) —
//      seuls leurs `dispose` les annulent, sinon flutter_test échoue sur
//      « A Timer is still pending ».
//    • TvLivePreview.debugDisableAutoStart = true : l'aperçu vidéo intégré
//      aux accueils reste sur son repli logo (pas de PlatformView en test).
// =========================================================
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Interface de plateforme de path_provider : on la remplace par un faux
// pointant vers un dossier temporaire (PlaylistDatabase y range tv_king.db).
// Dépendance TRANSITIVE de path_provider — présente dans le package_config.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/channels/data/recently_watched_repository.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/epg/data/epg_repository.dart';
import 'package:tv_king/features/playlists/data/favorites_repository.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/tv/core/tv_home_template.dart';
import 'package:tv_king/features/tv/presentation/tv_app.dart' show TvHomeScreen;
import 'package:tv_king/features/tv/presentation/tv_launcher_home_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_live_preview.dart';
import 'package:tv_king/features/tv/presentation/tv_player_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_rails_home_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_tivimate_home_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

// ============================================================
//  Environnement (une fois par fichier de test)
// ============================================================

bool _envReady = false;
late Directory _docsDir;

/// Faux path_provider : tout pointe vers un dossier temporaire du runner.
class _SimPathProviderPlatform extends PathProviderPlatform {
  _SimPathProviderPlatform(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationCachePath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getDownloadsPath() async => root;
}

Future<void> _initTvSimulatorEnv() async {
  if (_envReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  // SQLite RÉEL en test, SANS isolate (contrainte testWidgets/FakeAsync).
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  _docsDir = Directory.systemTemp.createTempSync('tv_simulator_');
  PathProviderPlatform.instance = _SimPathProviderPlatform(_docsDir.path);
  // FlavorConfig.current est lu par PlaylistRepository (filtre adultOnly) et
  // RecentlyWatchedRepository — sans lui : StateError au premier accès.
  FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
  // Aperçu vidéo neutralisé (pas de PlatformView possible en test widget).
  TvLivePreview.debugDisableAutoStart = true;
  _envReady = true;
}

// ============================================================
//  Remise à zéro (à appeler dans setUp de chaque test)
// ============================================================

/// Faux lecteur ACTIF (réinstallé à chaque reset) — les tests lisent son
/// journal pour vérifier que « OK sur une chaîne » lance LA bonne chaîne.
late TvPlayerProbe tvSimulatorPlayer;

Future<void> resetTvSimulatorState() async {
  await _initTvSimulatorEnv();
  SharedPreferences.setMockInitialValues(<String, Object>{});
  // Canal plateforme neutralisé : HapticFeedback (appui long favori),
  // SystemNavigator.pop (boîte Quitter)… — réponses nulles, jamais
  // d'exception MissingPlugin qui fuiterait en erreur asynchrone.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          SystemChannels.platform, (MethodCall call) async => null);

  // --- Base SQLite : tables prêtes puis VIDÉES (seed idempotent) ---
  final Database db = await PlaylistDatabase.instance.database;
  await EpgRepository.instance.initialize();
  await FavoritesRepository.instance.initialize();
  await RecentlyWatchedRepository.instance.initialize();
  await db.delete('channels');
  await db.delete('playlists');
  await db.delete('favorites');
  await db.delete('favorites_scoped');
  await db.delete('watch_sessions');
  // EPG : clearAll purge AUSSI le cache mémoire « programme en cours »
  // (TTL 60 s) — sans ça, un test précédent pouvait laisser des `null`
  // périmés servis au test suivant.
  await EpgRepository.instance.clearAll();
  await db.delete('epg_aliases');
  // Historique : clear() remet aussi le cache mémoire + notifie le stream.
  await RecentlyWatchedRepository.instance.clear();
  // Favoris : les singletons survivent entre tests du même fichier — on
  // force un RECHARGEMENT du cache depuis la base (vidée) en basculant de
  // portée aller-retour (l'API publique ne propose pas de reset direct).
  await FavoritesRepository.instance.setScope('simulator.flush');
  await FavoritesRepository.instance.setScope(FavoritesRepository.defaultScope);
  // Émet l'état courant (vide) → currentChannels cohérent pour les écrans.
  await PlaylistRepository.instance.initialize();

  // --- Faux lecteur plein écran (OBLIGATOIRE : le défaut est le lecteur
  //     natif Android, immontable en test) ---
  tvSimulatorPlayer = installFakeTvPlayer();
}

// ============================================================
//  Semis de données
// ============================================================

/// Catégories du bouquet simulé (sans accents : lisible dans les finders).
const List<String> kSimCategories = <String>[
  'Sport',
  'Cinema',
  'News',
  'Enfants',
  'Generalistes',
];

/// Sème une playlist ACTIVE + [count] chaînes réparties en catégories
/// (cycle Sport → Cinema → News → Enfants → Generalistes). URLs factices en
/// `.m3u8` (aucune requête : lecteur faux + aperçu désactivé), logos ABSENTS
/// (monogramme de repli — zéro requête d'image réseau).
/// Renvoie les chaînes DANS L'ORDRE de la playlist (sim-001 = « Sport 1 »).
Future<List<Channel>> seedTvChannels({int count = 30}) async {
  final Database db = await PlaylistDatabase.instance.database;
  final int now = DateTime.now().millisecondsSinceEpoch;
  final int playlistId = await db.insert('playlists', <String, Object?>{
    'name': 'Bouquet simulateur',
    'type': 'm3u',
    'm3u_url': 'http://sim.invalid/playlist.m3u',
    'created_at': now,
    'channel_count': count,
    'is_active': 1,
  });
  final List<Channel> out = <Channel>[];
  final Batch batch = db.batch();
  for (int i = 1; i <= count; i++) {
    final String cat = kSimCategories[(i - 1) % kSimCategories.length];
    final String id = 'sim-${i.toString().padLeft(3, '0')}';
    final String name = '$cat ${((i - 1) ~/ kSimCategories.length) + 1}';
    final String url = 'http://sim.invalid/live/$id.m3u8';
    batch.insert('channels', <String, Object?>{
      'playlist_id': playlistId,
      'external_id': id,
      'name': name,
      'category': cat,
      'stream_url': url,
      'logo_url': null,
      'is_live': 1,
    });
    out.add(Channel(
      id: id,
      playlistId: playlistId,
      name: name,
      category: cat,
      streamUrl: url,
      isLive: true,
    ));
  }
  await batch.commit(noResult: true);
  // Ré-émet chaînes + playlists sur les streams (les écrans écoutent).
  await PlaylistRepository.instance.initialize();
  return out;
}

/// Sème un EPG minimal pour [channelIds] : un programme EN COURS
/// (« Maintenant n », de −30 min à +30 min) et un SUIVANT (« Ensuite n »,
/// de +30 min à +90 min). n = position (1-based) dans [channelIds].
Future<void> seedTvEpg(Iterable<String> channelIds) async {
  await EpgRepository.instance.initialize();
  final Database db = await PlaylistDatabase.instance.database;
  final DateTime now = DateTime.now();
  final int nowStart = now.subtract(const Duration(minutes: 30)).millisecondsSinceEpoch;
  final int nowStop = now.add(const Duration(minutes: 30)).millisecondsSinceEpoch;
  final int nextStop = now.add(const Duration(minutes: 90)).millisecondsSinceEpoch;
  final Batch batch = db.batch();
  int n = 0;
  for (final String id in channelIds) {
    n++;
    batch.insert('epg_programs', <String, Object?>{
      'channel_id': id,
      'start_time': nowStart,
      'stop_time': nowStop,
      'title': 'Maintenant $n',
      'description': 'Programme en cours (simulateur)',
    });
    batch.insert('epg_programs', <String, Object?>{
      'channel_id': id,
      'start_time': nowStop,
      'stop_time': nextStop,
      'title': 'Ensuite $n',
      'description': 'Programme suivant (simulateur)',
    });
  }
  await batch.commit(noResult: true);
}

/// Ajoute UNE chaîne à la playlist active DÉJÀ semée puis ré-émet les
/// streams — simule un RESYNC de source pendant que l'écran est affiché.
Future<void> seedExtraTvChannel({
  required String id,
  required String name,
  required String category,
}) async {
  final Database db = await PlaylistDatabase.instance.database;
  final List<Map<String, Object?>> active = await db.query('playlists',
      columns: <String>['id'], where: 'is_active = 1', limit: 1);
  final int playlistId = active.first['id']! as int;
  await db.insert('channels', <String, Object?>{
    'playlist_id': playlistId,
    'external_id': id,
    'name': name,
    'category': category,
    'stream_url': 'http://sim.invalid/live/$id.m3u8',
    'logo_url': null,
    'is_live': 1,
  });
  await PlaylistRepository.instance.initialize(); // ré-émet channelsStream
}

/// Marque [ids] favoris (portée active). Idempotent.
Future<void> seedTvFavorites(Iterable<String> ids) async {
  for (final String id in ids) {
    if (!FavoritesRepository.instance.isFavorite(id)) {
      await FavoritesRepository.instance.toggle(id);
    }
  }
}

/// Alimente l'historique « Récemment regardé » (le premier de [ids] devient
/// le plus récent).
Future<void> seedTvRecents(Iterable<String> ids) async {
  for (final String id in ids.toList().reversed) {
    await RecentlyWatchedRepository.instance.record(id);
  }
}

// ============================================================
//  Faux lecteur plein écran
// ============================================================

/// Une lecture demandée au faux lecteur.
class TvSimPlay {
  const TvSimPlay({
    required this.channelId,
    required this.channelName,
    required this.startIndex,
    required this.channelCount,
  });
  final String channelId;
  final String channelName;
  final int startIndex;
  final int channelCount;
}

/// Journal du faux lecteur (une entrée par MONTAGE d'écran lecteur).
class TvPlayerProbe {
  final List<TvSimPlay> plays = <TvSimPlay>[];
  TvSimPlay get last => plays.last;
}

/// Texte affiché par le faux lecteur (repère pour les finders).
const String kFakePlayerMarker = 'LECTEUR SIMULÉ';

/// Injecte le faux lecteur via [registerTvPlayer] (même point d'entrée que
/// Windows/Tizen en prod). Widget 100 % inerte : aucun canal natif.
TvPlayerProbe installFakeTvPlayer() {
  final TvPlayerProbe probe = TvPlayerProbe();
  registerTvPlayer((List<Channel> channels, int startIndex) {
    return _FakeTvPlayerScreen(
      probe: probe,
      channels: channels,
      startIndex: startIndex,
    );
  });
  return probe;
}

class _FakeTvPlayerScreen extends StatefulWidget {
  const _FakeTvPlayerScreen({
    required this.probe,
    required this.channels,
    required this.startIndex,
  });
  final TvPlayerProbe probe;
  final List<Channel> channels;
  final int startIndex;

  @override
  State<_FakeTvPlayerScreen> createState() => _FakeTvPlayerScreenState();
}

class _FakeTvPlayerScreenState extends State<_FakeTvPlayerScreen> {
  @override
  void initState() {
    super.initState();
    // Journalisé au MONTAGE (pas dans le builder : il peut être rappelé à
    // chaque rebuild de route) → exactement 1 entrée par ouverture.
    final int i = (widget.startIndex >= 0 &&
            widget.startIndex < widget.channels.length)
        ? widget.startIndex
        : 0;
    final Channel c = widget.channels.isEmpty
        ? const Channel(
            id: 'sim-vide',
            name: '(aucune chaîne)',
            category: '',
            streamUrl: '',
            isLive: true,
          )
        : widget.channels[i];
    widget.probe.plays.add(TvSimPlay(
      channelId: c.id,
      channelName: c.name,
      startIndex: widget.startIndex,
      channelCount: widget.channels.length,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final String name = widget.channels.isEmpty
        ? '(aucune chaîne)'
        : widget
            .channels[(widget.startIndex >= 0 &&
                    widget.startIndex < widget.channels.length)
                ? widget.startIndex
                : 0]
            .name;
    return Material(
      color: Colors.black,
      child: Focus(
        autofocus: true,
        child: Center(
          child: Text(
            '$kFakePlayerMarker · $name',
            style: const TextStyle(color: Colors.white, fontSize: 24),
          ),
        ),
      ),
    );
  }
}

// ============================================================
//  Montage des écrans
// ============================================================

/// Coquille MaterialApp « prod-like » : localisations gen-l10n (FR), thème
/// sombre, observer de routes de l'aperçu (comme TvApp) — SANS GoogleFonts
/// ni canevas FittedBox (inutiles pour la logique testée ici).
Widget tvAppShell(Widget home) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('fr'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      splashFactory: NoSplash.splashFactory,
    ),
    navigatorObservers: <NavigatorObserver>[TvLivePreview.routeObserver],
    home: home,
  );
}

/// Monte l'ACCUEIL du template demandé (l'écran RÉEL, pas une maquette) sur
/// un écran TV 1920×1080, puis stabilise avec des pompes bornées.
Future<void> pumpTvTemplate(WidgetTester tester, TvHomeTemplate template) async {
  final Widget home = switch (template) {
    TvHomeTemplate.classic => const TvHomeScreen(),
    TvHomeTemplate.launcher => const TvLauncherHomeScreen(),
    TvHomeTemplate.rails => const TvRailsHomeScreen(),
    TvHomeTemplate.tivimate => const TvTivimateHomeScreen(),
  };
  await pumpTvScreen(tester, home);
}

/// Monte un écran TV arbitraire (guide, etc.) dans la coquille du simulateur.
Future<void> pumpTvScreen(WidgetTester tester, Widget screen) async {
  _useTvViewport(tester);
  _tolerateAhemOverflow();
  await tester.pumpWidget(tvAppShell(screen));
  await tvSettle(tester);
}

/// Démonte TOUT (dispose → timers périodiques annulés). À appeler à la FIN
/// de chaque test — sinon « A Timer is still pending » côté flutter_test.
Future<void> unmountTv(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));
}

/// Stabilisation BORNÉE (jamais pumpAndSettle : spinners/tickers infinis).
Future<void> tvSettle(
  WidgetTester tester, {
  int frames = 10,
  Duration step = const Duration(milliseconds: 60),
}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

void _useTvViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

// ---- Tolérance aux débordements « police de test » --------------------
// Les tests dessinent avec Ahem (chaque glyphe = carré em) : les textes y
// sont bien plus LARGES qu'en prod → de faux « RenderFlex overflowed by
// N pixels ». On filtre UNIQUEMENT ces erreurs-là ; tout le reste échoue
// normalement. Restauré automatiquement en fin de test (addTearDown).
bool _overflowToleranceActive = false;

void _tolerateAhemOverflow() {
  if (_overflowToleranceActive) return;
  _overflowToleranceActive = true;
  final FlutterExceptionHandler? previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final Object exception = details.exception;
    if (exception is FlutterError && exception.message.contains('overflowed')) {
      return; // faux positif métrique Ahem — ignoré
    }
    previous?.call(details);
  };
  addTearDown(() {
    FlutterError.onError = previous;
    _overflowToleranceActive = false;
  });
}

// ============================================================
//  Télécommande simulée
// ============================================================

Future<void> pressKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump(const Duration(milliseconds: 40));
  await tester.pump(const Duration(milliseconds: 180)); // anim de focus finie
}

Future<void> pressUp(WidgetTester tester) =>
    pressKey(tester, LogicalKeyboardKey.arrowUp);
Future<void> pressDown(WidgetTester tester) =>
    pressKey(tester, LogicalKeyboardKey.arrowDown);
Future<void> pressLeft(WidgetTester tester) =>
    pressKey(tester, LogicalKeyboardKey.arrowLeft);
Future<void> pressRight(WidgetTester tester) =>
    pressKey(tester, LogicalKeyboardKey.arrowRight);

/// OK télécommande (Enter — TvFocusable accepte select/enter/espace).
Future<void> pressOk(WidgetTester tester) async {
  await pressKey(tester, LogicalKeyboardKey.enter);
  await tvSettle(tester);
}

/// OK MAINTENU (> 450 ms) = appui long (toggle favori sur les listes).
Future<void> pressOkLong(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
  await tvSettle(tester);
}

/// BACK télécommande : le VRAI chemin Android TV (message système
/// `popRoute`) → PopScope/Navigator réagissent comme sur box.
Future<void> pressBack(WidgetTester tester) async {
  final ByteData message =
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute'));
  // ChannelBuffers.push = chemin moderne et stable pour simuler un message
  // PLATEFORME → framework (le handler navigation de WidgetsBinding le
  // reçoit comme un vrai appui Retour de box Android TV).
  tester.binding.channelBuffers
      .push('flutter/navigation', message, (ByteData? _) {});
  await tvSettle(tester);
}

/// 15 appuis D-pad variés — la « tournée » standard du simulateur. Vérifie
/// après CHAQUE appui qu'un widget monté porte toujours le focus.
const List<LogicalKeyboardKey> kTvDpadTour = <LogicalKeyboardKey>[
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowLeft,
];

Future<void> runDpadTour(WidgetTester tester) async {
  for (final LogicalKeyboardKey key in kTvDpadTour) {
    await pressKey(tester, key);
    expectTvFocusAlive();
  }
}

// ============================================================
//  Assertions partagées
// ============================================================

/// Le focus « vit » : un nœud non-nul, rattaché à un widget monté. C'est le
/// garde-fou n°1 d'une app TV (focus perdu = télécommande morte).
void expectTvFocusAlive() {
  final FocusNode? focus = FocusManager.instance.primaryFocus;
  expect(focus, isNotNull, reason: 'aucun nœud ne porte le focus (D-pad mort)');
  expect(focus!.context, isNotNull,
      reason: 'le focus pointe un nœud détaché de l\'arbre (D-pad mort)');
}
