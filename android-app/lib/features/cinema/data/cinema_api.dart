// =========================================================
//  cinema_api.dart — D'où viennent les films et les séries d'un compte
// =========================================================
//  Le module Cinéma parle « Xtream » (`get_vod_categories`, `get_vod_streams`,
//  `get_series`, `get_series_info`…). Trois façons de lui répondre :
//
//    • [XtreamCinemaApi]    le serveur du fournisseur (comme avant) ;
//    • [M3uVodApi]          les films et séries LUS DANS UN FICHIER M3U, rangés
//                           par m3u_vod_store.dart avec les mêmes réponses ;
//    • [FallbackCinemaApi]  un compte Xtream dont l'API n'a pas de films : on
//                           essaie le serveur, et seulement s'il répond « 404 »
//                           (ou une liste vide) on lit le M3U du même compte.
//
//  Un compte dont l'API fonctionne n'est donc JAMAIS touché : aucun
//  téléchargement de M3U, aucun changement de comportement.
// =========================================================
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/blackbox/black_box.dart';
import '../../playlists/data/m3u_fetcher.dart';
import '../../playlists/data/playlist_import_limits.dart';
import '../../playlists/data/xtream_client.dart';
import 'cinema_parsers.dart';
import 'm3u_vod_store.dart';

/// Au-delà de cet âge, le M3U est relu en arrière-plan (nouveaux films).
const Duration kM3uVodMaxAge = Duration(hours: 12);

/// Bouton « Actualiser » : pas de nouvelle lecture du M3U avant cet âge
/// (un double appui ne retélécharge pas 50 Mo).
const Duration kM3uVodMinGap = Duration(minutes: 2);

/// Un compte non plus sollicité : l'API sans films n'est re-testée qu'après ce délai.
const Duration kM3uVodReprobe = Duration(minutes: 30);

/// Ce que le module Cinéma demande à un compte.
abstract interface class CinemaApi {
  /// Réponse (octets JSON, format Xtream) de [action] ; `null` = « trop gros
  /// pour un bloc, passe par catégorie » ou « rien pour cet appel ».
  Future<Uint8List?> fetchActionBytes(
    String action, {
    Map<String, String>? extra,
    int? softMax,
  });

  void dispose();
}

/// Le serveur Xtream du fournisseur.
class XtreamCinemaApi implements CinemaApi {
  XtreamCinemaApi(this.client);
  final XtreamClient client;

  @override
  Future<Uint8List?> fetchActionBytes(
    String action, {
    Map<String, String>? extra,
    int? softMax,
  }) =>
      client.fetchActionBytes(action, extra: extra, softMax: softMax);

  @override
  void dispose() => client.dispose();
}

/// Films et séries d'un fichier M3U (lien, fichier local, ou `get.php`).
class M3uVodApi implements CinemaApi {
  M3uVodApi({
    required this.sourceKey,
    required this.m3uUrl,
    required this.signature,
    this.httpClient,
    this.forceRefresh,
  });

  /// `p<id de la liste>`, comme [CinemaSource.key].
  final String sourceKey;

  /// Lien http(s) ou `file:` du M3U.
  final String m3uUrl;

  /// Empreinte de ce qui rend le dossier valide (le lien, donc les
  /// identifiants) : si elle change, le dossier est reconstruit.
  final String signature;
  final http.Client? httpClient;

  /// Vrai pendant le bouton « Actualiser » : on relit le M3U pour de bon.
  final bool Function()? forceRefresh;

  /// Test : dossier racine imposé (sinon « documents/zuno_m3u_vod »).
  @visibleForTesting
  static Directory? rootForTesting;

  /// Prévenu quand un dossier vient d'être refait EN ARRIÈRE-PLAN : le dépôt
  /// demande alors un rafraîchissement du catalogue.
  static void Function(String sourceKey)? onRebuilt;

  static final Map<String, Future<M3uVodSummary>> _building =
      <String, Future<M3uVodSummary>>{};

  /// Source → signature pour laquelle le livre d'adresses a déjà été regardé.
  static final Map<String, String> _checked = <String, String>{};

