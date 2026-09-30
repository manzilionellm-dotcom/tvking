// =========================================================
//  cinema_repository.dart — Films & Séries (tous les comptes Xtream)
// =========================================================
//  Principe « fluide sur une box 1 Go » (le même que le Direct) :
//
//  1. CATÉGORIES d'abord (quelques Ko) : l'écran s'affiche tout de suite.
//  2. Chaque catégorie est chargée À LA DEMANDE (`&category_id=`), décodée
//     et convertie dans un ISOLATE, puis gardée en cache (LRU de 30
//     catégories) : ouvrir « Action » ne télécharge QUE l'Action.
//  3. En arrière-plan, un INDEX complet (recherche, « Récemment ajoutés »,
//     compteurs) est construit : liste entière si elle tient sous
//     [kCinemaSingleShotBytes], sinon catégorie par catégorie. Un seul type
//     indexé à la fois (films OU séries) pour borner la mémoire.
//  4. Plusieurs comptes : les catégories de même nom sont FUSIONNÉES et un
//     titre présent sur deux comptes n'apparaît qu'une fois.
//  5. Le dernier catalogue COMPLET est aussi sur le disque (dossier
//     `zuno_catalog`, à part des favoris / historique / profils). L'écran
//     l'affiche tout de suite. Un téléchargement en arrière-plan ne le
//     remplace qu'une fois fini et non vide. Une erreur ne l'efface pas.
//
//  Toutes les erreurs réseau d'un compte sont journalisées (boîte noire) et
//  n'empêchent jamais les autres comptes de s'afficher.
// =========================================================
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/blackbox/black_box.dart';
import '../../channels/domain/channel_genre.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/xtream_client.dart';
import '../../playlists/domain/playlist.dart';
import '../../tv/core/tv_activity.dart';
import '../../vod/domain/vod_movie.dart';
import '../domain/cinema_language.dart';
import '../domain/cinema_models.dart';
import 'catalog_cache_policy.dart';
import 'catalog_disk.dart';
import 'catalog_refresh.dart';
import 'cinema_parsers.dart';

/// Au-delà, la liste complète n'est PAS téléchargée d'un bloc (index construit
/// catégorie par catégorie). Même logique que l'import des chaînes.
const int kCinemaSingleShotBytes = 12 * 1024 * 1024;

/// Plafond de titres gardés dans l'index de RECHERCHE sur une petite box
/// (≤ 1 Go). Relevé selon la RAM réelle de la box, cf. [CinemaRepository.tuneForRam].
/// Les CATÉGORIES, elles, ne sont jamais plafonnées par l'index : si l'index
/// est partiel, elles sont lues en entier directement sur le serveur.
const int kCinemaIndexMax = 40000;

/// Plafond d'UNE catégorie lue sur le serveur (garde-fou mémoire seulement :
/// aucune catégorie réelle n'approche ce chiffre).
const int kCinemaCategoryMax = 150000;

/// Au-delà de cet âge, le catalogue en mémoire est relu à l'ouverture de
/// Films / Séries (nouveaux titres ajoutés par le fournisseur).
const Duration kCinemaMaxAge = Duration(minutes: 10);

class CinemaRepository {
  CinemaRepository._();
  static final CinemaRepository instance = CinemaRepository._();

  // ---------------- Mémoire de la box ----------------

  /// Plafond EFFECTIF de l'index, adapté à la RAM (voir [tuneForRam]).
  int _indexMax = kCinemaIndexMax;
  bool _ramTuned = false;
  static const MethodChannel _device =
      MethodChannel('com.manzilionellm.tvking/device');

  /// Adapte le plafond de l'index à la RAM RÉELLE de la box (une fois).
  /// Ordre de grandeur mesuré côté Dart : ~0,5 Ko par titre en mémoire.
  ///   ≤ 1 Go → 40 000 titres (~20 Mo) · ≤ 2 Go → 60 000 ·
  ///   ≤ 3 Go → 100 000 · au-delà → 150 000 (~75 Mo).
  /// Info indisponible (PC, échec) → défaut prudent de 40 000.
  Future<void> tuneForRam() async {
    if (_ramTuned) return;
    _ramTuned = true;
    try {
      final Object? raw = await _device.invokeMethod<Object?>('getMemoryInfo');
      if (raw is! Map) return;
      final int mb = (raw['totalMb'] as num?)?.toInt() ?? 0;
      final bool low = raw['lowRam'] == true;
      if (low || mb <= 0 || mb <= 1100) {
        _indexMax = kCinemaIndexMax;
      } else if (mb <= 2100) {
        _indexMax = 60000;
      } else if (mb <= 3100) {
        _indexMax = 100000;
      } else {
        _indexMax = 150000;
      }
      BlackBox.instance
          .info('CINEMA', 'RAM $mb Mo → index jusqu\'à $_indexMax titres');
    } catch (_) {
      // Plateforme sans plugin (PC) : défaut prudent.
    }
  }

  /// PC (Zuno Windows) : un ordinateur a largement la mémoire nécessaire
  /// (8 Go et plus en général) et le plugin RAM de la box n'y existe pas →
  /// index de recherche au maximum, sans lecture de RAM.
  void useDesktopMemory() {
    _ramTuned = true;
    _indexMax = 150000;
  }

  /// Moment du dernier chargement des catégories (fraîcheur du catalogue).
  DateTime? _loadedAt;

  /// Date enregistrée SUR LE DISQUE, par type (films / séries).
  /// C'est elle qui alimente « mis à jour il y a X ».
  final Map<CinemaKind, DateTime> _updatedAt = <CinemaKind, DateTime>{};

  /// Vrai quand les titres de ce type sont déjà dans un catalogue publié.
  final Map<CinemaKind, bool> _persisted = <CinemaKind, bool>{};

  /// Le prochain passage doit retélécharger, sans jeter ce qui est affiché.
  bool _wantsRefresh = false;

