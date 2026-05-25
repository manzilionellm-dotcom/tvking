// =========================================================
//  playlist_repository.dart — Façade haut niveau pour
//  manipuler playlists et chaînes (M3U + Xtream + SQLite)
// =========================================================
//  C'est l'INTERFACE que l'UI utilise. Elle masque tous les
//  détails :
//    - téléchargement HTTP du .m3u
//    - appels API Xtream
//    - parsing
//    - persistance SQLite
//    - notification de changement (via Stream)
//
//  Implémentation : singleton simple (on passera à Riverpod
//  Phase 1.4 quand l'app aura plus de viewmodels).
//
//  Stream :
//    - `channelsStream` émet la liste à jour des chaînes
//      visibles (toutes playlists confondues, on ne supporte
//      qu'une playlist active pour l'instant mais c'est
//      facile à étendre).
//    - L'écran d'accueil s'abonne via `StreamBuilder`.
// =========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
// ignore: depend_on_referenced_packages — dart:async fournit unawaited


import '../../channels/domain/channel.dart';
import '../../epg/data/epg_repository.dart';
import '../domain/playlist.dart';
import 'm3u_parser.dart';
import 'playlist_database.dart';
import 'xtream_client.dart';

/// Résultat individuel d'un import en lot.
class BatchImportResult {
  const BatchImportResult.success({
    required this.name,
    required this.channelCount,
  })  : ok = true,
        error = null;

  const BatchImportResult.failure({
    required this.name,
    required this.error,
  })  : ok = false,
        channelCount = 0;

  final bool ok;
  final String name;
  final int channelCount;
  final String? error;
}

class PlaylistRepository {
  PlaylistRepository._();
  static final PlaylistRepository instance = PlaylistRepository._();

  // Notifie chaque écran abonné quand les chaînes/playlists changent.
  final StreamController<List<Channel>> _channelsController =
      StreamController<List<Channel>>.broadcast();
  final StreamController<List<Playlist>> _playlistsController =
      StreamController<List<Playlist>>.broadcast();

  // Dernier snapshot émis — sert d'`initialData` aux nouveaux
  // abonnés du Stream (qui ne reçoivent PAS l'event passé d'un
  // broadcast stream). Sans ça, naviguer d'un écran à l'autre
  // affichait "0 chaînes" jusqu'à la prochaine mise à jour.
  List<Channel> _channelsCache = const <Channel>[];
  List<Playlist> _playlistsCache = const <Playlist>[];

  Stream<List<Channel>> get channelsStream => _channelsController.stream;
  Stream<List<Playlist>> get playlistsStream => _playlistsController.stream;

  /// Snapshot synchrone des chaînes actuellement chargées. À utiliser
  /// en `initialData` d'un StreamBuilder pour avoir l'état immédiatement.
  List<Channel> get currentChannels => _channelsCache;

  /// Snapshot synchrone des playlists actuellement chargées.
  List<Playlist> get currentPlaylists => _playlistsCache;

  /// Charge initialement les chaînes depuis la base et émet sur le stream.
  /// À appeler une fois au démarrage de l'app.
  Future<void> initialize() async {
    await _emitCurrentState();
  }

  // ============================================================
  //  LECTURE
  // ============================================================