  static Future<Directory> _root() async {
    final Directory? forced = rootForTesting;
    if (forced != null) return forced;
    final Directory docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'zuno_m3u_vod'));
  }

  static Future<Directory> dirFor(String sourceKey) async =>
      Directory(p.join((await _root()).path, sourceKey));

  /// Met en mémoire les adresses des films si un dossier valide existe. Appelé
  /// à chaque lecture des comptes : après le premier passage, aucun accès disque.
  static Future<void> preloadBook({
    required String sourceKey,
    required String signature,
  }) async {
    if (_checked[sourceKey] == signature) return;
    final M3uVodStore store = M3uVodStore(await dirFor(sourceKey));
    final M3uVodMeta? meta = await store.readMeta();
    if (meta != null && meta.signature == signature) {
      M3uUrlBook.install(sourceKey, await store.readUrlBook());
    } else {
      M3uUrlBook.remove(sourceKey);
    }
    _checked[sourceKey] = signature;
  }

  /// Efface les dossiers des listes SUPPRIMÉES (pas celles seulement
  /// masquées : un changement de profil ne doit pas tout retélécharger).
  static Future<void> prune(Set<String> existingKeys) async {
    try {
      final Directory root = await _root();
      if (!await root.exists()) return;
      await for (final FileSystemEntity e in root.list()) {
        String name = p.basename(e.path);
        for (final String suffix in <String>['.m3u.tmp', '.tmp']) {
          if (name.endsWith(suffix)) {
            name = name.substring(0, name.length - suffix.length);
            break;
          }
        }
        if (existingKeys.contains(name) || _building.containsKey(name)) continue;
        await e.delete(recursive: true);
        M3uUrlBook.remove(name);
        _checked.remove(name);
      }
    } catch (_) {
      // Nettoyage de confort : sans conséquence s'il échoue.
    }
  }

  /// Test : attend les fabrications en cours (appelé par
  /// CinemaRepository.shutdownForTesting).
  static Future<void> settleForTesting() async {
    await Future.wait(<Future<void>>[
      for (final Future<M3uVodSummary> f in _building.values.toList())
        f.then((M3uVodSummary _) {}, onError: (Object _) {}),
    ]);
  }

  /// Test : oublie l'état en mémoire.
  @visibleForTesting
  static void resetForTesting() {
    _building.clear();
    _checked.clear();
    M3uUrlBook.clearAll();
    onRebuilt = null;
    rootForTesting = null;
  }

  @override
  Future<Uint8List?> fetchActionBytes(
    String action, {
    Map<String, String>? extra,
    int? softMax,
  }) async {
    final bool movies = action.contains('vod');
    switch (action) {
      case 'get_vod_categories':
      case 'get_series_categories':
        return (await _store()).categories(movies: movies);
      case 'get_vod_streams':
      case 'get_series':
        final String? category = extra?['category_id'];
        // Catalogue entier : « trop gros, lis par catégorie ».
        if (category == null) return null;
        return (await _store()).titles(movies: movies, categoryId: category);
      case 'get_series_info':
        final String? id = extra?['series_id'];
        return id == null ? null : (await _store()).seriesInfo(id);
      default:
        // get_vod_info : un M3U n'a pas de fiche détaillée (résumé, acteurs…).
        return null;
    }
  }

  @override
  void dispose() {}

  /// Dossier prêt à lire. Absent ou d'un autre compte : on le fabrique (le
  /// premier appel attend, 10 à 90 s selon la taille du M3U). Trop vieux : on
  /// répond avec l'ancien et on le refait en arrière-plan.
  Future<M3uVodStore> _store() async {
    final Directory dir = await dirFor(sourceKey);
    final M3uVodStore store = M3uVodStore(dir);
    final M3uVodMeta? meta = await store.readMeta();
    if (meta != null && meta.signature == signature) {
      await preloadBook(sourceKey: sourceKey, signature: signature);
      final Duration age = meta.age(DateTime.now());
      final bool manual = forceRefresh?.call() ?? false;
      if (manual && age > kM3uVodMinGap) {
        // Bouton « Actualiser » : on attend le fournisseur. Un échec remonte
        // (le catalogue affiché n'est pas touché et l'écran dit que
        // l'actualisation n'a pas eu lieu), comme pour l'API Xtream.
        final M3uVodSummary s = await _rebuild(dir);
        if (!s.ok) throw Exception(s.error);
      } else if (age > kM3uVodMaxAge) {
        unawaited(_rebuild(dir).then((M3uVodSummary s) {
          if (s.ok) onRebuilt?.call(sourceKey);
        }));
      }
      return M3uVodStore(dir);
    }
    final M3uVodSummary s = await _rebuild(dir);
    if (!s.ok) throw Exception(s.error);
    return M3uVodStore(dir);
  }

  /// Une seule fabrication à la fois par source (deux écrans, deux appels :
  /// un seul téléchargement).
  Future<M3uVodSummary> _rebuild(Directory dir) {
    return _building.putIfAbsent(sourceKey, () {
      // Bloc { } et non « => » : `remove` rend le Future lui-même, et un
      // `whenComplete` qui rend son propre Future s'attend pour toujours.
      return _build(dir).whenComplete(() {
        _building.remove(sourceKey);
      });
    });
  }

  Future<M3uVodSummary> _build(Directory dir) async {
    final Stopwatch clock = Stopwatch()..start();
    File? temp;
    try {
      final String path;
      if (m3uUrl.trim().toLowerCase().startsWith('file:')) {
        path = Uri.parse(m3uUrl.trim()).toFilePath();
      } else {
        await dir.parent.create(recursive: true);
        temp = File('${dir.path}.m3u.tmp');
        await M3uFetcher.fetchToFile(m3uUrl.trim(), temp, httpClient: httpClient);
        path = temp.path;
      }
      final M3uVodSummary s = await compute(
        buildM3uVodStore,
        M3uVodBuildJob(m3uPath: path, outPath: dir.path, signature: signature),
      );
      if (!s.ok) {
        BlackBox.instance.warn('CINEMA', 'M3U $sourceKey : lecture impossible : ${s.error}');
        return s;
      }
      _checked.remove(sourceKey);
      await preloadBook(sourceKey: sourceKey, signature: signature);
      if (s.isEmpty) {
        BlackBox.instance.info('CINEMA',
            'M3U $sourceKey : aucun film ni série dans ce fichier (${s.urlsSeen} adresses lues)');
      } else {
        BlackBox.instance.info(
            'CINEMA',
            'M3U $sourceKey : ${s.movies} films, ${s.series} séries (${s.episodes} épisodes), '
                '${s.movieCategories + s.seriesCategories} catégories, ${s.urlsSeen} adresses lues '
                'en ${clock.elapsed.inSeconds} s${s.truncated ? ' (coupé au plafond)' : ''}');
      }
      return s;
    } on PlaylistImportTooLarge catch (e) {
      BlackBox.instance.warn('CINEMA', 'M3U $sourceKey : ${e.message}');
      return M3uVodSummary(error: e.message);
    } catch (e) {
      BlackBox.instance.warn('CINEMA', 'M3U $sourceKey : téléchargement impossible : $e');
      return M3uVodSummary(error: e.toString());
    } finally {
      try {
        if (temp != null && await temp.exists()) await temp.delete();
      } catch (_) {}
    }
  }
}

