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
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/app/device_memory.dart';
import '../../../core/crash/crash_reporting.dart';
import '../../../core/i18n/l10n_now.dart';
import '../../channels/domain/channel.dart';
import '../../epg/domain/epg_program.dart';
import '../../player/data/player_settings.dart';
import '../../player/data/stream_diagnostics.dart';
import '../../vod/domain/vod_info.dart';
import '../../vod/domain/vod_movie.dart';
import '../../vod/domain/vod_series.dart';
import 'iptv_http.dart';
import 'playlist_import_limits.dart';
import 'source_link_utils.dart';

/// Exception métier pour signaler une erreur Xtream lisible
/// (login refusé, serveur HS, réponse non-JSON, etc.).
class XtreamException implements Exception {
  XtreamException(this.message);
  final String message;

  @override
  String toString() => 'XtreamException: $message';
}

/// Photo de l'état d'un compte Xtream, extraite du `user_info` de
/// player_api.php. Sert au diagnostic « code mort vs mauvais format
/// d'URL » : un statut ≠ Active ou une date passée explique 100 % des
/// échecs de flux sans qu'on ait à soupçonner l'app.
@immutable
class XtreamAccountInfo {
  const XtreamAccountInfo({
    this.status,
    this.expDate,
    this.maxConnections,
    this.activeCons,
  });

  /// `Active`, `Expired`, `Banned`, `Disabled`… tel que renvoyé
  /// par le panel (non normalisé par le protocole).
  final String? status;

  /// Date d'expiration (`exp_date` epoch secondes). `null` = illimité
  /// ou non communiqué.
  final DateTime? expDate;

  /// Connexions simultanées autorisées (`max_connections`).
  final int? maxConnections;

  /// Connexions actives au moment de l'appel (`active_cons`).
  final int? activeCons;
}