  /// Dossier disque du compte courant (empreinte, pas le mot de passe).
  String? _folderSig;

  CatalogDisk? _disk;
  final CatalogRefresher _refresher = const CatalogRefresher();
  final Random _jitter = Random();
  final Map<CinemaKind, Future<void>> _refreshInFlight =
      <CinemaKind, Future<void>>{};

  /// Dernier essai de téléchargement. Évite de retaper le serveur en boucle
  /// quand il ne répond pas et qu'on n'a encore rien enregistré.
  DateTime? _refreshStartedAt;

  /// Augmente à chaque [clear] : un téléchargement commencé avant s'arrête
  /// et ne publie pas.
  int _catalogGen = 0;

  /// À appeler à l'ouverture de Films / Séries.
  ///
  /// Avant : au bout de 10 minutes on VIDAIT la mémoire. Si le serveur ne
  /// répondait pas, l'écran n'avait plus rien et affichait « aucun film ».
  /// Maintenant on garde le catalogue et on note qu'il faut le rafraîchir
  /// en arrière-plan. L'écran ne passe jamais au vide s'il a déjà une liste.
  void refreshIfStale() {
    final DateTime? at = _loadedAt;
    if (at != null && DateTime.now().difference(at) > kCinemaMaxAge) {
      BlackBox.instance.info('CINEMA',
          'catalogue de plus de ${kCinemaMaxAge.inMinutes} min → rafraîchi en arrière-plan');
      _wantsRefresh = true;
    }
  }

  /// Redémarrage / bouton Réessayer : relire le fournisseur, sans effacer
  /// le catalogue déjà sur la box.
  void requestRefresh() {
    _wantsRefresh = true;
  }

  /// Oublie les catégories en mémoire pour UN type (le bouton Réessayer).
  /// Le disque n'est pas touché.
  void dropKindMemory(CinemaKind kind) {
    _cats.remove(kind);
    _catKeys.remove(kind);
    _persisted.remove(kind);
    _wantsRefresh = true;
  }

  /// Date du catalogue affiché, ou null s'il n'y en a pas encore.
  DateTime? catalogUpdatedAt(CinemaKind kind) => _updatedAt[kind];

  /// Âge du catalogue pour la phrase « mis à jour … ».
  CatalogAge? catalogAgeAt(CinemaKind kind, DateTime now) {
    final DateTime? at = _updatedAt[kind];
    if (at == null) return null;
    return catalogAge(at, now);
  }

  /// Catégories déjà en mémoire (l'écran s'en sert après un rafraîchissement).
  List<CinemaCategory>? peekCategories(CinemaKind kind) => _cats[kind];

  // ---------------- État ----------------
  String _sourcesSig = '';
  List<CinemaSource> _sources = const <CinemaSource>[];
  final Map<String, XtreamClient> _clients = <String, XtreamClient>{};

  final Map<CinemaKind, List<CinemaCategory>> _cats =
      <CinemaKind, List<CinemaCategory>>{};

  /// kind → sourceKey → id catégorie serveur → clé fusionnée.
  final Map<CinemaKind, Map<String, Map<String, String>>> _catKeys =
      <CinemaKind, Map<String, Map<String, String>>>{};

  /// Cache LRU des catégories chargées (`kind|catKey`).
  final LinkedHashMap<String, List<CinemaTitle>> _titles =
      LinkedHashMap<String, List<CinemaTitle>>();
  static const int _kTitleCacheMax = 30;

  /// Index complet d'UN type (films ou séries).
  CinemaKind? _indexKind;

  /// Génération de l'index : une construction dépassée (écran quitté puis
  /// rouvert) s'arrête d'elle-même et ne publie plus rien.
  int _indexGen = 0;
  List<CinemaTitle> _index = const <CinemaTitle>[];
  bool _indexDone = false;

  /// Vrai seulement si l'index contient TOUT le catalogue : plafond
  /// [kCinemaIndexMax] non atteint ET aucun compte / aucune catégorie en
  /// échec. Sinon, les catégories sont lues directement sur le serveur
  /// (liste complète) — cause du bug « ça ne prend que la moitié » : sur un
  /// gros catalogue (> 40 000 titres) ou une box lente, l'index était
  /// partiel et les catégories étaient servies depuis cet index incomplet.
  bool _indexComplete = false;
  Future<void>? _indexing;
  Map<String, int> _indexCounts = const <String, int>{};
  List<CinemaTitle>? _recent;

  /// Incrémenté quand l'index grandit / se termine → l'écran se met à jour
  /// (recherche, compteurs, « Récemment ajoutés »).
  final ValueNotifier<int> indexVersion = ValueNotifier<int>(0);

  final LinkedHashMap<String, CinemaDetails> _details =
      LinkedHashMap<String, CinemaDetails>();
  final LinkedHashMap<String, SeriesDetails> _series =
      LinkedHashMap<String, SeriesDetails>();

  // ---------------- Comptes ----------------

  /// Comptes Xtream du client. Si la liste change (compte ajouté / retiré /
  /// poussé par le panel), tous les caches sont vidés.
  Future<List<CinemaSource>> sources() async {
    final List<Playlist> all =
        await PlaylistRepository.instance.getAllPlaylists();
    final List<CinemaSource> out = <CinemaSource>[];
    for (final Playlist p in all) {
      if (p.type != PlaylistType.xtream) continue;
      if (p.hidden) continue; // source désactivée par le client
      final String server = (p.xtreamServer ?? '').trim();
      final String user = (p.xtreamUsername ?? '').trim();
      if (server.isEmpty || user.isEmpty || p.id == null) continue;
      out.add(CinemaSource(
        key: 'p${p.id}',
        playlistId: p.id!,
        server: server.endsWith('/')
            ? server.substring(0, server.length - 1)
            : server,
        username: user,
        password: p.xtreamPassword ?? '',
      ));
    }
    final String sig = out
        .map((CinemaSource s) => '${s.key}@${s.server}/${s.username}')
        .join(',');
    if (sig != _sourcesSig) {
      clear();
      _sourcesSig = sig;
      _sources = out;
    }
    // Empreinte du dossier cache. Le mot de passe n'entre PAS dedans :
    // s'il change, les films déjà enregistrés restent lisibles (l'URL est
    // reconstruite avec le nouveau mot de passe).
    _folderSig = out.isEmpty
        ? null
        : catalogFolderName(out
            .map(
                (CinemaSource s) => '${s.playlistId}|${s.server}|${s.username}')
            .join('\n'));
    return _sources;
  }