/// Ce que l'API a répondu à « liste des catégories ».
enum _Reply {
  /// Au moins une catégorie.
  items,

  /// Une vraie liste, vide : le compte n'a pas de films / séries. On le croit
  /// (sinon un abonnement de directs téléchargerait un M3U à chaque ouverture).
  empty,

  /// Ni liste ni JSON (page web, objet « infos du compte »…) : le serveur ne
  /// connaît pas cette demande.
  unusable,
}

/// Compte Xtream : l'API d'abord ; le M3U du même compte SEULEMENT si le
/// serveur ne connaît pas la demande (404, 405, 501, réponse qui n'est pas une
/// liste) — ou si la personne touche « Actualiser » alors que la liste est vide.
class FallbackCinemaApi implements CinemaApi {
  FallbackCinemaApi({
    required this.primary,
    required this.fallback,
    this.forceRefresh,
  });

  final CinemaApi primary;
  final M3uVodApi fallback;

  /// Vrai pendant le bouton « Actualiser ».
  final bool Function()? forceRefresh;

  /// films? → l'API a-t-elle des catégories ? (absent = pas encore testé)
  final Map<bool, bool> _apiOk = <bool, bool>{};
  final Map<bool, DateTime> _probedAt = <bool, DateTime>{};

  @override
  Future<Uint8List?> fetchActionBytes(
    String action, {
    Map<String, String>? extra,
    int? softMax,
  }) {
    final bool movies = action.contains('vod');
    if (action.endsWith('_categories')) return _categories(action, movies);

    // Un identifiant qui n'est pas un numéro du fournisseur vient du M3U.
    final String? id = extra?['category_id'] ?? extra?['series_id'];
    if (m3uVodIsOwnId(id)) {
      return fallback.fetchActionBytes(action, extra: extra, softMax: softMax);
    }
    if (_apiOk[movies] == false) {
      // L'API n'a pas de films : le catalogue entier et les fiches de film
      // n'existent pas ailleurs → « par catégorie » / « pas de fiche ».
      return Future<Uint8List?>.value(null);
    }
    return primary.fetchActionBytes(action, extra: extra, softMax: softMax);
  }