  Future<List<Channel>> getAllChannels() async {
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows =
        await db.query('channels', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(_channelFromMap).toList();
  }

  Future<List<Playlist>> getAllPlaylists() async {
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows =
        await db.query('playlists', orderBy: 'created_at DESC');
    return rows.map(Playlist.fromMap).toList();
  }

  // ============================================================
  //  AJOUT PLAYLIST — M3U
  // ============================================================

  /// Télécharge le .m3u puis stocke les chaînes en base.
  ///
  /// Lance une [Exception] si l'URL est invalide ou si le
  /// téléchargement échoue.
  Future<Playlist> addM3uPlaylist({
    required String name,
    required String url,
    String? epgUrl,
    http.Client? httpClient,
  }) async {
    final http.Client client = httpClient ?? http.Client();
    try {
      // 1) Insère la playlist d'abord (sans channelCount/lastSync)
      final Playlist newPlaylist = Playlist(
        id: null,
        name: name,
        type: PlaylistType.m3u,
        m3uUrl: url,
        epgUrl: epgUrl,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      final int playlistId = await _insertPlaylist(newPlaylist);

      // 2) Télécharge le contenu M3U
      if (kDebugMode) debugPrint('[Repo] GET $url');
      final http.Response resp = await client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 60));

      if (resp.statusCode != 200) {
        throw Exception('Erreur HTTP ${resp.statusCode}');
      }

      // 3) Parse + insertion en batch
      final M3uParseResult parsed =
          M3uParser.parse(resp.body, playlistId: playlistId);

      if (parsed.channels.isEmpty) {
        await _deletePlaylist(playlistId);
        throw Exception(
          'Aucune chaîne trouvée dans le fichier M3U. URL invalide ?',
        );
      }

      await _insertChannels(parsed.channels);
      final Playlist saved = newPlaylist.copyWith(
        id: playlistId,
        channelCount: parsed.channels.length,
        lastSyncedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _updatePlaylistMetrics(saved);

      await _emitCurrentState();

      // Si une URL EPG est fournie → on déclenche la sync en
      // arrière-plan (non bloquant : l'utilisateur peut déjà
      // naviguer pendant que l'EPG arrive).
      if (epgUrl != null && epgUrl.isNotEmpty) {
        unawaited(_syncEpgFor(parsed.channels, epgUrl));
      }
      return saved;
    } finally {
      if (httpClient == null) client.close();
    }
  }

  /// Lance l'import EPG en arrière-plan, ignore les erreurs réseau
  /// (l'utilisateur peut toujours retenter manuellement plus tard).
  Future<void> _syncEpgFor(
    List<Channel> channels,
    String epgUrl,
  ) async {
    try {
      final Set<String> ids =
          channels.map((Channel c) => c.id).toSet();
      await EpgRepository.instance.downloadAndImport(
        url: epgUrl,
        knownChannelIds: ids,
      );
    } catch (_) {
      // Silencieux — l'EPG est optionnel.
    }
  }

  // ============================================================
  //  AJOUT PLAYLIST — M3U en LOT (multi-URL)
  // ============================================================

  /// Importe plusieurs URLs M3U d'un coup. La progression est
  /// rapportée via [onProgress] qui reçoit (urlActuelle, indexCourant,
  /// total, success, errorMessageOuNull).
  ///
  /// On continue même si une URL plante — on collecte les erreurs
  /// et on les renvoie à la fin.
  Future<List<BatchImportResult>> addM3uPlaylistsBatch({
    required List<({String name, String url})> entries,
    void Function(int index, int total, String name, BatchImportResult? result)?
        onProgress,
  }) async {
    final List<BatchImportResult> results = <BatchImportResult>[];
    for (int i = 0; i < entries.length; i++) {
      final ({String name, String url}) entry = entries[i];
      onProgress?.call(i, entries.length, entry.name, null);
      try {
        final Playlist saved = await addM3uPlaylist(
          name: entry.name,
          url: entry.url,
        );
        final BatchImportResult ok = BatchImportResult.success(
          name: entry.name,
          channelCount: saved.channelCount,
        );
        results.add(ok);
        onProgress?.call(i + 1, entries.length, entry.name, ok);
      } on Exception catch (e) {
        final BatchImportResult ko = BatchImportResult.failure(
          name: entry.name,
          error: e.toString(),
        );
        results.add(ko);
        onProgress?.call(i + 1, entries.length, entry.name, ko);
      }
    }
    return results;
  }

  // ============================================================
  //  AJOUT PLAYLIST — Xtream Codes
  // ============================================================

  /// URL XMLTV auto-générée pour un compte Xtream.
  /// Standard de fait : <serveur>/xmltv.php?username=X&password=Y
  static String xtreamEpgUrl({
    required String serverUrl,
    required String username,
    required String password,
  }) {
    final String base = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
    return '$base/xmltv.php?username=$username&password=$password';
  }

  Future<Playlist> addXtreamPlaylist({
    required String name,
    required String serverUrl,
    required String username,
    required String password,
    http.Client? httpClient,
  }) async {
    // 1) Vérifie d'abord les credentials, avant de polluer la base
    final XtreamClient xtream = XtreamClient(
      serverUrl: serverUrl,
      username: username,
      password: password,
      httpClient: httpClient,
    );
    try {
      await xtream.verifyCredentials();

      // 2) Crée la playlist en base (avec EPG URL auto-générée)
      final Playlist newPlaylist = Playlist(
        id: null,
        name: name,
        type: PlaylistType.xtream,
        xtreamServer: serverUrl,
        xtreamUsername: username,
        xtreamPassword: password,
        epgUrl: xtreamEpgUrl(
          serverUrl: serverUrl,
          username: username,
          password: password,
        ),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      final int playlistId = await _insertPlaylist(newPlaylist);

      // 3) Récupère catégories + chaînes
      final Map<String, String> cats = await xtream.fetchLiveCategories();
      final List<Channel> channels = await xtream.fetchLiveChannels(
        playlistId: playlistId,
        categories: cats,
      );

      if (channels.isEmpty) {
        await _deletePlaylist(playlistId);
        throw Exception(
          'Aucune chaîne live disponible pour ce compte Xtream.',
        );
      }

      await _insertChannels(channels);
      final Playlist saved = newPlaylist.copyWith(
        id: playlistId,
        channelCount: channels.length,
        lastSyncedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _updatePlaylistMetrics(saved);

      await _emitCurrentState();

      // EPG auto en arrière-plan (Xtream a sa propre URL XMLTV)
      if (newPlaylist.epgUrl != null) {
        unawaited(_syncEpgFor(channels, newPlaylist.epgUrl!));
      }
      return saved;
    } finally {
      if (httpClient == null) xtream.dispose();
    }
  }

  // ============================================================
  //  SUPPRESSION
  // ============================================================

  Future<void> deletePlaylist(int playlistId) async {
    await _deletePlaylist(playlistId);
    await _emitCurrentState();
  }

  // ============================================================
  //  REFRESH — re-télécharge la même source
  // ============================================================

  /// Re-télécharge une playlist existante en utilisant les mêmes
  /// paramètres d'origine. Supprime les anciennes chaînes et
  /// charge les nouvelles. Le `playlistId` reste le même.
  ///
  /// Retourne `true` si la sync a réussi, lance une Exception sinon.
  Future<bool> refreshPlaylist(Playlist playlist) async {
    if (playlist.id == null) return false;
    final Database db = await PlaylistDatabase.instance.database;

    if (playlist.type == PlaylistType.m3u && playlist.m3uUrl != null) {
      final http.Client client = http.Client();
      try {
        final http.Response resp = await client
            .get(Uri.parse(playlist.m3uUrl!))
            .timeout(const Duration(seconds: 60));
        if (resp.statusCode != 200) {
          throw Exception('Erreur HTTP ${resp.statusCode}');
        }
        final M3uParseResult parsed =
            M3uParser.parse(resp.body, playlistId: playlist.id!);
        if (parsed.channels.isEmpty) {
          throw Exception('Aucune chaîne dans la nouvelle version.');
        }
        // Remplace les chaînes existantes
        await db.delete(
          'channels',
          where: 'playlist_id = ?',
          whereArgs: <Object>[playlist.id!],
        );
        await _insertChannels(parsed.channels);
        await _updatePlaylistMetrics(
          playlist.copyWith(
            channelCount: parsed.channels.length,
            lastSyncedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        await _emitCurrentState();
        return true;
      } finally {
        client.close();
      }
    }

    if (playlist.type == PlaylistType.xtream &&
        playlist.xtreamServer != null &&
        playlist.xtreamUsername != null &&
        playlist.xtreamPassword != null) {
      final XtreamClient xtream = XtreamClient(
        serverUrl: playlist.xtreamServer!,
        username: playlist.xtreamUsername!,
        password: playlist.xtreamPassword!,
      );
      try {
        await xtream.verifyCredentials();
        final Map<String, String> cats = await xtream.fetchLiveCategories();
        final List<Channel> channels = await xtream.fetchLiveChannels(
          playlistId: playlist.id!,
          categories: cats,
        );
        if (channels.isEmpty) {
          throw Exception('Aucune chaîne live disponible.');
        }
        await db.delete(
          'channels',
          where: 'playlist_id = ?',
          whereArgs: <Object>[playlist.id!],
        );
        await _insertChannels(channels);
        await _updatePlaylistMetrics(
          playlist.copyWith(
            channelCount: channels.length,
            lastSyncedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        await _emitCurrentState();
        return true;
      } finally {
        xtream.dispose();
      }
    }

    return false;
  }

  // ============================================================
  //  Helpers SQLite internes
  // ============================================================

  Future<int> _insertPlaylist(Playlist playlist) async {
    final Database db = await PlaylistDatabase.instance.database;
    return db.insert('playlists', playlist.toMap());
  }

  Future<void> _deletePlaylist(int id) async {
    final Database db = await PlaylistDatabase.instance.database;
    // ON DELETE CASCADE → les chaînes liées tombent automatiquement
    await db.delete('playlists', where: 'id = ?', whereArgs: <Object>[id]);
  }

  Future<void> _insertChannels(List<Channel> channels) async {
    final Database db = await PlaylistDatabase.instance.database;
    // Batch pour gagner ~10x sur grosses playlists.
    final Batch batch = db.batch();
    for (final Channel ch in channels) {
      batch.insert('channels', _channelToMap(ch));
    }
    await batch.commit(noResult: true);
  }

  Future<void> _updatePlaylistMetrics(Playlist playlist) async {
    if (playlist.id == null) return;
    final Database db = await PlaylistDatabase.instance.database;
    await db.update(
      'playlists',
      <String, Object?>{
        'last_synced_at': playlist.lastSyncedAt,
        'channel_count': playlist.channelCount,
      },
      where: 'id = ?',
      whereArgs: <Object>[playlist.id!],
    );
  }

  Future<void> _emitCurrentState() async {
    final List<Channel> channels = await getAllChannels();
    final List<Playlist> playlists = await getAllPlaylists();
    // Met à jour les caches synchrones avant d'émettre
    // (`currentChannels` est ainsi cohérent avec le dernier event).
    _channelsCache = channels;
    _playlistsCache = playlists;
    if (!_channelsController.isClosed) {
      _channelsController.add(channels);
    }
    if (!_playlistsController.isClosed) {
      _playlistsController.add(playlists);
    }
  }

  // ============================================================
  //  Mapping Channel ↔ SQLite
  // ============================================================

  Map<String, Object?> _channelToMap(Channel ch) {
    return <String, Object?>{
      'playlist_id': ch.playlistId,
      'external_id': ch.id,
      'name': ch.name,
      'category': ch.category,
      'stream_url': ch.streamUrl,
      'logo_url': ch.logoUrl,
      'is_live': ch.isLive ? 1 : 0,
      'catchup_supported': ch.catchupSupported ? 1 : 0,
      'catchup_days': ch.catchupDays,
      'catchup_source': ch.catchupSource,
    };
  }

  Channel _channelFromMap(Map<String, Object?> map) {
    return Channel(
      id: map['external_id'] as String,
      playlistId: map['playlist_id'] as int?,
      name: map['name'] as String,
      category: map['category'] as String,
      streamUrl: map['stream_url'] as String,
      isLive: (map['is_live'] as int? ?? 1) == 1,
      logoUrl: map['logo_url'] as String?,
      catchupSupported: (map['catchup_supported'] as int? ?? 0) == 1,
      catchupDays: map['catchup_days'] as int?,
      catchupSource: map['catchup_source'] as String?,
    );
  }
}