class XtreamClient {
  XtreamClient({
    required this.serverUrl,
    required this.username,
    required this.password,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 20),
  })  : _http = httpClient ?? createIptvHttpClient(),
        _timeout = timeout;

  final String serverUrl;
  final String username;
  final String password;
  final http.Client _http;
  final Duration _timeout;

  /// Normalise le serveur (filet défensif — normalement déjà fait par
  /// l'appelant, cf. `PlaylistRepository`) : complète http:// si absent,
  /// purge les caractères invisibles, et RÉDUIT un lien complet collé tel
  /// quel (get.php?username=…, portail /c/, player_api.php…) au vrai
  /// serveur. Sans ça, `_buildUri` fabriquait `…/get.php?…/player_api.php`
  /// → réponse M3U/HTML au lieu de JSON → code valide refusé.
  String get _baseUrl => SourceLinkUtils.sanitizeXtreamServer(serverUrl);

  /// Identifiants encodés pour URL. Un mot de passe contenant `@ & # + /`
  /// ou un espace cassait les URLs de flux/EPG construites par
  /// concaténation (le login passait, mais AUCUNE chaîne ne se lançait).
  String get _userEnc => Uri.encodeComponent(username.trim());
  String get _passEnc => Uri.encodeComponent(password.trim());

  /// Timeout de LECTURE du corps, plus généreux que celui d'établissement :
  /// un `get_live_streams` global de gros bouquet pèse des dizaines de Mo —
  /// 20 s ne suffisaient pas sur une connexion moyenne (le M3U laisse 90 s).
  static const Duration _bodyTimeout = Duration(seconds: 90);

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
      // Messages LOCALISÉS via l10nNow (pas de BuildContext dans ce client) :
      // ils remontent tels quels jusqu'aux écrans d'ajout/connexion. Seul le
      // TYPE XtreamException est pattern-matché par les appelants.
      throw XtreamException(l10nNow.xtreamInvalidResponse);
    }
    // Boîte noire : photo du compte (statut / expiration / connexions)
    // prise AU CHARGEMENT du compte — consultable dans l'écran debug
    // caché pour trancher « code mort » vs « mauvais format d'URL ».
    _recordAccountInfo(parseAccountInfo(userInfo));
    // Le protocole Xtream n'est pas normalisé : selon le panel, `auth`
    // vaut 1, "1", true ou "true" quand c'est bon — et certains panels
    // (forks XUI.one…) ne renvoient PAS le champ du tout alors que le
    // compte est valide (user_info présent avec status/exp_date). On ne
    // refuse donc que sur un refus EXPLICITE (0/false) — c'était le motif
    // n°1 du « ce code marche sur IBO mais pas chez nous ».
    final String auth =
        userInfo['auth']?.toString().trim().toLowerCase() ?? '';
    if (auth == '0' || auth == 'false') {
      throw XtreamException(l10nNow.xtreamCredentialsRefused);
    }
    // Statut : on ne refuse que les états clairement BLOQUANTS connus.
    // Un statut exotique inconnu (« Enabled », « Trial », vide…) passe —
    // le vrai test est l'import des chaînes juste après.
    final String status =
        userInfo['status']?.toString().trim().toLowerCase() ?? '';
    const Set<String> blocked = <String>{
      'banned', 'disabled', 'expired', 'suspended', 'blocked', 'inactive',
    };
    if (blocked.contains(status)) {
      throw XtreamException(l10nNow.xtreamAccountInactive(status));
    }
    // FORMAT DE SORTIE LIVE : les serveurs déclarent les conteneurs
    // autorisés dans `allowed_output_formats` (ex. ["m3u8"] seulement sur
    // les panels « sécurisés »). IBO/Smarters le respectent ; nous on
    // forçait `.ts` → HTTP 200 avec page vide → ÉCRAN NOIR alors que la
    // même chaîne marche sur IBO. Si `ts` n'est PAS autorisé mais que
    // `m3u8` l'est, on bascule les URLs live en HLS.
    final Object? formats = userInfo['allowed_output_formats'];
    if (formats is List) {
      final Set<String> allowed = formats
          .map((Object? e) => e?.toString().trim().toLowerCase() ?? '')
          .where((String e) => e.isNotEmpty)
          .toSet();
      if (allowed.isNotEmpty &&
          !allowed.contains('ts') &&
          allowed.contains('m3u8')) {
        _liveExtension = 'm3u8';
      }
    }
  }

  /// Re-demande l'état du compte à player_api.php (user_info) et le
  /// renvoie. Utilisé par le bouton « Vérifier le compte » de l'écran
  /// debug caché. Enregistre aussi le résultat dans la boîte noire.
  Future<XtreamAccountInfo> fetchAccountInfo() async {
    final Map<String, dynamic> data = await _callApi(action: null);
    final Map<String, dynamic>? userInfo =
        data['user_info'] as Map<String, dynamic>?;
    if (userInfo == null) {
      throw XtreamException('Réponse serveur invalide (pas de user_info).');
    }
    final XtreamAccountInfo info = parseAccountInfo(userInfo);
    _recordAccountInfo(info);
    return info;
  }

  /// Extrait les champs utiles du `user_info` (protocole non normalisé :
  /// nombres tantôt int, tantôt String ; `exp_date` epoch secondes,
  /// parfois `null`/vide pour « illimité »). Public + visibleForTesting
  /// pour tester le parsing sans réseau.
  @visibleForTesting
  static XtreamAccountInfo parseAccountInfo(Map<String, dynamic> userInfo) {
    int? asInt(Object? v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString().trim());
    }

    DateTime? expDate;
    final int? expEpoch = asInt(userInfo['exp_date']);
    if (expEpoch != null && expEpoch > 0) {
      expDate = DateTime.fromMillisecondsSinceEpoch(expEpoch * 1000);
    }

    final String? status = userInfo['status']?.toString().trim();
    return XtreamAccountInfo(
      status: (status == null || status.isEmpty) ? null : status,
      expDate: expDate,
      maxConnections: asInt(userInfo['max_connections']),
      activeCons: asInt(userInfo['active_cons']),
    );
  }

  void _recordAccountInfo(XtreamAccountInfo info) {
    StreamDiagnostics.instance.recordXtreamAccount(
      status: info.status,
      expDate: info.expDate,
      maxConnections: info.maxConnections,
      activeCons: info.activeCons,
    );
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
        // Repli localisé (langue active à l'IMPORT — le nom de catégorie est
        // ensuite STOCKÉ avec chaque chaîne ; un refresh le re-localise).
        final String name =
            item['category_name']?.toString() ?? l10nNow.fallbackNoName;
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
      // PLAFOND MÉMOIRE (anti-OOM), ADAPTÉ À LA RAM (DeviceMemory.channelCap) :
      // on arrête de matérialiser au-delà — le reste reste sur le serveur, la
      // source est juste tronquée à une taille tenable sur box faible.
      if (channels.length >= DeviceMemory.channelCap) break;
      if (item is! Map<String, dynamic>) continue;
      final Channel? ch = _mapLiveStream(item, playlistId, cats);
      if (ch != null) channels.add(ch);
    }

    if (kDebugMode) {
      debugPrint('[XtreamClient] ${channels.length} chaînes live récupérées');
    }
    CrashReporting.instance.recordMemoryBreadcrumbWithCounts(
        'xtream.channels.built', channels: channels.length);
    return channels;
  }

  /// PONT EPG : alias `epg_channel_id` → id de chaîne (`xtream-N`), accumulés
  /// pendant l'import. Le XMLTV du panel (`xmltv.php`) identifie ses chaînes
  /// par `epg_channel_id` (ex. « TF1.fr ») alors que nos chaînes s'appellent
  /// `xtream-<stream_id>` : sans ce pont, AUCUN programme importé ne matchait
  /// une chaîne Xtream → « Programme non disponible » partout (mismatch
  /// confirmé par la boîte noire : epg.import_ok avec count=0 et known élevé).
  /// Persisté par PlaylistRepository dans `epg_aliases`, consommé par
  /// EpgRepository au moment d'insérer les programmes. Borné (anti-OOM).
  final Map<String, String> _epgAliases = <String, String>{};
  static const int _kEpgAliasCap = 60000;

  /// Alias collectés par le DERNIER import/fetch live (epg_channel_id → id).
  Map<String, String> get epgChannelAliases =>
      Map<String, String>.unmodifiable(_epgAliases);

  /// Mappe UN objet JSON `get_live_streams` en [Channel] (parsing défensif :
  /// Xtream renvoie souvent des nombres en String). Renvoie `null` si l'entrée
  /// est inexploitable (pas de stream_id).
  Channel? _mapLiveStream(
    Map<String, dynamic> item,
    int playlistId,
    Map<String, String> cats,
  ) {
    final String streamId = item['stream_id']?.toString() ?? '';
    if (streamId.isEmpty) return null;
    final String epgChannelId =
        item['epg_channel_id']?.toString().trim() ?? '';
    if (epgChannelId.isNotEmpty && _epgAliases.length < _kEpgAliasCap) {
      _epgAliases[epgChannelId] = 'xtream-$streamId';
    }
    final String name =
        item['name']?.toString() ?? l10nNow.fallbackNoNameParens;
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
    return Channel(
      id: 'xtream-$streamId',
      playlistId: playlistId,
      name: name,
      category: category.isEmpty ? 'Autres' : category,
      streamUrl: _buildLiveStreamUrl(streamId),
      isLive: true,
      logoUrl: (streamIcon == null || streamIcon.isEmpty) ? null : streamIcon,
      catchupSupported: tvArchive == 1,
      catchupDays: tvArchive == 1 ? tvArchiveDuration : null,
    );
  }

  /// IMPORT LIVE EN FLUX (anti-OOM, le cœur du soin 15k–100k chaînes).
  ///
  /// Au lieu de télécharger+décoder TOUT `get_live_streams` d'un coup (un JSON
  /// de 15k+ objets → pic mémoire ~plusieurs centaines de Mo → kill natif sur
  /// box 1 Go), on importe **catégorie par catégorie** :
  ///   pour chaque catégorie → `get_live_streams&category_id=X` (petite
  ///   réponse) → on mappe le petit lot → `onBatch(lot)` l'insère
  ///   IMMÉDIATEMENT en base → on jette le lot. À aucun moment on ne tient une
  ///   `List<Channel>` géante ni un gros arbre JSON.
  ///
  /// Robustesse :
  ///  • Dédup par id (`seen`) : certains serveurs ignorent le filtre et
  ///    renvoient tout à chaque appel → on n'insère jamais de doublon, et le
  ///    plafond + l'arrêt anticipé évitent le travail inutile.
  ///  • Une catégorie qui échoue n'arrête pas les autres.
  ///  • REPLI : si aucune catégorie n'a produit de chaîne (serveur sans
  ///    filtrage), on retombe sur le fetch global capé [fetchLiveChannels].
  ///
  /// Renvoie le nombre total de chaînes importées (= insérées).
  Future<int> importLiveChannelsStreamed({
    required int playlistId,
    Map<String, String>? categories,
    required Future<void> Function(List<Channel> batch) onBatch,
    // PROGRESSION VIVANTE (écrans TV d'ajout) : appelé après chaque lot
    // inséré, avec le TOTAL courant et la catégorie en cours (« Sport »…)
    // → l'UI affiche un compteur qui monte au lieu d'un spinner muet.
    // OPTIONNEL et non-cassant : les appelants existants ne passent rien.
    void Function(int totalChannels, String? categoryName)? onProgress,
  }) async {
    final Map<String, String> cats =
        categories ?? await fetchLiveCategories();

    // ===== CHEMIN RAPIDE « façon TiviMate » =====
    // UN SEUL appel `get_live_streams` global au lieu d'UN PAR CATÉGORIE
    // (~140 allers-retours réseau séquentiels → 1). C'est CE fan-out qui
    // faisait durer l'import 6 min ; en un seul appel il tombe à ~10-20 s.
    // On insère par paquets de 1000 (écriture batchée + compteur vivant qui
    // monte). Filets préservés :
    //  • PAS tenté sur box à FAIBLE RAM (le gros JSON global = risque OOM) ;
    //  • si la réponse dépasse le plafond octets (kMaxXtreamJsonBytes, gros
    //    bouquet) → PlaylistImportTooLarge → on RETOMBE sur le chemin par
    //    catégorie (memory-safe), comportement d'origine intact ;
    //  • réponse globale vide (serveur qui n'accepte que le filtre par
    //    catégorie) → on tente aussi le chemin par catégorie.
    if (!DeviceMemory.lowRam) {
      try {
        final List<Channel> all = await fetchLiveChannels(
          playlistId: playlistId,
          categories: cats,
        );
        if (all.isNotEmpty) {
          int fast = 0;
          const int chunk = 1000;
          for (int i = 0; i < all.length; i += chunk) {
            final int end = (i + chunk < all.length) ? i + chunk : all.length;
            final List<Channel> batch = all.sublist(i, end);
            await onBatch(batch);
            fast += batch.length;
            onProgress?.call(fast, null);
            CrashReporting.instance.recordMemoryBreadcrumbWithCounts(
                'xtream.stream.fast', channels: fast);
          }
          return fast;
        }
      } on PlaylistImportTooLarge {
        // Bouquet trop gros pour un seul appel → repli par catégorie.
      } catch (_) {
        // Échec réseau/parse du global → repli par catégorie.
      }
    }

    // ===== CHEMIN PAR CATÉGORIE (memory-safe / repli) =====
    final Set<String> seen = <String>{};
    int total = 0;

    for (final MapEntry<String, String> entry in cats.entries) {
      if (total >= DeviceMemory.channelCap) break;
      List<dynamic> raw;
      try {
        raw = await _callApiList(
          action: 'get_live_streams',
          categoryId: entry.key,
        );
      } catch (_) {
        // Une catégorie injoignable/malformée ne bloque pas l'import global.
        continue;
      }
      final List<Channel> batch = <Channel>[];
      for (final dynamic item in raw) {
        if (total + batch.length >= DeviceMemory.channelCap) break;
        if (item is! Map<String, dynamic>) continue;
        final Channel? ch = _mapLiveStream(item, playlistId, cats);
        if (ch == null) continue;
        if (!seen.add(ch.id)) continue; // dédup (serveurs ignorant le filtre)
        batch.add(ch);
      }
      // `raw` (l'arbre JSON de CETTE catégorie) devient collectable ici.
      if (batch.isNotEmpty) {
        await onBatch(batch);
        total += batch.length;
        onProgress?.call(total, entry.value);
        CrashReporting.instance.recordMemoryBreadcrumbWithCounts(
            'xtream.stream.batch', channels: total);
      }
    }

    // REPLI : serveur qui ne sait pas filtrer par catégorie (0 chaîne obtenue
    // ainsi) → on tente l'ancien chemin global, déjà capé à channelCap.
    if (total == 0) {
      final List<Channel> all = await fetchLiveChannels(
        playlistId: playlistId,
        categories: cats,
      );
      if (all.isNotEmpty) {
        await onBatch(all);
        total = all.length;
        onProgress?.call(total, null);
      }
    }
    return total;
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
        final String name =
            item['category_name']?.toString() ?? l10nNow.fallbackNoName;
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
    // GROSSE SOURCE (10 000+ films) : on télécharge le corps HTTP puis on
    // fait TOUT le travail lourd — décodage JSON ET construction des objets
    // films — DANS UN ISOLATE. Avant, seul le décodage était isolé et la
    // construction de dizaines de milliers d'objets gelait l'écran
    // (« le Cinéma ne s'ouvre pas », écran noir figé). Le fil d'affichage
    // ne reçoit plus qu'une liste PRÊTE, déjà plafonnée.
    final Uri uri = _buildUri(action: 'get_vod_streams');
    final String body = await _getBody(uri);
    CrashReporting.instance.recordMemoryBreadcrumbWithCounts(
        'xtream.http.get_vod_streams',
        bytes: body.length);
    final List<VodMovie> movies = await compute(
      _parseVodMoviesIsolate,
      (
        body,
        cats,
        DeviceMemory.channelCap,
        _baseUrl,
        _userEnc,
        _passEnc,
        l10nNow.fallbackNoNameParens,
      ),
    );
    CrashReporting.instance
        .recordMemoryBreadcrumb('xtream.vod.parsed');
    if (kDebugMode) {
      debugPrint('[XtreamClient] ${movies.length} films VOD récupérés');
    }
    return movies;
  }

  /// URL d'un film VOD au format standard Xtream.
  String _buildVodStreamUrl(String streamId, String ext) {
    return '$_baseUrl/movie/$_userEnc/$_passEnc/$streamId.$ext';
  }

  /// Fiche DÉTAILLÉE d'un film (`get_vod_info`) : synopsis, casting,
  /// réalisateur, genre, durée, image de fond… — tout ce que le catalogue
  /// (`get_vod_streams`) ne fournit pas.
  ///
  /// FAIL-OPEN : toute erreur (serveur HS, timeout, JSON exotique) renvoie
  /// `null` — la fiche film s'affiche alors avec les seules infos de la
  /// vignette (nom, affiche, note) au lieu de planter ou de bloquer.
  Future<VodInfo?> fetchVodInfo(String streamId) async {
    try {
      final Map<String, dynamic> data =
          await _callApi(action: 'get_vod_info', vodId: streamId);
      return VodInfo.fromJson(data);
    } catch (e) {
      if (kDebugMode) debugPrint('[XtreamClient] get_vod_info: $e');
      return null;
    }
  }

  // ============================================================
  //  SÉRIES (saisons + épisodes)
  // ============================================================

  /// Catégories Séries (map id → nom).
  Future<Map<String, String>> fetchSeriesCategories() async {
    final List<dynamic> raw =
        await _callApiList(action: 'get_series_categories');
    final Map<String, String> result = <String, String>{};
    for (final dynamic item in raw) {
      if (item is Map<String, dynamic>) {
        final String id = item['category_id']?.toString() ?? '';
        final String name =
            item['category_name']?.toString() ?? l10nNow.fallbackNoName;
        if (id.isNotEmpty) result[id] = name;
      }
    }
    return result;
  }

  /// Catalogue des séries (vignettes). Les épisodes NE sont PAS chargés ici
  /// (2e appel get_series_info à l'ouverture de la fiche). Plafonné RAM.
  Future<List<VodSeries>> fetchSeries({Map<String, String>? categories}) async {
    final Map<String, String> cats =
        categories ?? await fetchSeriesCategories();
    final List<dynamic> raw = await _callApiList(action: 'get_series');

    final List<VodSeries> out = <VodSeries>[];
    for (final dynamic item in raw) {
      if (out.length >= DeviceMemory.channelCap) break; // anti-OOM RAM-tiered
      if (item is! Map<String, dynamic>) continue;
      final String seriesId = item['series_id']?.toString() ?? '';
      if (seriesId.isEmpty) continue;
      final String name =
          item['name']?.toString() ?? l10nNow.fallbackNoNameParens;
      final String categoryId = item['category_id']?.toString() ?? '';
      final String category = cats[categoryId] ?? 'Autres';
      final String? cover = item['cover']?.toString();
      final String? plot = item['plot']?.toString();
      final String? rating = item['rating']?.toString();
      final String? year = item['releaseDate']?.toString();
      out.add(
        VodSeries(
          id: seriesId,
          name: name,
          category: category.isEmpty ? 'Autres' : category,
          posterUrl: (cover == null || cover.isEmpty) ? null : cover,
          plot: (plot == null || plot.isEmpty) ? null : plot,
          rating: (rating == null || rating.isEmpty || rating == '0')
              ? null
              : rating,
          year: (year == null || year.isEmpty) ? null : year,
        ),
      );
    }
    if (kDebugMode) {
      debugPrint('[XtreamClient] ${out.length} séries récupérées');
    }
    return out;
  }

  /// Épisodes d'une série (tous saisons confondues, triés saison/épisode).
  /// Conservé pour compatibilité — délègue à [fetchSeriesDetail].
  Future<List<VodEpisode>> fetchSeriesEpisodes(String seriesId) async {
    return (await fetchSeriesDetail(seriesId)).episodes;
  }

  /// Fiche COMPLÈTE d'une série (`get_series_info`) : les épisodes ET les
  /// métadonnées riches (synopsis, casting, genre, image de fond…) — le
  /// même appel réseau sert les deux, on ne paie pas un fetch de plus.
  /// `info` est `null` si le serveur n'en fournit pas (fail-open).
  /// get_series_info renvoie `{ info: {...}, episodes: { "1": [...] } }`.
  Future<({VodInfo? info, List<VodEpisode> episodes})> fetchSeriesDetail(
      String seriesId) async {
    final Map<String, dynamic> data =
        await _callApi(action: 'get_series_info', seriesId: seriesId);
    // Métadonnées riches : parsing DÉFENSIF partagé avec les films (mêmes
    // clés dans le sous-objet `info`). Jamais bloquant : erreur → null.
    VodInfo? seriesInfo;
    try {
      seriesInfo = VodInfo.fromJson(data);
    } catch (_) {
      seriesInfo = null;
    }
    final dynamic eps = data['episodes'];
    final List<VodEpisode> out = <VodEpisode>[];
    if (eps is Map<String, dynamic>) {
      for (final MapEntry<String, dynamic> entry in eps.entries) {
        final int season = int.tryParse(entry.key) ?? 0;
        final dynamic list = entry.value;
        if (list is! List) continue;
        for (final dynamic e in list) {
          if (e is! Map<String, dynamic>) continue;
          final String id = e['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          final int epNum = int.tryParse(e['episode_num']?.toString() ?? '') ??
              (out.length + 1);
          String ext =
              (e['container_extension']?.toString() ?? 'mp4').trim();
          if (ext.isEmpty) ext = 'mp4';
          // Repli localisé — les épisodes ne sont PAS persistés (re-fetch à
          // chaque ouverture de fiche), donc le libellé suit la langue active.
          final String title =
              (e['title']?.toString().trim().isNotEmpty ?? false)
                  ? e['title'].toString()
                  : l10nNow.fallbackEpisode(epNum);
          // Vignette de l'épisode (image 16:9 propre à l'épisode) : les
          // panels la rangent dans `info.movie_image`. Défensif : absente
          // ou malformée → null, la fiche affiche le poster de la série.
          String? epPoster;
          final dynamic epInfo = e['info'];
          if (epInfo is Map<String, dynamic>) {
            final String img = epInfo['movie_image']?.toString() ?? '';
            if (img.startsWith('http')) epPoster = img;
          }
          out.add(
            VodEpisode(
              id: 'ep-$id',
              title: title,
              season: season,
              episodeNum: epNum,
              streamUrl: '$_baseUrl/series/$_userEnc/$_passEnc/$id.$ext',
              containerExt: ext,
              posterUrl: epPoster,
            ),
          );
        }
      }
    }
    out.sort((VodEpisode a, VodEpisode b) {
      final int s = a.season.compareTo(b.season);
      return s != 0 ? s : a.episodeNum.compareTo(b.episodeNum);
    });
    return (info: seriesInfo, episodes: out);
  }

  /// Ferme proprement le client HTTP. À appeler en fin de cycle.
  void dispose() => _http.close();

  // ============================================================
  //  Helpers internes
  // ============================================================

  /// Conteneur live : `.ts` (MPEG-TS brut, marche sur la plupart des
  /// serveurs) par défaut ; basculé sur `.m3u8` par [verifyCredentials]
  /// quand le serveur déclare ne PAS autoriser `ts`
  /// (allowed_output_formats). Les deux chemins d'import (ajout +
  /// rafraîchissement) vérifient les identifiants AVANT de construire
  /// les URLs, donc l'extension est déjà la bonne ici.
  String _liveExtension = 'ts';

  /// URL de stream live au format standard Xtream. En HLS, le serveur
  /// sert la playlist sous le préfixe `/live/` (forme standard Xtream) ;
  /// en `.ts` la forme courte sans préfixe marche partout.
  String _buildLiveStreamUrl(String streamId) {
    if (_liveExtension == 'm3u8') {
      return '$_baseUrl/live/$_userEnc/$_passEnc/$streamId.m3u8';
    }
    return '$_baseUrl/$_userEnc/$_passEnc/$streamId.ts';
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

  /// GET avec rotation de signatures, renvoyant le CORPS décodé (String) lu en
  /// STREAMING et BORNÉ à [kMaxXtreamJsonBytes] : on ne télécharge JAMAIS un
  /// JSON Xtream géant d'un bloc en RAM (cause racine OOM box faibles). Mémorise
  /// la signature gagnante. Lève une [XtreamException] si aucune signature n'a
  /// 200, ou [PlaylistImportTooLarge] si la réponse dépasse le plafond.
  Future<String> _getBody(Uri uri) async {
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
          final List<int> bytes = await _readCapped(
            resp.stream,
            kMaxXtreamJsonBytes,
          ).timeout(_bodyTimeout);
          // Xtream sert du JSON (UTF-8). allowMalformed pour ne jamais planter
          // sur un octet douteux d'un backend exotique.
          return utf8.decode(bytes, allowMalformed: true);
        }
        lastError = XtreamException(
          l10nNow.xtreamHttpError(resp.statusCode, uri.host),
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
    throw lastError ?? XtreamException(l10nNow.xtreamUnreachable(uri.host));
  }

  /// Lit [stream] en bornant à [maxBytes] (anti-OOM) : dépassement →
  /// [PlaylistImportTooLarge], le flux est interrompu et l'abonnement annulé.
  static Future<List<int>> _readCapped(
      Stream<List<int>> stream, int maxBytes) async {
    final BytesBuilder builder = BytesBuilder(copy: false);
    int total = 0;
    await for (final List<int> chunk in stream) {
      total += chunk.length;
      if (total > maxBytes) {
        throw PlaylistImportTooLarge(
          l10nNow.xtreamTooLarge(maxBytes ~/ (1024 * 1024)),
        );
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// Appel API qui retourne une Map JSON (cas verifyCredentials).
  Future<Map<String, dynamic>> _callApi(
      {required String? action, String? seriesId, String? vodId}) async {
    final Uri uri = _buildUri(action: action, seriesId: seriesId, vodId: vodId);
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
  /// [categoryId] (optionnel) restreint la réponse à une seule catégorie →
  /// import EN FLUX, mémoire bornée à un petit lot.
  Future<List<dynamic>> _callApiList({
    required String action,
    String? categoryId,
  }) async {
    final Uri uri = _buildUri(action: action, categoryId: categoryId);
    final String body = await _getBody(uri);
    // Breadcrumb : taille du corps HTTP reçu (suspect OOM n°1 sur grosse source).
    CrashReporting.instance
        .recordMemoryBreadcrumbWithCounts('xtream.http.$action', bytes: body.length);
    try {
      // Décodage dans un ISOLATE (compute) : sur un gros bouquet la réponse
      // pèse plusieurs Mo et un jsonDecode synchrone gèlerait l'UI (ANR).
      final dynamic decoded = await compute(_decodeJsonInIsolate, body);
      CrashReporting.instance.recordMemoryBreadcrumb('xtream.json.decoded.$action');
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

  Uri _buildUri({
    required String? action,
    String? categoryId,
    String? seriesId,
    String? vodId,
    String? streamId,
    int? limit,
  }) {
    final Uri base = Uri.parse('$_baseUrl/player_api.php');
    final Map<String, String> queryParameters = <String, String>{
      ...base.queryParameters,
      'username': username,
      'password': password,
      if (action != null) 'action': action,
      // Filtre par catégorie (import EN FLUX) : le serveur ne renvoie alors que
      // les chaînes de CETTE catégorie → petite réponse → mémoire bornée.
      if (categoryId != null && categoryId.isNotEmpty) 'category_id': categoryId,
      // Fiche série (get_series_info) : identifiant de la série demandée.
      if (seriesId != null && seriesId.isNotEmpty) 'series_id': seriesId,
      // Fiche film (get_vod_info) : identifiant du film demandé.
      if (vodId != null && vodId.isNotEmpty) 'vod_id': vodId,
      // EPG courte (get_short_epg) : identifiant du flux + nb de programmes.
      if (streamId != null && streamId.isNotEmpty) 'stream_id': streamId,
      if (limit != null) 'limit': '$limit',
    };
    return base.replace(queryParameters: queryParameters);
  }

  // ============================================================
  //  EPG COURTE (get_short_epg) — repli quand le XMLTV n'a rien
  // ============================================================

  /// Programmes « maintenant + suivants » d'UNE chaîne via l'API du panel
  /// (`get_short_epg`). Appel API léger (pas une connexion de FLUX : ne
  /// consomme pas la connexion unique des comptes 1-conn). Sert de REPLI à
  /// l'aperçu quand la base XMLTV locale ne connaît pas la chaîne (panel
  /// sans URL XMLTV, sync pas encore passée…). Renvoie `[]` sur toute
  /// réponse vide/malformée — jamais d'exception vers l'UI.
  Future<List<EpgProgram>> fetchShortEpg({
    required String streamId,
    int limit = 8,
  }) async {
    try {
      final Uri uri = _buildUri(
          action: 'get_short_epg', streamId: streamId, limit: limit);
      final String body = await _getBody(uri);
      final dynamic decoded = jsonDecode(body);
      return parseShortEpgListings(decoded, 'xtream-$streamId');
    } catch (_) {
      return const <EpgProgram>[];
    }
  }

  /// Parsing PUR (testable sans réseau) du JSON `get_short_epg` :
  /// `{"epg_listings":[{title(base64), start_timestamp, stop_timestamp,
  /// description(base64)}, …]}`. Défensif : titres en base64 OU en clair,
  /// timestamps en secondes epoch (String ou int), entrées invalides
  /// ignorées une à une.
  static List<EpgProgram> parseShortEpgListings(
    dynamic decoded,
    String channelId,
  ) {
    final List<dynamic> listings = decoded is Map<String, dynamic>
        ? (decoded['epg_listings'] is List
            ? decoded['epg_listings'] as List<dynamic>
            : const <dynamic>[])
        : (decoded is List ? decoded : const <dynamic>[]);
    final List<EpgProgram> out = <EpgProgram>[];
    for (final dynamic raw in listings) {
      if (raw is! Map) continue;
      final int? startS = _epochSeconds(raw['start_timestamp']);
      final int? stopS = _epochSeconds(raw['stop_timestamp']);
      if (startS == null || stopS == null || stopS <= startS) continue;
      final String title = _decodeMaybeBase64(raw['title']?.toString());
      if (title.isEmpty) continue;
      final String desc =
          _decodeMaybeBase64(raw['description']?.toString());
      out.add(EpgProgram(
        channelId: channelId,
        startTime: startS * 1000,
        stopTime: stopS * 1000,
        title: title,
        description: desc.isEmpty ? null : desc,
      ));
    }
    out.sort((EpgProgram a, EpgProgram b) => a.startTime - b.startTime);
    return out;
  }

  static int? _epochSeconds(dynamic v) {
    if (v is int) return v > 0 ? v : null;
    final int? parsed = int.tryParse(v?.toString() ?? '');
    return (parsed != null && parsed > 0) ? parsed : null;
  }

  /// Les panels encodent titres/descriptions en base64 — mais pas tous.
  /// On tente le décodage ; si le résultat n'est pas de l'UTF-8 valide ou
  /// que l'entrée n'est pas du base64, on garde le texte tel quel.
  static String _decodeMaybeBase64(String? v) {
    final String s = (v ?? '').trim();
    if (s.isEmpty) return '';
    try {
      return utf8.decode(base64Decode(s)).trim();
    } catch (_) {
      return s;
    }
  }
}

/// Décode du JSON dans un isolate (`compute`). Top-level = requis pour être
/// envoyable à un isolate. Sert à ne pas geler l'UI sur les grosses réponses
/// Xtream (get_live_streams / VOD / séries de plusieurs Mo).
dynamic _decodeJsonInIsolate(String source) => jsonDecode(source);

/// Analyse COMPLÈTE du catalogue VOD dans un isolate : décodage JSON +
/// construction des objets [VodMovie] (plafonnée). Tourne HORS du fil
/// d'affichage → l'écran Cinéma ne gèle jamais, même avec 50 000 films.
/// Entrée (record, seul argument transmissible à un isolate) :
///   (corps HTTP, catégories id→nom, plafond, baseUrl, userEnc, passEnc,
///    nom de repli). Les [VodMovie] (champs String uniquement) sont
///   recopiés vers le fil principal — sûr entre isolates.
List<VodMovie> _parseVodMoviesIsolate(
  (String, Map<String, String>, int, String, String, String, String) input,
) {
  final (
    String body,
    Map<String, String> cats,
    int cap,
    String baseUrl,
    String userEnc,
    String passEnc,
    String fallbackName,
  ) = input;
  final dynamic decoded = jsonDecode(body);
  final List<dynamic> raw = decoded is List
      ? decoded
      : (decoded is Map && decoded['data'] is List
          ? decoded['data'] as List<dynamic>
          : const <dynamic>[]);
  final List<VodMovie> movies = <VodMovie>[];
  for (final dynamic item in raw) {
    if (movies.length >= cap) break; // plafond mémoire (anti-OOM)
    if (item is! Map) continue;
    final String streamId = item['stream_id']?.toString() ?? '';
    if (streamId.isEmpty) continue;
    final String name = item['name']?.toString() ?? fallbackName;
    final String categoryId = item['category_id']?.toString() ?? '';
    final String category = cats[categoryId] ?? 'Autres';
    String ext = (item['container_extension']?.toString() ?? 'mp4').trim();
    if (ext.isEmpty) ext = 'mp4';
    final String? poster = item['stream_icon']?.toString();
    final String? rating = item['rating']?.toString();
    movies.add(VodMovie(
      id: 'vod-$streamId',
      name: name,
      category: category.isEmpty ? 'Autres' : category,
      streamUrl: '$baseUrl/movie/$userEnc/$passEnc/$streamId.$ext',
      containerExt: ext,
      posterUrl: (poster == null || poster.isEmpty) ? null : poster,
      rating: (rating == null || rating.isEmpty || rating == '0')
          ? null
          : rating,
    ));
  }
  return movies;
}
