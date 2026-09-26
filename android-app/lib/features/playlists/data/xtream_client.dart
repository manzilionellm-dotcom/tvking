// =========================================================
//  xtream_client.dart — Client API Xtream Codes
// =========================================================
//  Le protocole Xtream Codes est la 2ème façon (après M3U)
//  pour qu'une app IPTV se connecte à un serveur.
//
//  L'utilisateur donne 3 infos :
//    - URL du serveur avec port (ex : http://server.com:8080)
//    - Username
//    - Password
//
//  L'app appelle ensuite plusieurs endpoints :
//
//    /player_api.php?username=X&password=Y
//        → infos sur le compte (vérification login)
//
//    /player_api.php?username=X&password=Y&action=get_live_categories
//        → liste des catégories live (id + nom)
//
//    /player_api.php?username=X&password=Y&action=get_live_streams
//        → liste de toutes les chaînes live, chacune avec son
//          stream_id, name, stream_icon, category_id, etc.
//
//  L'URL d'un flux Xtream se construit comme :
//    http://server:port/{username}/{password}/{stream_id}.ts
//  (ou .m3u8 selon le serveur — on tente .ts qui marche partout)
//
//  Robustesse : on gère les serveurs qui répondent en HTTP plain,
//  en JSON un peu malformé, ou qui ferment la connexion brutalement.
// =========================================================

import 'dart:async';
import 'dart:convert';
import 'dart:isolate' show TransferableTypedData;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/blackbox/black_box.dart';
import '../../channels/domain/channel.dart';
import 'import_progress.dart';
import '../../player/data/player_settings.dart';
import '../../vod/domain/vod_movie.dart';
import 'playlist_import_limits.dart';

/// Exception métier pour signaler une erreur Xtream lisible
/// (login refusé, serveur HS, réponse non-JSON, etc.).
class XtreamException implements Exception {
  XtreamException(this.message);
  final String message;

  @override
  String toString() => 'XtreamException: $message';
}