  Future<Uint8List?> _categories(String action, bool movies) async {
    final DateTime? probed = _probedAt[movies];
    if (_apiOk[movies] == false &&
        probed != null &&
        DateTime.now().difference(probed) < kM3uVodReprobe) {
      return fallback.fetchActionBytes(action);
    }
    Uint8List? bytes;
    Object? error;
    try {
      bytes = await primary.fetchActionBytes(action);
    } catch (e) {
      error = e;
    }
    final _Reply reply = bytes == null ? _Reply.unusable : _reply(bytes);
    if (reply == _Reply.items) {
      _apiOk[movies] = true;
      _probedAt.remove(movies);
      return bytes;
    }
    // Liste vide : le compte n'a pas de films. On ne télécharge pas un M3U
    // pour le vérifier, sauf si la personne vient de demander « Actualiser ».
    if (reply == _Reply.empty && !(forceRefresh?.call() ?? false)) {
      _apiOk[movies] = true;
      return bytes;
    }
    // Panne passagère (réseau, délai, 5xx) : comportement d'avant, on ne
    // télécharge pas un M3U pour ça.
    if (error != null && !_noVodOnServer(error)) throw error;
    _apiOk[movies] = false;
    _probedAt[movies] = DateTime.now();
    BlackBox.instance.info('CINEMA',
        'le serveur n\'a pas ${movies ? 'de films' : 'de séries'} via son API → lecture du M3U du compte');
    return fallback.fetchActionBytes(action);
  }

  static _Reply _reply(Uint8List bytes) {
    try {
      final dynamic decoded = decodeJsonBytes(bytes);
      if (parseCategories(decoded).isNotEmpty) return _Reply.items;
      final bool isList = decoded is List ||
          (decoded is Map && decoded['data'] is List);
      // Une liste vide (ou sans rien d'exploitable) est une vraie réponse ;
      // un objet « user_info / server_info » ne l'est pas.
      return isList && (asJsonList(decoded).isEmpty) ? _Reply.empty : _Reply.unusable;
    } catch (_) {
      // Page web ou texte au lieu du JSON : l'API ne répond pas pour de vrai.
      return _Reply.unusable;
    }
  }

  /// Le serveur a répondu « cette action n'existe pas ici ».
  static bool _noVodOnServer(Object error) =>
      error is XtreamException &&
      (error.statusCode == 404 ||
          error.statusCode == 405 ||
          error.statusCode == 501);

  @override
  void dispose() {
    primary.dispose();
    fallback.dispose();
  }
}