  CinemaSource? sourceByKey(String key) {
    for (final CinemaSource s in _sources) {
      if (s.key == key) return s;
    }
    return null;
  }

  XtreamClient _client(CinemaSource s) => _clients.putIfAbsent(
        s.key,
        () => XtreamClient(
          serverUrl: s.server,
          username: s.username,
          password: s.password,
          timeout: const Duration(seconds: 25),
        ),
      );

  // ---------------- Catégories ----------------

  /// Catégories fusionnées de tous les comptes (ordre du 1er compte).
  ///
  /// Ordre : mémoire, puis disque (affichage immédiat), puis réseau.
  /// Une erreur réseau sans rien d'enregistré ne mémorise PAS la liste vide :
  /// sinon l'écran afficherait « aucun film » jusqu'au prochain vidage.
  Future<List<CinemaCategory>> categories(CinemaKind kind) async {
    final List<CinemaSource> srcs = await sources();
    final List<CinemaCategory>? cached = _cats[kind];
    if (cached != null) {
      if (srcs.isNotEmpty && _needsRefresh(kind)) {
        unawaited(_refreshCatalog(kind));
      }
      return cached;
    }

    final CatalogHeader? header = await _readDiskHeader(kind);
    if (header != null && header.categories.isNotEmpty) {
      _installHeader(kind, header);
      _persisted[kind] = true;
      if (srcs.isNotEmpty && _needsRefresh(kind)) {
        unawaited(_refreshCatalog(kind));
      }
      return _cats[kind] ?? const <CinemaCategory>[];
    }

    if (srcs.isEmpty) return const <CinemaCategory>[];

    final _CatFetch fetched = await _fetchMerged(kind);
    final bool keep = rememberCategoryList(
      count: fetched.categories.length,
      anySuccess: fetched.anySuccess,
      anyFailure: fetched.anyFailure,
    );
    if (keep) {
      _cats[kind] = fetched.categories;
      _catKeys[kind] = fetched.keys;
      _loadedAt ??= DateTime.now();
      if (fetched.categories.isNotEmpty) {
        _persisted[kind] = false;
        unawaited(_refreshCatalog(kind));
      }
    }
    BlackBox.instance.info('CINEMA',
        '${kind.name} : ${fetched.categories.length} catégories (${srcs.length} compte(s))');
    return fetched.categories;
  }

  bool _needsRefresh(CinemaKind kind) {
    if (_wantsRefresh) return true;
    if (_persisted[kind] == true) {
      final DateTime? at = _updatedAt[kind];
      if (at == null) return true;
      return DateTime.now().difference(at) > kCinemaMaxAge;
    }
    final DateTime? started = _refreshStartedAt;
    if (started != null &&
        DateTime.now().difference(started) < const Duration(minutes: 2)) {
      return false;
    }
    return true;
  }

  // ---------------- Titres d'une catégorie ----------------

  /// Titres d'une catégorie (mémoire, disque, ou réseau).
  Future<List<CinemaTitle>> titles(CinemaKind kind, CinemaCategory cat) async {
    return (await loadTitles(kind, cat)).titles;
  }

  /// Comme [titles], mais dit si l'échec vient du serveur.
  ///
  /// [failed] n'est vrai que lorsqu'on n'a RIEN à montrer (ni mémoire, ni
  /// disque) et que le serveur n'a pas répondu. Une catégorie vraiment vide
  /// a [failed] à faux : l'écran peut dire « rien ici ».
  Future<CinemaTitleLoad> loadTitles(
    CinemaKind kind,
    CinemaCategory cat, {
    bool forceNetwork = false,
  }) async {
    await sources();
    final String ck = '${kind.name}|${cat.key}';
    if (!forceNetwork) {
      final List<CinemaTitle>? hit = _titles.remove(ck);
      if (hit != null) {
        _titles[ck] = hit; // remis en fin = « récemment utilisé »
        return CinemaTitleLoad(titles: hit, fromCache: true, failed: false);
      }
      final List<CinemaTitle>? saved = await _titlesFromDisk(kind, cat.key);
      if (saved != null) {
        _rememberTitles(ck, saved);
        return CinemaTitleLoad(titles: saved, fromCache: true, failed: false);
      }
      if (_indexKind == kind && _indexDone && _indexComplete) {
        final List<CinemaTitle> fromIndex = _index
            .where((CinemaTitle t) => t.categoryKey == cat.key)
            .toList(growable: false);
        _rememberTitles(ck, fromIndex);
        return CinemaTitleLoad(titles: fromIndex, fromCache: true, failed: false);
      }
    }

    final _TitleNet net = await _fetchTitlesNetwork(kind, cat);
    if (net.failed) {
      final List<CinemaTitle>? saved = await _titlesFromDisk(kind, cat.key);
      if (saved != null) {
        _rememberTitles(ck, saved);
        return CinemaTitleLoad(titles: saved, fromCache: true, failed: false);
      }
      return const CinemaTitleLoad(titles: <CinemaTitle>[], failed: true);
    }
    if (shouldCacheTitlePage(fetchFailed: false)) {
      _rememberTitles(ck, net.titles);
    }
    return CinemaTitleLoad(titles: net.titles, failed: false);
  }

