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

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/observability/structured_logger.dart';
import '../../channels/domain/channel.dart';
import '../../player/data/player_settings.dart';
import '../../vod/domain/vod_movie.dart';

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

  /// Vérifie que les identifiants sont valides.
  /// Lance une `XtreamException` si KO.
  Future<void> verifyCredentials() async {
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

    final List<dynamic> raw = await _callApiList(
      action: 'get_live_streams',
    );

    final List<Channel> channels = <Channel>[];
    for (final dynamic item in raw) {
      if (item is! Map<String, dynamic>) continue;

      final String streamId = item['stream_id']?.toString() ?? '';
      if (streamId.isEmpty) continue;

      final String name = item['name']?.toString() ?? '(Sans nom)';
      final String categoryId = item['category_id']?.toString() ?? '';
      final String category = cats[categoryId] ?? 'Autres';
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
          playlistId: playlistId,
          name: name,
          category: category.isEmpty ? 'Autres' : category,
          streamUrl: _buildLiveStreamUrl(streamId),
          isLive: true,
          logoUrl: (streamIcon == null || streamIcon.isEmpty)
              ? null
              : streamIcon,
          catchupSupported: tvArchive == 1,
          catchupDays: tvArchive == 1 ? tvArchiveDuration : null,
        ),
      );
    }

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
  String _buildLiveStreamUrl(String streamId) {
    return '$_baseUrl/$username/$password/$streamId.ts';
  }

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

  /// GET avec rotation de signatures : renvoie la 1ʳᵉ réponse 200, en
  /// mémorisant la signature gagnante. Lève une [XtreamException] claire
  /// si AUCUNE signature n'obtient 200.
  Future<http.Response> _get(Uri uri) async {
    Object? lastError;
    for (final String ua in _candidateUserAgents()) {
      try {
        final Map<String, String> headers = <String, String>{
          'Accept': 'application/json',
          'User-Agent': ua,
          // En-têtes « complets » façon navigateur — certains fronts
          // CDN bloquent les requêtes trop nues (cf. m3u_fetcher).
          'Accept-Language': 'fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7',
          'Connection': 'keep-alive',
        };

        // PREUVE / DIAGNOSTIC 884 : trace de la requête EXACTE envoyée à
        // player_api.php (cf. docs/DIAGNOSTIC_HTTP_884.md). On masque le
        // mot de passe dans le log (sécurité) tout en gardant l'URL utile.
        StructuredLogger.instance.info(
          domain: 'net',
          event: 'xtream.request',
          ctx: <String, Object?>{
            'host': uri.host,
            'path': uri.path,
            'action': uri.queryParameters['action'],
            'ua': ua,
            'headers': headers,
          },
        );

        final http.Response resp =
            await _http.get(uri, headers: headers).timeout(_timeout);

        StructuredLogger.instance.info(
          domain: 'net',
          event: 'xtream.response',
          ctx: <String, Object?>{
            'host': uri.host,
            'status': resp.statusCode,
            'bytes': resp.bodyBytes.length,
            'contentType': resp.headers['content-type'],
          },
        );

        if (resp.statusCode == 200) {
          _workingUserAgent = ua;
          return resp;
        }
        lastError = XtreamException(
          'Erreur HTTP ${resp.statusCode} sur ${uri.host}',
        );
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

  /// Appel API qui retourne une Map JSON (cas verifyCredentials).
  Future<Map<String, dynamic>> _callApi({required String? action}) async {
    final Uri uri = _buildUri(action: action);
    final http.Response response = await _get(uri);
    try {
      final dynamic decoded = jsonDecode(response.body);
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
    final http.Response response = await _get(uri);
    try {
      // Décodage dans un ISOLATE (compute) : sur un gros bouquet la réponse
      // pèse plusieurs Mo et un jsonDecode synchrone gèlerait l'UI (ANR).
      final dynamic decoded =
          await compute(_decodeJsonInIsolate, response.body);
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

  Uri _buildUri({required String? action}) {
    final Uri base = Uri.parse('$_baseUrl/player_api.php');
    final Map<String, String> queryParameters = <String, String>{
      ...base.queryParameters,
      'username': username,
      'password': password,
      if (action != null) 'action': action,
    };
    return base.replace(queryParameters: queryParameters);
  }
}

/// Décode du JSON dans un isolate (`compute`). Top-level = requis pour être
/// envoyable à un isolate. Sert à ne pas geler l'UI sur les grosses réponses
/// Xtream (get_live_streams / VOD / séries de plusieurs Mo).
dynamic _decodeJsonInIsolate(String source) => jsonDecode(source);