class XtreamClient {
  XtreamClient({
    required this.serverUrl,
    required this.username,
    required this.password,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 20),
  })  : _http = httpClient ?? http.Client(),
        _timeout = timeout;

  final String serverUrl;
  final String username;
  final String password;
  final http.Client _http;
  final Duration _timeout;

  /// Normalise le serveur : enlève le slash final éventuel.
  String get _baseUrl =>
      serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;

  // ============================================================
  //  Endpoints publics
  // ============================================================

  /// Base des URLs de lecture (`…/movie/…`, `…/series/…`), sans slash final.
  /// Utilisée par le module Cinéma pour construire les URLs de films et
  /// d'épisodes (jamais d'URL en dur : tout vient du compte du client).
  String get streamBase => _baseUrl;

  /// Appel brut `player_api.php?action=…` renvoyant les OCTETS de la réponse
  /// (décodés ensuite en isolate par l'appelant). Même rotation de
  /// signatures et même plafond mémoire que l'import des chaînes.
  /// [softMax] : au-delà, renvoie `null` (l'appelant passe au mode « par
  /// catégorie »). Sert au module Cinéma (films, séries, fiches détaillées).
  Future<Uint8List?> fetchActionBytes(
    String action, {
    Map<String, String>? extra,
    int? softMax,
  }) =>
      _getBytes(_buildUri(action: action, extra: extra), softMax: softMax);

  /// Vérifie que les identifiants sont valides.
  /// Lance une `XtreamException` si KO.
  Future<void> verifyCredentials() async {
    ImportProgressBus.connecting();
    final Map<String, dynamic> data = await _callApi(action: null);
    final Map<String, dynamic>? userInfo =
        data['user_info'] as Map<String, dynamic>?;
    if (userInfo == null) {
      throw XtreamException(
        'Réponse serveur invalide (pas de user_info).',
      );
    }
    final String auth = (userInfo['auth']?.toString() ?? '0');
    if (auth != '1') {
      throw XtreamException(
        'Identifiants refusés (auth=$auth). Vérifie ton login/mot de passe.',
      );
    }
    final String status = userInfo['status']?.toString() ?? '';
    if (status.isNotEmpty &&
        status.toLowerCase() != 'active' &&
        status != '1') {
      throw XtreamException(
        'Compte non-actif côté serveur (status=$status).',
      );
    }
  }

  /// Récupère la liste des catégories Live (map id → nom).
  Future<Map<String, String>> fetchLiveCategories() async {
    ImportProgressBus.categories();
    final List<dynamic> raw = await _callApiList(
      action: 'get_live_categories',
    );
    final Map<String, String> result = <String, String>{};
    for (final dynamic item in raw) {
      if (item is Map<String, dynamic>) {
        final String id = item['category_id']?.toString() ?? '';
        final String name = item['category_name']?.toString() ?? 'Sans nom';
        if (id.isNotEmpty) {
          result[id] = name;
        }
      }
    }
    return result;
  }

  /// Récupère TOUTES les chaînes live et renvoie une liste de Channel
  /// déjà mappés (id, nom, catégorie, URL de flux construite, logo).
  Future<List<Channel>> fetchLiveChannels({
    required int playlistId,
    Map<String, String>? categories,
  }) async {
    // Si on n'a pas reçu les catégories, on les récupère maintenant
    final Map<String, String> cats =
        categories ?? await fetchLiveCategories();

    final String host = Uri.tryParse(_baseUrl)?.host ?? _baseUrl;
    final String prefix = '$_baseUrl/$username/$password/';

    // TOUT EN ISOLATE (performance, 25/09/2026) : décodage JSON directement
    // depuis les OCTETS (décodeur UTF-8+JSON fusionné de dart:convert → aucune
    // String intermédiaire) ET construction des objets Channel hors du fil UI.
    // Les octets sont TRANSFÉRÉS (pas copiés) à l'isolate.
    //
    // MÉMOIRE BORNÉE (cause n°1 de « l'app se ferme à Connexion… » sur box
    // 1 Go, cf. boîte noire) : on tente d'abord la liste ENTIÈRE, mais on
    // s'arrête net au-delà de kXtreamSingleShotBytes ; dans ce cas on
    // re-télécharge CATÉGORIE PAR CATÉGORIE (`category_id`) : chaque réponse
    // est petite, décodée, mappée, puis libérée. Le pic mémoire devient celui
    // d'une catégorie au lieu du bouquet entier (même approche que les
    // lecteurs natifs qui lisent le JSON en flux).
    BlackBox.instance.breadcrumb('Import Xtream $host : téléchargement de la liste');
    await BlackBox.instance.logMemory('avant import Xtream');
    final Uint8List? whole = await _getBytes(
      _buildUri(action: 'get_live_streams'),
      softMax: kXtreamSingleShotBytes,
      onBytes: ImportProgressBus.downloading,
    );

    List<Channel> channels;
    if (whole != null) {
      final String mb = (whole.length / (1024 * 1024)).toStringAsFixed(1);
      BlackBox.instance.info('XTREAM', '$host : $mb Mo reçus (bloc unique) → décodage en isolate');
      BlackBox.instance.breadcrumb('Import Xtream $host : décodage $mb Mo (isolate)');
      ImportProgressBus.decoding(whole.length);
      channels = await compute(
        _mapLiveStreamsInIsolate,
        _LiveStreamsJob(
          payload: TransferableTypedData.fromList(<Uint8List>[whole]),
          categories: cats,
          playlistId: playlistId,
          streamUrlPrefix: prefix,
          maxChannels: kMaxChannelsPerImport,
        ),
      );
    } else {
      BlackBox.instance.warn('XTREAM',
          '$host : liste > ${kXtreamSingleShotBytes ~/ (1024 * 1024)} Mo → import PAR CATÉGORIE (${cats.length} catégories)');
      channels = <Channel>[];
      final Set<String> seen = <String>{};
      int i = 0;
      for (final MapEntry<String, String> cat in cats.entries) {
        i++;
        if (channels.length >= kMaxChannelsPerImport) break;
        BlackBox.instance.breadcrumb(
            'Import Xtream $host : catégorie $i/${cats.length} « ${cat.value} »');
        ImportProgressBus.category(i, cats.length, channels.length);
        try {
          final Uint8List? part = await _getBytes(
            _buildUri(
              action: 'get_live_streams',
              extra: <String, String>{'category_id': cat.key},
            ),
          );
          if (part == null) continue;
          final List<Channel> mapped = await compute(
            _mapLiveStreamsInIsolate,
            _LiveStreamsJob(
              payload: TransferableTypedData.fromList(<Uint8List>[part]),
              categories: cats,
              playlistId: playlistId,
              streamUrlPrefix: prefix,
              maxChannels: kMaxChannelsPerImport - channels.length,
            ),
          );
          // Une chaîne peut être rangée dans deux catégories : dédup par id.
          for (final Channel c in mapped) {
            if (seen.add(c.id)) channels.add(c);
          }
        } catch (e) {
          // Une catégorie en échec n'annule pas l'import : on la note et on continue.
          BlackBox.instance.warn('XTREAM', 'catégorie « ${cat.value} » ignorée : $e');
        }
      }
    }

    BlackBox.instance.info('XTREAM', '$host : ${channels.length} chaînes live récupérées');
    ImportProgressBus.found(channels.length);
    await BlackBox.instance.logMemory('après import Xtream');
    BlackBox.instance.breadcrumb('');
    if (kDebugMode) {
      debugPrint('[XtreamClient] ${channels.length} chaînes live récupérées');
    }
    return channels;
  }

  // ============================================================
  //  VOD (films à la demande)
  // ============================================================

  /// Catégories VOD (map id → nom).
  Future<Map<String, String>> fetchVodCategories() async {
    final List<dynamic> raw =
        await _callApiList(action: 'get_vod_categories');
    final Map<String, String> result = <String, String>{};
    for (final dynamic item in raw) {
      if (item is Map<String, dynamic>) {
        final String id = item['category_id']?.toString() ?? '';
        final String name = item['category_name']?.toString() ?? 'Sans nom';
        if (id.isNotEmpty) result[id] = name;
      }
    }
    return result;
  }

  /// Récupère tous les films VOD et les mappe en [VodMovie] (URL de
  /// fichier construite, poster, catégorie). Renvoie une liste vide si
  /// le serveur ne propose pas de VOD.
  Future<List<VodMovie>> fetchVodMovies({Map<String, String>? categories}) async {
    final Map<String, String> cats =
        categories ?? await fetchVodCategories();
    final List<dynamic> raw = await _callApiList(action: 'get_vod_streams');

    final List<VodMovie> movies = <VodMovie>[];
    for (final dynamic item in raw) {
      if (movies.length >= kMaxChannelsPerImport) break; // plafond mémoire (anti-OOM)
      if (item is! Map<String, dynamic>) continue;
      final String streamId = item['stream_id']?.toString() ?? '';
      if (streamId.isEmpty) continue;
      final String name = item['name']?.toString() ?? '(Sans nom)';
      final String categoryId = item['category_id']?.toString() ?? '';
      final String category = cats[categoryId] ?? 'Autres';
      // Extension du conteneur : mp4 par défaut si non fournie.
      String ext = (item['container_extension']?.toString() ?? 'mp4').trim();
      if (ext.isEmpty) ext = 'mp4';
      final String? poster = item['stream_icon']?.toString();
      final String? rating = item['rating']?.toString();

      movies.add(
        VodMovie(
          id: 'vod-$streamId',
          name: name,
          category: category.isEmpty ? 'Autres' : category,
          streamUrl: _buildVodStreamUrl(streamId, ext),
          containerExt: ext,
          posterUrl: (poster == null || poster.isEmpty) ? null : poster,
          rating: (rating == null || rating.isEmpty || rating == '0')
              ? null
              : rating,
        ),
      );
    }
    if (kDebugMode) {
      debugPrint('[XtreamClient] ${movies.length} films VOD récupérés');
    }
    return movies;
  }

  /// URL d'un film VOD au format standard Xtream.
  String _buildVodStreamUrl(String streamId, String ext) {
    return '$_baseUrl/movie/$username/$password/$streamId.$ext';
  }

  /// Ferme proprement le client HTTP. À appeler en fin de cycle.
  void dispose() => _http.close();

  // ============================================================
  //  Helpers internes
  // ============================================================

  /// URL de stream live au format standard Xtream.
  /// `.ts` est le format brut MPEG-TS reconnu par 100% des serveurs.
  /// (On essaiera `.m3u8` plus tard si on rencontre un fournisseur
  /// qui ne sert que du HLS.)

  /// Signature (User-Agent) qui a fonctionné pour ce serveur. Mémorisée
  /// au 1er appel réussi pour ne pas re-tester toute la liste à chaque
  /// endpoint (catégories, chaînes, VOD…).
  String? _workingUserAgent;

  /// Liste ORDONNÉE des signatures de lecteur à essayer (sans doublon).
  /// Beaucoup de serveurs Xtream ne répondent (player_api.php) QU'aux UA
  /// de lecteurs connus et renvoient 403/401/code maison aux autres. On
  /// les essaie en cascade, exactement comme pour le M3U.
  List<String> _candidateUserAgents() {
    final List<String> list = <String>[];
    void add(String? ua) {
      if (ua == null) return;
      final String v = ua.trim();
      if (v.isEmpty || list.contains(v)) return;
      list.add(v);
    }

    add(_workingUserAgent);
    add(PlayerSettings.instance.userAgent);
    for (final String v in PlayerSettings.userAgentPresets.values) {
      add(v);
    }
    add('Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36');
    return list;
  }

  /// GET avec rotation de signatures, renvoyant le CORPS décodé (String) lu en
  /// STREAMING et BORNÉ à [kMaxXtreamJsonBytes] : on ne télécharge JAMAIS un
  /// JSON Xtream géant d'un bloc en RAM (cause racine OOM box faibles). Mémorise
  /// la signature gagnante. Lève une [XtreamException] si aucune signature n'a
  /// 200, ou [PlaylistImportTooLarge] si la réponse dépasse le plafond.
  Future<String> _getBody(Uri uri) async {
    final Uint8List bytes = (await _getBytes(uri))!; // null impossible sans softMax
    // Xtream sert du JSON (UTF-8). allowMalformed pour ne jamais planter
    // sur un octet douteux d'un backend exotique.
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Variante OCTETS de [_getBody] : même rotation de signatures, même
  /// plafond, mais sans décodage — pour confier le décodage à un isolate
  /// (cf. [fetchLiveChannels]).
  ///
  /// [softMax] : plafond SOUPLE — au-delà, on coupe le téléchargement et on
  /// renvoie `null` (l'appelant bascule sur un import par catégorie). Sans
  /// [softMax], seul le plafond dur [kMaxXtreamJsonBytes] s'applique (erreur).
  Future<Uint8List?> _getBytes(Uri uri,
      {int? softMax, void Function(int received)? onBytes}) async {
    Object? lastError;
    for (final String ua in _candidateUserAgents()) {
      try {
        final http.Request req = http.Request('GET', uri)
          ..followRedirects = true
          ..headers.addAll(<String, String>{
            'Accept': 'application/json',
            'User-Agent': ua,
            // En-têtes « complets » façon navigateur — certains fronts
            // CDN bloquent les requêtes trop nues (cf. m3u_fetcher).
            'Accept-Language': 'fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7',
            'Connection': 'keep-alive',
          });
        final http.StreamedResponse resp =
            await _http.send(req).timeout(_timeout);
        if (resp.statusCode == 200) {
          _workingUserAgent = ua;
          return await _readCapped(
            resp.stream,
            kMaxXtreamJsonBytes,
            softMax: softMax,
            onBytes: onBytes,
          ).timeout(_timeout);
        }
        lastError = XtreamException(
          'Erreur HTTP ${resp.statusCode} sur ${uri.host}',
        );
      } on PlaylistImportTooLarge {
        // Taille indépendante de la signature → on remonte l'erreur claire.
        rethrow;
      } on TimeoutException catch (e) {
        // Serveur injoignable/trop lent : pas un souci d'UA → on arrête
        // pour ne pas cumuler les timeouts sur chaque signature.
        lastError = e;
        break;
      } on Exception catch (e) {
        lastError = e;
      }
    }
    throw lastError ??
        XtreamException('Serveur Xtream injoignable (${uri.host}).');
  }

  /// Lit [stream] en bornant à [maxBytes] (anti-OOM) : dépassement →
  /// [PlaylistImportTooLarge], le flux est interrompu et l'abonnement annulé.
  static Future<Uint8List?> _readCapped(
      Stream<List<int>> stream, int maxBytes,
      {int? softMax, void Function(int received)? onBytes}) async {
    final BytesBuilder builder = BytesBuilder(copy: false);
    int total = 0;
    await for (final List<int> chunk in stream) {
      total += chunk.length;
      onBytes?.call(total); // progression « Téléchargement… x Mo » (limitée côté bus)
      // Plafond souple : on arrête de lire (le `return` annule l'abonnement →
      // la connexion est fermée) et on signale « trop gros pour un bloc ».
      if (softMax != null && total > softMax) return null;
      if (total > maxBytes) {
        throw PlaylistImportTooLarge(
          'Source Xtream trop volumineuse (> ${maxBytes ~/ (1024 * 1024)} Mo). '
          'Filtre les catégories côté fournisseur.',
        );
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// Appel API qui retourne une Map JSON (cas verifyCredentials).
  Future<Map<String, dynamic>> _callApi({required String? action}) async {
    final Uri uri = _buildUri(action: action);
    final String body = await _getBody(uri);
    try {
      final dynamic decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw XtreamException(
        'Réponse JSON non attendue (Map attendue) sur action=$action.',
      );
    } on FormatException catch (e) {
      throw XtreamException(
        'Réponse non-JSON sur action=$action : ${e.message}',
      );
    }
  }

  /// Appel API qui retourne une List JSON (cas get_live_streams, etc.).
  Future<List<dynamic>> _callApiList({required String action}) async {
    final Uri uri = _buildUri(action: action);
    final String body = await _getBody(uri);
    try {
      // Décodage dans un ISOLATE (compute) : sur un gros bouquet la réponse
      // pèse plusieurs Mo et un jsonDecode synchrone gèlerait l'UI (ANR).
      final dynamic decoded = await compute(_decodeJsonInIsolate, body);
      if (decoded is List<dynamic>) return decoded;
      // Certains serveurs encapsulent dans `{data: [...]}` ; on tolère.
      if (decoded is Map<String, dynamic> && decoded['data'] is List) {
        return decoded['data'] as List<dynamic>;
      }
      throw XtreamException(
        'Réponse JSON non attendue (List attendue) sur action=$action.',
      );
    } on FormatException catch (e) {
      throw XtreamException(
        'Réponse non-JSON sur action=$action : ${e.message}',
      );
    }
  }

  // Point d'entrée de l'isolate pour le décodage JSON (cf. _callApiList).
  // Doit rester top-level/statique pour être envoyable à `compute`.

  Uri _buildUri({required String? action, Map<String, String>? extra}) {
    final Uri base = Uri.parse('$_baseUrl/player_api.php');
    final Map<String, String> queryParameters = <String, String>{
      ...base.queryParameters,
      'username': username,
      'password': password,
      if (action != null) 'action': action,
      ...?extra,
    };
    return base.replace(queryParameters: queryParameters);
  }
}

/// Décode du JSON dans un isolate (`compute`). Top-level = requis pour être
/// envoyable à un isolate. Sert à ne pas geler l'UI sur les grosses réponses
/// Xtream (get_live_streams / VOD / séries de plusieurs Mo).
dynamic _decodeJsonInIsolate(String source) => jsonDecode(source);

/// Paramètres du mapping `get_live_streams` exécuté en isolate. Uniquement des
/// types envoyables (TransferableTypedData, Map, int, String).
class _LiveStreamsJob {
  const _LiveStreamsJob({
    required this.payload,
    required this.categories,
    required this.playlistId,
    required this.streamUrlPrefix,
    required this.maxChannels,
  });
  final TransferableTypedData payload;
  final Map<String, String> categories;
  final int playlistId;
  final String streamUrlPrefix;
  final int maxChannels;
}

/// Décode + mappe la réponse `get_live_streams` en objets [Channel], HORS du
/// fil UI (cf. [XtreamClient.fetchLiveChannels]). Top-level = requis par
/// `compute`. La logique est celle de l'ancienne boucle synchrone, inchangée.
List<Channel> _mapLiveStreamsInIsolate(_LiveStreamsJob job) {
  final Uint8List bytes = job.payload.materialize().asUint8List();
  // Décodeur UTF-8 → JSON FUSIONNÉ de dart:convert : parse le JSON directement
  // depuis les octets, sans construire la String intermédiaire (qui pesait
  // 1-2× la taille du JSON en plus de l'arbre d'objets).
  dynamic decoded;
  try {
    decoded = const Utf8Decoder(allowMalformed: true)
        .fuse(const JsonDecoder())
        .convert(bytes);
  } on FormatException catch (e) {
    throw XtreamException(
      'Réponse non-JSON sur action=get_live_streams : ${e.message}',
    );
  }
  List<dynamic> raw;
  if (decoded is List<dynamic>) {
    raw = decoded;
  } else if (decoded is Map<String, dynamic> && decoded['data'] is List) {
    raw = decoded['data'] as List<dynamic>; // certains serveurs encapsulent
  } else {
    throw XtreamException(
      'Réponse JSON non attendue (List attendue) sur action=get_live_streams.',
    );
  }

  final List<Channel> channels = <Channel>[];
  for (final dynamic item in raw) {
    // PLAFOND MÉMOIRE (anti-OOM) : on arrête de matérialiser au-delà du
    // plafond d'import — le reste reste sur le serveur, la source est juste
    // tronquée à une taille tenable sur box faible.
    if (channels.length >= job.maxChannels) break;
    if (item is! Map<String, dynamic>) continue;

    final String streamId = item['stream_id']?.toString() ?? '';
    if (streamId.isEmpty) continue;

    final String name = item['name']?.toString() ?? '(Sans nom)';
    final String categoryId = item['category_id']?.toString() ?? '';
    final String category = job.categories[categoryId] ?? 'Autres';
    final String? streamIcon = item['stream_icon']?.toString();
    final dynamic tvArchiveRaw = item['tv_archive'];
    final int tvArchive = tvArchiveRaw is int
        ? tvArchiveRaw
        : int.tryParse(tvArchiveRaw?.toString() ?? '') ?? 0;
    final dynamic tvArchiveDurationRaw = item['tv_archive_duration'];
    final int tvArchiveDuration = tvArchiveDurationRaw is int
        ? tvArchiveDurationRaw
        : int.tryParse(tvArchiveDurationRaw?.toString() ?? '') ?? 0;

    channels.add(
      Channel(
        id: 'xtream-$streamId',
        playlistId: job.playlistId,
        name: name,
        category: category.isEmpty ? 'Autres' : category,
        streamUrl: '${job.streamUrlPrefix}$streamId.ts',
        isLive: true,
        logoUrl:
            (streamIcon == null || streamIcon.isEmpty) ? null : streamIcon,
        catchupSupported: tvArchive == 1,
        catchupDays: tvArchive == 1 ? tvArchiveDuration : null,
      ),
    );
  }
  return channels;
}