  void _rememberTitles(String cacheKey, List<CinemaTitle> titles) {
    _titles[cacheKey] = titles;
    while (_titles.length > _kTitleCacheMax) {
      _titles.remove(_titles.keys.first);
    }
  }

  Future<_TitleNet> _fetchTitlesNetwork(
      CinemaKind kind, CinemaCategory cat) async {
    final String action =
        kind == CinemaKind.movie ? 'get_vod_streams' : 'get_series';
    final List<CinemaTitle> all = <CinemaTitle>[];
    bool anyOk = false;
    bool anyFail = false;
    for (final CategoryRef part in cat.parts) {
      final CinemaSource? s = sourceByKey(part.sourceKey);
      if (s == null) {
        anyFail = true;
        continue;
      }
      try {
        final Uint8List? b = await _fetchWithRetry(
          s,
          action,
          <String, String>{'category_id': part.categoryId},
        );
        if (b == null) {
          anyFail = true;
          continue;
        }
        anyOk = true;
        all.addAll(await _mapInIsolate(b, kind, s, cat.key));
      } catch (e) {
        anyFail = true;
        BlackBox.instance.warn('CINEMA', '${s.key} « ${cat.name} » : $e');
      }
    }
    // Échec de TOUTES les parties : on ne mémorise pas une liste vide.
    // (Une catégorie vraiment vide a répondu, anyOk est vrai.)
    if (cat.parts.isNotEmpty && !anyOk && anyFail) {
      return const _TitleNet(titles: <CinemaTitle>[], failed: true);
    }
    return _TitleNet(titles: _dedupe(all), failed: false);
  }

  Future<List<CinemaTitle>> _mapInIsolate(
      Uint8List bytes, CinemaKind kind, CinemaSource s, String fallbackKey,
      {int max = kCinemaCategoryMax}) {
    return compute(
      mapTitlesJob,
      TitlesJob(
        payload: TransferableTypedData.fromList(<Uint8List>[bytes]),
        kind: kind,
        source: s,
        categoryKeyById: _catKeys[kind]?[s.key] ?? const <String, String>{},
        fallbackCategoryKey: fallbackKey,
        max: max,
      ),
    );
  }

  /// Requête Xtream avec UN nouvel essai après 1,5 s : un serveur IPTV
  /// chargé coupe souvent une requête sur deux aux heures de pointe ; sans
  /// ce 2e essai, la catégorie (ou tout un compte) manquait à l'écran.
  Future<Uint8List?> _fetchWithRetry(
      CinemaSource s, String action, Map<String, String>? extra) async {
    try {
      return await _client(s).fetchActionBytes(action, extra: extra);
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      return _client(s).fetchActionBytes(action, extra: extra);
    }
  }

  /// Un même titre sur plusieurs comptes → une seule vignette.
  static List<CinemaTitle> _dedupe(List<CinemaTitle> all) {
    final Set<String> seen = <String>{};
    final List<CinemaTitle> out = <CinemaTitle>[];
    for (final CinemaTitle t in all) {
      if (seen.add('${t.searchKey}|${t.year ?? ''}')) out.add(t);
    }
    return out;
  }

  // ---------------- Index (recherche, récents, compteurs) ----------------

  bool indexReady(CinemaKind kind) => _indexKind == kind && _indexDone;

  /// Lance (une fois) la construction de l'index de [kind] en arrière-plan.
  Future<void> ensureIndex(CinemaKind kind) {
    if (_indexKind == kind && _indexDone) return Future<void>.value();
    if (_indexKind == kind && _indexing != null) return _indexing!;
    // Un seul type indexé à la fois : on libère l'autre.
    _indexKind = kind;
    _index = const <CinemaTitle>[];
    _indexDone = false;
    _indexComplete = false;
    _indexCounts = const <String, int>{};
    _recent = null;
    final Future<void> f = _buildIndex(kind, ++_indexGen);
    _indexing = f;
    return f;
  }

