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


import '../../../core/flavor/flavor.dart';
import '../../channels/domain/channel.dart';
import '../../epg/data/epg_repository.dart';
import '../domain/playlist.dart';
import 'm3u_fetcher.dart';
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

    // Phase 1+/Multi-serveurs (2026-06-01) : si une playlist est
    // marquee active, on filtre les chaines pour ne renvoyer que les
    // siennes. Sinon (cas sans active marquee — peut arriver si
    // l'user a delete la derniere active sans en designer une autre),
    // on retombe sur "toutes les chaines de toutes les playlists"
    // pour ne pas casser l'app.
    final List<Map<String, Object?>> activeRows = await db.query(
      'playlists',
      columns: <String>['id'],
      where: 'is_active = 1',
      limit: 1,
    );

    List<Map<String, Object?>> rows;
    if (activeRows.isNotEmpty) {
      final int activeId = activeRows.first['id'] as int;
      rows = await db.query(
        'channels',
        where: 'playlist_id = ?',
        whereArgs: <Object>[activeId],
        orderBy: 'name COLLATE NOCASE ASC',
      );
    } else {
      // Fallback : aucune playlist active explicitement -> tout
      rows = await db.query(
        'channels',
        orderBy: 'name COLLATE NOCASE ASC',
      );
    }
    final List<Channel> all = rows.map(_channelFromMap).toList();

    // Filtre adultOnly du flavor Red Room. On le pose ICI (point
    // unique de lecture) pour que TOUS les consommateurs (home,
    // favoris, recherche, EPG, recommandations) héritent
    // automatiquement de la restriction. Aucun risque d'oubli dans
    // un widget qui contournerait le repo.
    if (FlavorConfig.current.adultOnly) {
      return all.where((Channel c) => c.genre == ChannelGenre.adult).toList();
    }
    return all;
  }

  Future<List<Playlist>> getAllPlaylists() async {
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows =
        await db.query('playlists', orderBy: 'created_at DESC');
    return rows.map(Playlist.fromMap).toList();
  }

  /// Phase 1+/Multi-serveurs : retourne la playlist active, ou la 1ere
  /// (la plus ancienne) si aucune n'est marquee. `null` si la base
  /// est vide.
  Future<Playlist?> getActivePlaylist() async {
    final Database db = await PlaylistDatabase.instance.database;
    // 1) Tente la marquee active
    final List<Map<String, Object?>> active = await db.query(
      'playlists',
      where: 'is_active = 1',
      limit: 1,
    );
    if (active.isNotEmpty) return Playlist.fromMap(active.first);
    // 2) Fallback sur la plus ancienne
    final List<Map<String, Object?>> first = await db.query(
      'playlists',
      orderBy: 'created_at ASC',
      limit: 1,
    );
    if (first.isEmpty) return null;
    return Playlist.fromMap(first.first);
  }

  /// Phase 1+/Multi-serveurs : marque [playlistId] comme la playlist
  /// active. Garantit l'exclusivite (toutes les autres passent a
  /// is_active=0) via une transaction. Refresh ensuite le stream
  /// channels pour que l'UI bascule sans recharger.
  Future<void> setActivePlaylist(int playlistId) async {
    final Database db = await PlaylistDatabase.instance.database;
    await db.transaction((Transaction txn) async {
      await txn.update(
        'playlists',
        <String, Object?>{'is_active': 0},
        // Tout sauf la cible -> 0
        where: 'id != ?',
        whereArgs: <Object>[playlistId],
      );
      await txn.update(
        'playlists',
        <String, Object?>{'is_active': 1},
        where: 'id = ?',
        whereArgs: <Object>[playlistId],
      );
    });
    // Re-emit les chaines de la nouvelle playlist active.
    await _emitCurrentState();
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
    // On insère la playlist AVANT le download (le parser a besoin de son
    // id pour rattacher les chaînes). MAIS : si une étape échoue ensuite
    // (download KO, 0 chaîne…), on SUPPRIME cette entrée orpheline dans
    // le `catch` → on ne garde QUE les sources valides (demande client).
    int? playlistId;
    try {
      // 1) Insère la playlist (sans channelCount/lastSync)
      final Playlist newPlaylist = Playlist(
        id: null,
        name: name,
        type: PlaylistType.m3u,
        m3uUrl: url,
        epgUrl: epgUrl,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      playlistId = await _insertPlaylist(newPlaylist);

      // 2) Télécharge le contenu M3U via le fetcher robuste
      //    (User-Agent navigateur + UTF-8 / Latin-1 fallback +
      //    strip BOM + timeout 90s — gère les serveurs paranos
      //    ou les exports Windows-1252 mal étiquetés).
      if (kDebugMode) debugPrint('[Repo] GET $url');
      final String body = await M3uFetcher.fetch(url, httpClient: client);

      // 3) Parse (dans un ISOLATE → pas de gel UI) + insertion en batch
      final M3uParseResult parsed =
          await M3uParser.parseInBackground(body, playlistId: playlistId);

      if (parsed.channels.isEmpty) {
        // Source invalide → on lève ; le `catch` retire l'orpheline.
        final String hint = parsed.warnings.isEmpty
            ? ''
            : '\n\nDétails parser :\n${parsed.warnings.take(3).join('\n')}';
        throw Exception(
          'Aucune chaîne trouvée dans le fichier M3U. '
          'URL invalide ou format incompatible ?$hint',
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
    } catch (_) {
      // ÉCHEC après insertion (download, parse, 0 chaîne) → on retire la
      // playlist orpheline pour ne garder QUE les sources valides.
      if (playlistId != null) {
        await _deletePlaylist(playlistId);
      }
      rethrow;
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
    // Orpheline : si une étape échoue APRÈS insertion, on la supprime
    // (cf. `catch`) → on ne stocke QUE les comptes valides.
    int? playlistId;
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
      playlistId = await _insertPlaylist(newPlaylist);

      // 3) Récupère catégories + chaînes
      final Map<String, String> cats = await xtream.fetchLiveCategories();
      final List<Channel> channels = await xtream.fetchLiveChannels(
        playlistId: playlistId,
        categories: cats,
      );

      if (channels.isEmpty) {
        // Compte sans chaîne live → on lève ; le `catch` retire l'orpheline.
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
    } catch (_) {
      // ÉCHEC après insertion (fetch catégories/chaînes, 0 chaîne) → on
      // retire la playlist orpheline : on ne garde QUE le valide.
      if (playlistId != null) {
        await _deletePlaylist(playlistId);
      }
      rethrow;
    } finally {
      if (httpClient == null) xtream.dispose();
    }
  }

  // ============================================================
  //  SUPPRESSION
  // ============================================================

  Future<void> deletePlaylist(int playlistId) async {
    // Vidage SYNCHRONE du cache mémoire + émission immédiate d'une
    // liste vide AVANT le DELETE SQL. Sur grosses playlists (20k+
    // chaînes), le delete cascade prend 10-30s — sans ce vidage,
    // l'UI continue d'afficher les vieilles chaînes pendant tout
    // ce temps et l'utilisateur a l'impression que rien ne s'est
    // passé. Avec : la home se vide instantanément, puis on
    // ré-émet l'état réel à la fin du DELETE pour rester cohérent.
    final List<Playlist> remainingPlaylists = _playlistsCache
        .where((Playlist p) => p.id != playlistId)
        .toList();
    final List<Channel> remainingChannels = _channelsCache
        .where((Channel c) => c.playlistId != playlistId)
        .toList();
    _playlistsCache = remainingPlaylists;
    _channelsCache = remainingChannels;
    if (!_playlistsController.isClosed) {
      _playlistsController.add(remainingPlaylists);
    }
    if (!_channelsController.isClosed) {
      _channelsController.add(remainingChannels);
    }

    // Maintenant le DELETE SQL réel (peut prendre du temps sur
    // grosses playlists, mais l'UI est déjà à jour).
    await _deletePlaylist(playlistId);
    // Re-émet l'état "officiel" depuis la DB pour rester cohérent
    // en cas d'incohérence (rare).
    await _emitCurrentState();
  }

  // ============================================================
  //  REFRESH — re-télécharge la même source
  // ============================================================

  /// Re-télécharge une playlist existante en utilisant les mêmes
  /// paramètres d'origine. Supprime les anciennes chaînes et
  /// Re-synchronise TOUTES les playlists en parallèle. Renvoie le
  /// nombre de playlists actualisées avec succès. Sert au bouton
  /// "Actualiser" de la home et à l'auto-refresh au démarrage.
  Future<int> refreshAll() async {
    final List<Playlist> all = await getAllPlaylists();
    int ok = 0;
    for (final Playlist p in all) {
      try {
        final bool result = await refreshPlaylist(p);
        if (result) ok++;
      } catch (_) {
        // Best-effort — si une playlist échoue, on passe à la
        // suivante (on ne veut pas bloquer les autres).
      }
    }
    // Nettoyage : retire toute source qui s'est vidée (code qui n'a
    // plus de chaîne) pour ne pas laisser de playlist morte traîner.
    await pruneEmptyPlaylists();
    return ok;
  }

  /// Supprime les playlists DÉJÀ synchronisées qui n'ont AUCUNE chaîne
  /// (un code/stream qui « n'a pas marché »). Évite qu'une source morte
  /// reste et embrouille l'app. On IGNORE les playlists jamais
  /// synchronisées (last_synced_at NULL = ajout en cours), et on ne
  /// touche pas à une source temporairement injoignable (elle garde son
  /// dernier `channel_count` > 0). Renvoie le nombre supprimé.
  Future<int> pruneEmptyPlaylists() async {
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows = await db.query(
      'playlists',
      columns: <String>['id'],
      where: 'last_synced_at IS NOT NULL '
          'AND (channel_count IS NULL OR channel_count = 0)',
    );
    if (rows.isEmpty) return 0;
    for (final Map<String, Object?> r in rows) {
      await _deletePlaylist(r['id'] as int);
    }
    await _emitCurrentState();
    return rows.length;
  }

  /// Variante "soft" pour l'auto-refresh au démarrage : ne rafraîchit
  /// que les playlists dont `lastSyncedAt` date de plus de [staleness].
  /// Évite de re-fetch à chaque ouverture d'app si l'utilisateur lance
  /// 5 fois dans l'heure.
  Future<int> refreshStale({
    Duration staleness = const Duration(hours: 12),
  }) async {
    final List<Playlist> all = await getAllPlaylists();
    final int cutoff =
        DateTime.now().subtract(staleness).millisecondsSinceEpoch;
    int ok = 0;
    for (final Playlist p in all) {
      final int? last = p.lastSyncedAt;
      if (last != null && last > cutoff) continue;
      try {
        if (await refreshPlaylist(p)) ok++;
      } catch (_) {}
    }
    return ok;
  }

  /// charge les nouvelles. Le `playlistId` reste le même.
  ///
  /// Retourne `true` si la sync a réussi, lance une Exception sinon.
  Future<bool> refreshPlaylist(Playlist playlist) async {
    if (playlist.id == null) return false;
    final Database db = await PlaylistDatabase.instance.database;

    if (playlist.type == PlaylistType.m3u && playlist.m3uUrl != null) {
      final http.Client client = http.Client();
      try {
        // Même fetcher robuste qu'à l'ajout initial (Latin-1 fallback,
        // User-Agent navigateur, strip BOM, timeout 90s).
        final String body = await M3uFetcher.fetch(
          playlist.m3uUrl!,
          httpClient: client,
        );
        final M3uParseResult parsed =
            await M3uParser.parseInBackground(body, playlistId: playlist.id!);
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
    // Phase 1+/Multi-serveurs : si c'est la PREMIERE playlist (la
    // table etait vide), on la marque auto-active. Sinon, les
    // suivantes sont inactives par defaut (l'user les active
    // explicitement depuis l'UI). Comme ca le user qui n'utilise
    // qu'une playlist n'a jamais besoin de "choisir" — l'app marche
    // naturellement.
    final List<Map<String, Object?>> existing = await db.query(
      'playlists',
      columns: <String>['id'],
      limit: 1,
    );
    final bool isFirst = existing.isEmpty;
    final Map<String, Object?> map = playlist.toMap();
    if (isFirst) {
      map['is_active'] = 1;
    }
    return db.insert('playlists', map);
  }

  Future<void> _deletePlaylist(int id) async {
    final Database db = await PlaylistDatabase.instance.database;
    // Phase 1+/Multi-serveurs : si on delete l'active, on promeut la
    // plus ancienne playlist restante comme nouvelle active. Comme ca
    // l'user n'a pas a aller manuellement reactiver une autre source
    // apres suppression.
    final List<Map<String, Object?>> wasActive = await db.query(
      'playlists',
      columns: <String>['id'],
      where: 'id = ? AND is_active = 1',
      whereArgs: <Object>[id],
      limit: 1,
    );
    // ON DELETE CASCADE → les chaînes liées tombent automatiquement
    await db.delete('playlists', where: 'id = ?', whereArgs: <Object>[id]);
    if (wasActive.isNotEmpty) {
      final List<Map<String, Object?>> next = await db.query(
        'playlists',
        columns: <String>['id'],
        orderBy: 'created_at ASC',
        limit: 1,
      );
      if (next.isNotEmpty) {
        await db.update(
          'playlists',
          <String, Object?>{'is_active': 1},
          where: 'id = ?',
          whereArgs: <Object>[next.first['id'] as int],
        );
      }
    }
  }

  /// Insert toutes les chaînes en CHUNKS de 1000 + ré-émet l'état
  /// après chaque chunk. Sur grosses playlists (20k+), l'utilisateur
  /// voit le compteur grimper en direct au lieu d'attendre 30s qu'un
  /// gros batch finisse.
  ///
  /// Performance comparée :
  ///   - Avant : 1 batch de 27 085 inserts = ~25s freeze, puis pop
  ///   - Après : 27 batches de 1 000 = ~25s total mais l'UI se
  ///     rafraîchit toutes les ~900ms (chunk + emit) — sensation
  ///     "ça avance" au lieu de "ça dort".
  Future<void> _insertChannels(List<Channel> channels) async {
    const int chunkSize = 1000;
    final Database db = await PlaylistDatabase.instance.database;
    for (int i = 0; i < channels.length; i += chunkSize) {
      final int end = (i + chunkSize > channels.length)
          ? channels.length
          : i + chunkSize;
      final Batch batch = db.batch();
      for (int j = i; j < end; j++) {
        batch.insert('channels', _channelToMap(channels[j]));
      }
      await batch.commit(noResult: true);
      // Anti-ANR / mémoire : on NE recharge PLUS toute la base après
      // CHAQUE tranche (c'était du O(n²) — sur un gros bouquet ça ramait
      // de plus en plus). On émet seulement après la 1re tranche (premier
      // affichage rapide) et à la toute fin (cohérence garantie).
      final bool isFirst = i == 0;
      final bool isLast = end >= channels.length;
      if (isFirst || isLast) {
        await _emitCurrentState();
      }
    }
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