  Future<void> _buildIndex(CinemaKind kind, int gen) async {
    bool stale() => gen != _indexGen || _indexKind != kind;
    // Le disque suffit : on ne retélécharge pas tout le catalogue pour
    // la recherche pendant que le client regarde un film.
    if (await _fillIndexFromDisk(kind)) return;
    final Future<void>? pending = _refreshInFlight[kind];
    if (pending != null) {
      await pending;
      if (stale()) return;
      if (await _fillIndexFromDisk(kind)) return;
    }
    await tuneForRam();
    final List<CinemaCategory> cats = await categories(kind);
    final String action =
        kind == CinemaKind.movie ? 'get_vod_streams' : 'get_series';
    final List<CinemaTitle> acc = <CinemaTitle>[];
    final Set<String> seen = <String>{};
    bool complete = true; // devient faux au 1er trou (plafond ou échec)
    void add(List<CinemaTitle> list, {bool truncated = false}) {
      if (truncated) complete = false;
      for (final CinemaTitle t in list) {
        if (acc.length >= _indexMax) {
          complete = false;
          return;
        }
        if (seen.add('${t.searchKey}|${t.year ?? ''}')) acc.add(t);
      }
    }

    void publish() {
      if (stale()) return;
      _index = List<CinemaTitle>.unmodifiable(acc);
      _recent = null;
      indexVersion.value++;
    }

    final Stopwatch sw = Stopwatch()..start();
    for (final CinemaSource s in _sources) {
      if (stale()) break;
      if (acc.length >= _indexMax) {
        complete = false;
        break;
      }
      // 1) Tout le catalogue d'un bloc (rapide) si la réponse reste légère.
      //    ÉCHEC (délai dépassé sur box / connexion lente, coupure…) → on NE
      //    SAUTE PLUS le compte : on passe à l'étape 2. Avant, un seul
      //    délai dépassé retirait TOUT le compte de l'index.
      Uint8List? whole;
      try {
        whole = await _client(s)
            .fetchActionBytes(action, softMax: kCinemaSingleShotBytes);
      } catch (e) {
        BlackBox.instance.warn(
            'CINEMA', 'index ${s.key} (bloc) : $e → catégorie par catégorie');
        whole = null;
      }
      if (whole != null) {
        try {
          final int room = _indexMax - acc.length;
          final List<CinemaTitle> got =
              await _mapInIsolate(whole, kind, s, '', max: room);
          add(got, truncated: got.length >= room);
          whole = null; // libère le JSON brut au plus vite (mémoire)
          publish();
          continue;
        } catch (e) {
          BlackBox.instance.warn('CINEMA', 'index ${s.key} (lecture) : $e');
        }
      }
      // 2) Catégorie par catégorie (léger, progressif), avec un 2e essai.
      int n = 0;
      for (final CinemaCategory c in cats) {
        if (stale()) break;
        if (acc.length >= _indexMax) {
          complete = false;
          break;
        }
        for (final CategoryRef part in c.parts) {
          if (part.sourceKey != s.key) continue;
          try {
            final Uint8List? b = await _fetchWithRetry(
              s,
              action,
              <String, String>{'category_id': part.categoryId},
            );
            if (b != null) add(await _mapInIsolate(b, kind, s, c.key));
          } catch (e) {
            complete = false; // cette catégorie devra être relue en direct
            BlackBox.instance.warn('CINEMA', 'index « ${c.name} » : $e');
          }
        }
        if (++n % 8 == 0) publish();
      }
      publish();
    }
    if (stale()) return;
    final Map<String, int> counts = <String, int>{};
    for (final CinemaTitle t in acc) {
      counts[t.categoryKey] = (counts[t.categoryKey] ?? 0) + 1;
    }
    _indexCounts = counts;
    _indexComplete = complete;
    _indexDone = true;
    publish();
    BlackBox.instance.info(
        'CINEMA',
        'index ${kind.name} : ${acc.length} titres en ${sw.elapsedMilliseconds} ms'
            '${complete ? '' : ' (partiel → catégories lues en direct)'}');
  }

  /// Nombre de titres d'une catégorie (null tant que l'index n'est pas fini).
  /// Pas de compteur si l'index est partiel : mieux vaut aucun chiffre
  /// qu'un chiffre faux (« 0 » sur une catégorie pleine).
  int? countFor(CinemaKind kind, String catKey) =>
      indexReady(kind) && _indexComplete ? (_indexCounts[catKey] ?? 0) : null;

  /// « Récemment ajoutés » (depuis l'index, du plus récent au plus ancien).
  List<CinemaTitle> recent(CinemaKind kind,
      {Set<String>? allowedCats, int max = 80}) {
    if (_indexKind != kind || _index.isEmpty) return const <CinemaTitle>[];
    final List<CinemaTitle> sorted = _recent ??= (List<CinemaTitle>.of(
        _index.where((CinemaTitle t) => t.addedAt > 0))
      ..sort((CinemaTitle a, CinemaTitle b) => b.addedAt.compareTo(a.addedAt)));
    final Iterable<CinemaTitle> it = allowedCats == null
        ? sorted
        : sorted.where((CinemaTitle t) => allowedCats.contains(t.categoryKey));
    return it.take(max).toList(growable: false);
  }

  /// Recherche (tous les mots de la requête doivent être dans le nom).
  List<CinemaTitle> search(CinemaKind kind, String query,
      {Set<String>? allowedCats, int max = 80}) {
    final List<String> words = CinemaLanguage.searchKey(query)
        .split(' ')
        .where((String w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return const <CinemaTitle>[];
    Iterable<CinemaTitle> pool =
        _indexKind == kind ? _index : const <CinemaTitle>[];
    if (pool.isEmpty) {
      // Index pas encore là : on cherche dans les catégories déjà ouvertes.
      pool = <CinemaTitle>[
        for (final MapEntry<String, List<CinemaTitle>> e in _titles.entries)
          if (e.key.startsWith('${kind.name}|')) ...e.value,
      ];
    }
    final List<CinemaTitle> out = <CinemaTitle>[];
    for (final CinemaTitle t in pool) {
      if (allowedCats != null && !allowedCats.contains(t.categoryKey)) continue;
      bool ok = true;
      for (final String w in words) {
        if (!t.searchKey.contains(w)) {
          ok = false;
          break;
        }
      }
      if (ok) {
        out.add(t);
        if (out.length >= max) break;
      }
    }
    return out;
  }

  // ---------------- Fiches détaillées ----------------

  Future<CinemaDetails> movieDetails(CinemaTitle t) async {
    final CinemaDetails? hit = _details[t.id];
    if (hit != null) return hit;
    final CinemaSource? s = sourceByKey(t.sourceKey);
    if (s == null) return CinemaDetails.empty;
    try {
      final Uint8List? b = await _client(s).fetchActionBytes(
        'get_vod_info',
        extra: <String, String>{'vod_id': t.remoteId},
      );
      final CinemaDetails d =
          b == null ? CinemaDetails.empty : parseVodInfo(decodeJsonBytes(b));
      _details[t.id] = d;
      while (_details.length > 200) {
        _details.remove(_details.keys.first);
      }
      return d;
    } catch (e) {
      BlackBox.instance.warn('CINEMA', 'fiche film ${t.id} : $e');
      return CinemaDetails.empty;
    }
  }

  Future<SeriesDetails?> seriesDetails(CinemaTitle t) async {
    final SeriesDetails? hit = _series[t.id];
    if (hit != null) return hit;
    final CinemaSource? s = sourceByKey(t.sourceKey) ??
        (await sources())
            .where((CinemaSource x) => x.key == t.sourceKey)
            .firstOrNull;
    if (s == null) return null;
    try {
      final Uint8List? b = await _client(s).fetchActionBytes(
        'get_series_info',
        extra: <String, String>{'series_id': t.remoteId},
      );
      if (b == null) return null;
      final SeriesDetails d = await compute(
        _seriesInIsolate,
        (
          payload: TransferableTypedData.fromList(<Uint8List>[b]),
          source: s,
          seriesId: t.id,
          name: t.name,
        ),
      );
      _series[t.id] = d;
      while (_series.length > 20) {
        _series.remove(_series.keys.first);
      }
      return d;
    } catch (e) {
      BlackBox.instance.warn('CINEMA', 'fiche série ${t.id} : $e');
      return null;
    }
  }

  /// Vide la MÉMOIRE (comptes changés, ou libération).
  ///
  /// Le catalogue sur le disque n'est pas effacé : un redémarrage ou un
  /// changement de compte ne doit pas faire disparaître les films déjà
  /// enregistrés. Le téléchargement en cours s'arrête ([_catalogGen]) et
  /// ne publie pas un morceau.
  void clear() {
    for (final XtreamClient c in _clients.values) {
      c.dispose();
    }
    _clients.clear();
    _cats.clear();
    _catKeys.clear();
    _titles.clear();
    _details.clear();
    _series.clear();
    _indexKind = null;
    _indexGen++;
    _index = const <CinemaTitle>[];
    _indexDone = false;
    _indexComplete = false;
    _indexing = null;
    _loadedAt = null;
    _indexCounts = const <String, int>{};
    _recent = null;
    _updatedAt.clear();
    _persisted.clear();
    _refreshInFlight.clear();
    _refreshStartedAt = null;
    _catalogGen++;
    indexVersion.value++;
  }

  /// Libère la mémoire lourde en quittant le Cinéma (l'index sera rebâti à
  /// la prochaine ouverture ; les catégories restent pour un retour rapide).
  void trim() {
    _titles.clear();
    _indexKind = null;
    _indexGen++;
    _index = const <CinemaTitle>[];
    _indexDone = false;
    _indexing = null;
    _indexCounts = const <String, int>{};
    _recent = null;
  }

  // ---------------- Cache disque ----------------

  Future<CatalogDisk?> _openDisk() async {
    if (_disk != null) return _disk;
    try {
      final Directory docs = await getApplicationDocumentsDirectory();
      _disk = CatalogDisk(Directory(p.join(docs.path, 'zuno_catalog')));
      return _disk;
    } catch (e) {
      BlackBox.instance.warn('CINEMA', 'cache catalogue indisponible : $e');
      return null;
    }
  }

  Future<CatalogHeader?> _readDiskHeader(CinemaKind kind) async {
    final String? folder = _folderSig;
    final CatalogDisk? disk = await _openDisk();
    if (folder == null || disk == null) return null;
    try {
      return await disk.readHeader(folder, kind);
    } catch (e) {
      BlackBox.instance.warn('CINEMA', 'lecture cache ${kind.name} : $e');
      return null;
    }
  }

  Future<List<CinemaTitle>?> _titlesFromDisk(
      CinemaKind kind, String categoryKey) async {
    final String? folder = _folderSig;
    final CatalogDisk? disk = await _openDisk();
    if (folder == null || disk == null) return null;
    try {
      final List<CatalogTitleRecord>? rows =
          await disk.readTitles(folder, kind, categoryKey);
      if (rows == null) return null;
      return <CinemaTitle>[
        for (final CatalogTitleRecord row in rows)
          row.toCinemaTitle(sourceByKey(row.sourceKey)),
      ];
    } catch (e) {
      BlackBox.instance.warn('CINEMA', 'titres en cache « $categoryKey » : $e');
      return null;
    }
  }

  void _installHeader(CinemaKind kind, CatalogHeader header) {
    final List<CinemaCategory> cats = <CinemaCategory>[
      for (final CatalogCategoryRecord record in header.categories)
        record.toCinemaCategory(),
    ];
    _cats[kind] = cats;
    final Map<String, Map<String, String>> keys =
        <String, Map<String, String>>{};
    for (final CinemaCategory category in cats) {
      for (final CategoryRef part in category.parts) {
        keys.putIfAbsent(
                part.sourceKey, () => <String, String>{})[part.categoryId] =
            category.key;
      }
    }
    _catKeys[kind] = keys;
    _loadedAt = header.updatedAt;
    _updatedAt[kind] = header.updatedAt;
  }

  /// Films déjà sur la box, pour l'écran mobile si le serveur ne répond pas.
  /// Liste vide si le cache est incomplet : on ne montre pas un morceau.
  Future<List<VodMovie>> cachedVodMovies() async {
    final String? folder = _folderSig;
    if (folder == null) {
      await sources();
    }
    final String? sig = _folderSig;
    final CatalogDisk? disk = await _openDisk();
    if (sig == null || disk == null) return const <VodMovie>[];
    final CatalogHeader? header = await disk.readHeader(sig, CinemaKind.movie);
    if (header == null || !header.complete) return const <VodMovie>[];
    final Map<String, String> names = <String, String>{
      for (final CatalogCategoryRecord category in header.categories)
        category.key: category.name,
    };
    final List<VodMovie> out = <VodMovie>[];
    for (final CatalogCategoryRecord category in header.categories) {
      final List<CatalogTitleRecord>? rows =
          await disk.readTitles(sig, CinemaKind.movie, category.key);
      if (rows == null) return const <VodMovie>[];
      for (final CatalogTitleRecord row in rows) {
        if (row.kind != CinemaKind.movie) continue;
        final CinemaTitle title = row.toCinemaTitle(sourceByKey(row.sourceKey));
        final String? url = title.streamUrl;
        if (url == null || url.isEmpty) continue;
        out.add(VodMovie(
          id: title.id,
          name: title.name,
          category: names[title.categoryKey] ?? title.categoryKey,
          streamUrl: url,
          containerExt: title.containerExt,
          posterUrl: title.posterUrl,
          rating: title.rating?.toString(),
          year: title.year,
        ));
      }
    }
    return out;
  }

  Future<void> _refreshCatalog(CinemaKind kind) {
    final Future<void>? current = _refreshInFlight[kind];
    if (current != null) return current;
    final int gen = _catalogGen;
    final String? folder = _folderSig;
    final Future<void> run = _refreshBody(kind, gen, folder);
    _refreshInFlight[kind] = run;
    return run.whenComplete(() {
      if (identical(_refreshInFlight[kind], run)) _refreshInFlight.remove(kind);
    });
  }

  Future<void> _refreshBody(CinemaKind kind, int gen, String? folder) async {
    if (folder == null || gen != _catalogGen) return;
    final CatalogDisk? disk = await _openDisk();
    if (disk == null || gen != _catalogGen) return;
    _wantsRefresh = false;
    _refreshStartedAt = DateTime.now();
    try {
      final CatalogRefreshResult result = await _refresher.run(
        disk: disk,
        signature: folder,
        kind: kind,
        fetchCategories: () => _downloadCategoryRecords(kind),
        fetchTitles: (CatalogCategoryRecord category) =>
            _downloadTitleRecords(kind, category),
        playbackBusy: () => TvActivity.isBusy,
        sleep: (Duration delay) => Future<void>.delayed(delay),
        jitterPermille: () => _jitter.nextInt(1001),
        cancelled: () => gen != _catalogGen,
      );
      if (gen != _catalogGen) return;
      if (result.status != CatalogRefreshStatus.published) return;
      final CatalogHeader? header = await disk.readHeader(folder, kind);
      if (header == null || gen != _catalogGen) return;
      _installHeader(kind, header);
      _persisted[kind] = true;
      _titles.removeWhere(
          (String key, List<CinemaTitle> _) => key.startsWith('${kind.name}|'));
      await disk.pruneSignatures(folder);
      if (_indexKind == null || _indexKind == kind) {
        await _fillIndexFromDisk(kind);
      }
      BlackBox.instance.info('CINEMA',
          'catalogue ${kind.name} enregistré : ${header.titleCount} titres');
    } catch (e) {
      BlackBox.instance
          .warn('CINEMA', 'catalogue ${kind.name} non enregistré : $e');
    }
  }

  Future<bool> _fillIndexFromDisk(CinemaKind kind) async {
    final int gen = _indexGen;
    if (_indexKind != null && _indexKind != kind) return false;
    final String? folder = _folderSig;
    final CatalogDisk? disk = await _openDisk();
    if (folder == null || disk == null) return false;
    final CatalogHeader? header = await disk.readHeader(folder, kind);
    if (header == null || !header.complete || header.titleCount <= 0) {
      return false;
    }
    await tuneForRam();
    if (gen != _indexGen) return false;
    final List<CinemaTitle> acc = <CinemaTitle>[];
    final Set<String> seen = <String>{};
    bool hitCap = false;
    for (final CatalogCategoryRecord category in header.categories) {
      if (gen != _indexGen) return false;
      final List<CatalogTitleRecord>? rows =
          await disk.readTitles(folder, kind, category.key);
      if (rows == null) return false;
      for (final CatalogTitleRecord row in rows) {
        if (acc.length >= _indexMax) {
          hitCap = true;
          break;
        }
        final CinemaTitle title = row.toCinemaTitle(sourceByKey(row.sourceKey));
        if (seen.add('${title.searchKey}|${title.year ?? ''}')) acc.add(title);
      }
      if (hitCap) break;
    }
    if (gen != _indexGen || acc.isEmpty) return false;
    final Map<String, int> counts = <String, int>{};
    for (final CinemaTitle title in acc) {
      counts[title.categoryKey] = (counts[title.categoryKey] ?? 0) + 1;
    }
    _indexKind = kind;
    _index = List<CinemaTitle>.unmodifiable(acc);
    _indexCounts = counts;
    _indexComplete = !hitCap;
    _indexDone = true;
    _recent = null;
    indexVersion.value++;
    return true;
  }

  Future<_CatFetch> _fetchMerged(CinemaKind kind) async {
    final List<CinemaSource> srcs = _sources;
    final String action = kind == CinemaKind.movie
        ? 'get_vod_categories'
        : 'get_series_categories';
    bool anySuccess = false;
    bool anyFailure = false;
    final List<List<({String id, String name})>> perSource =
        await Future.wait(<Future<List<({String id, String name})>>>[
      for (final CinemaSource s in srcs)
        () async {
          try {
            final Uint8List? b = await _client(s).fetchActionBytes(action);
            if (b == null) {
              anyFailure = true;
              return const <({String id, String name})>[];
            }
            anySuccess = true;
            return parseCategories(decodeJsonBytes(b));
          } catch (e) {
            anyFailure = true;
            BlackBox.instance.warn('CINEMA', '${s.key} $action : $e');
            return const <({String id, String name})>[];
          }
        }(),
    ]);

    final LinkedHashMap<String, _CatBuilder> merged =
        LinkedHashMap<String, _CatBuilder>();
    final Map<String, Map<String, String>> keys =
        <String, Map<String, String>>{};
    for (int i = 0; i < srcs.length; i++) {
      final CinemaSource s = srcs[i];
      final Map<String, String> byId =
          keys.putIfAbsent(s.key, () => <String, String>{});
      for (final ({String id, String name}) c in perSource[i]) {
        final String pretty = ChannelClassifier.prettifyCategory(c.name);
        final String key = CinemaLanguage.searchKey(pretty);
        byId[c.id] = key;
        merged
            .putIfAbsent(key, () => _CatBuilder(pretty))
            .parts
            .add(CategoryRef(s.key, c.id));
      }
    }
    final List<CinemaCategory> out = <CinemaCategory>[
      for (final MapEntry<String, _CatBuilder> e in merged.entries)
        CinemaCategory(
          key: e.key,
          name: e.value.name,
          parts: List<CategoryRef>.unmodifiable(e.value.parts),
          languageKey: CinemaLanguage.detect(e.value.name),
          isAdult: isAdultCategory(e.value.name),
          isKids: isKidsCategory(e.value.name),
        ),
    ];
    return _CatFetch(
      categories: out,
      keys: keys,
      anySuccess: anySuccess,
      anyFailure: anyFailure,
    );
  }

  Future<CatalogFetchResult<List<CatalogCategoryRecord>>>
      _downloadCategoryRecords(CinemaKind kind) async {
    try {
      final _CatFetch fetched = await _fetchMerged(kind);
      if (fetched.anyFailure || !fetched.anySuccess) {
        return const CatalogFetchResult<List<CatalogCategoryRecord>>.fail();
      }
      return CatalogFetchResult<
          List<CatalogCategoryRecord>>.ok(<CatalogCategoryRecord>[
        for (final CinemaCategory category in fetched.categories)
          CatalogCategoryRecord(
            key: category.key,
            name: category.name,
            languageKey: category.languageKey,
            isAdult: category.isAdult,
            isKids: category.isKids,
            fileId: '',
            parts: <CatalogPartRecord>[
              for (final CategoryRef part in category.parts)
                CatalogPartRecord(part.sourceKey, part.categoryId),
            ],
          ),
      ]);
    } catch (e) {
      BlackBox.instance.warn('CINEMA', 'catégories catalogue : $e');
      return const CatalogFetchResult<List<CatalogCategoryRecord>>.fail();
    }
  }

  Future<CatalogFetchResult<List<CatalogTitleRecord>>> _downloadTitleRecords(
    CinemaKind kind,
    CatalogCategoryRecord category,
  ) async {
    final String action =
        kind == CinemaKind.movie ? 'get_vod_streams' : 'get_series';
    if (category.parts.isEmpty) {
      return const CatalogFetchResult<List<CatalogTitleRecord>>.ok(
          <CatalogTitleRecord>[]);
    }
    final List<CinemaTitle> all = <CinemaTitle>[];
    for (final CatalogPartRecord part in category.parts) {
      final CinemaSource? source = sourceByKey(part.sourceKey);
      if (source == null) {
        return const CatalogFetchResult<List<CatalogTitleRecord>>.fail();
      }
      try {
        final Uint8List? bytes = await _client(source).fetchActionBytes(
          action,
          extra: <String, String>{'category_id': part.categoryId},
        );
        if (bytes == null) {
          return const CatalogFetchResult<List<CatalogTitleRecord>>.fail();
        }
        all.addAll(await _mapInIsolate(bytes, kind, source, category.key));
      } catch (e) {
        BlackBox.instance.warn('CINEMA', 'morceau « ${category.name} » : $e');
        return const CatalogFetchResult<List<CatalogTitleRecord>>.fail();
      }
    }
    return CatalogFetchResult<List<CatalogTitleRecord>>.ok(<CatalogTitleRecord>[
      for (final CinemaTitle title in _dedupe(all))
        CatalogTitleRecord.fromCinemaTitle(title),
    ]);
  }
}

class _CatBuilder {
  _CatBuilder(this.name);
  final String name;
  final List<CategoryRef> parts = <CategoryRef>[];
}

/// Résultat d'un chargement de catégorie pour l'écran.
class CinemaTitleLoad {
  const CinemaTitleLoad({
    required this.titles,
    required this.failed,
    this.fromCache = false,
  });

  final List<CinemaTitle> titles;

  /// Vrai seulement si on n'a rien à montrer ET que le serveur n'a pas répondu.
  final bool failed;

  /// Vrai si la liste vient de la mémoire ou du disque.
  final bool fromCache;
}

class _TitleNet {
  const _TitleNet({required this.titles, required this.failed});
  final List<CinemaTitle> titles;
  final bool failed;
}

class _CatFetch {
  const _CatFetch({
    required this.categories,
    required this.keys,
    required this.anySuccess,
    required this.anyFailure,
  });

  final List<CinemaCategory> categories;
  final Map<String, Map<String, String>> keys;
  final bool anySuccess;
  final bool anyFailure;
}

/// Point d'entrée isolate pour `get_series_info` (réponse parfois lourde :
/// des centaines d'épisodes avec leurs résumés).
SeriesDetails _seriesInIsolate(
    ({
      TransferableTypedData payload,
      CinemaSource source,
      String seriesId,
      String name
    }) job) {
  return parseSeriesInfo(
    decodeJsonBytes(job.payload.materialize().asUint8List()),
    source: job.source,
    seriesId: job.seriesId,
    seriesName: job.name,
  );
}

// ---------------------------------------------------------
//  Classement « adulte » / « enfants » d'une catégorie
// ---------------------------------------------------------

/// Mots propres aux catalogues VOD enfants (en plus de ceux du Direct).
const List<String> _kKidsVodWords = <String>[
  'kids',
  'enfant',
  'jeunesse',
  'animation',
  'anime',
  'dessin anime',
  'dessins animes',
  'cartoon',
  'famille',
  'family',
  'disney',
  'pixar',
  'dreamworks',
  'infantil',
  'kinder',
  'bambini',
  'cocuk',
  'детск',
  '儿童',
  '动画',
  '動畫',
  'أطفال',
  'كرتون',
  'बच्चों',
];

bool isAdultCategory(String name) =>
    ChannelClassifier.classifyGenre('', name) == ChannelGenre.adult;

bool isKidsCategory(String name) {
  if (isAdultCategory(name)) return false;
  if (ChannelClassifier.classifyGenre('', name) == ChannelGenre.kids)
    return true;
  final String k = CinemaLanguage.searchKey(name);
  for (final String w in _kKidsVodWords) {
    if (k.contains(w)) return true;
  }
  return false;
}
