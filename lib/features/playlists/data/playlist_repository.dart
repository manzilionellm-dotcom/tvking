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


import '../../../core/app/device_memory.dart';
import '../../../core/crash/crash_reporting.dart';
import '../../../core/flavor/flavor.dart';
import '../../../core/security/secret_cipher.dart';
import '../../channels/domain/channel.dart';
import '../../channels/domain/channel_genre.dart';
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

  // FILTRE FLAVOR (POINT UNIQUE) : sur un flavor `adultOnly` (ex. « Privé »),
  // on ne laisse passer QUE les chaînes du genre Adulte. Comme tout l'UI
  // (accueil, recherche, favoris, EPG, reco) lit les chaînes par ICI, la
  // restriction est héritée partout, sans toucher chaque écran. Sur les
  // flavors normaux (The Few, TV), `adultOnly` = false → aucune restriction.
  List<Channel> _applyFlavorFilter(List<Channel> all) {
    if (!FlavorConfig.current.adultOnly) return all;
    return all
        .where((Channel c) => c.genre == ChannelGenre.adult)
        .toList(growable: false);
  }

  Stream<List<Channel>> get channelsStream =>
      _channelsController.stream.map(_applyFlavorFilter);
  Stream<List<Playlist>> get playlistsStream => _playlistsController.stream;

  /// Snapshot synchrone des chaînes actuellement chargées. À utiliser
  /// en `initialData` d'un StreamBuilder pour avoir l'état immédiatement.
  List<Channel> get currentChannels => _applyFlavorFilter(_channelsCache);

  /// Snapshot synchrone des playlists actuellement chargées.
  List<Playlist> get currentPlaylists => _playlistsCache;

  /// Charge initialement les chaînes depuis la base et émet sur le stream.
  /// À appeler une fois au démarrage de l'app.
  Future<void> initialize() async {
    // Prépare la clé de chiffrement AVANT toute lecture (déchiffrement des
    // mots de passe Xtream). Fail-open : si indisponible, lecture en clair.
    await SecretCipher.instance.ensureReady();
    await _emitCurrentState();
  }

  /// Construit une [Playlist] depuis une ligne SQLite en DÉCHIFFRANT le mot de
  /// passe Xtream (les anciennes valeurs en clair sont renvoyées telles quelles
  /// par le cipher). Point UNIQUE de lecture → l'objet en mémoire a toujours le
  /// mot de passe EN CLAIR (l'UI, le client Xtream et la sauvegarde cloud le
  /// voient déchiffré ; seule la colonne SQLite est chiffrée).
  Playlist _playlistFromRow(Map<String, Object?> row) {
    final Object? pw = row['xtream_password'];
    if (pw is String && pw.isNotEmpty) {
      final Map<String, Object?> copy = Map<String, Object?>.from(row);
      copy['xtream_password'] = SecretCipher.instance.decrypt(pw);
      return Playlist.fromMap(copy);
    }
    return Playlist.fromMap(row);
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

    final int? activeId =
        activeRows.isNotEmpty ? activeRows.first['id'] as int : null;
    if (activeId == null) {
      // Aucune playlist active. AVANT de tout renvoyer, on PURGE les
      // chaînes orphelines (dont la playlist a été supprimée) : sur les
      // bases créées avant l'activation des clés étrangères, le CASCADE
      // n'avait pas joué et ces chaînes « fantômes » réapparaissaient
      // après suppression de toutes les listes. Cette purge guérit ces
      // bases au premier passage → l'écran se vide vraiment.
      await db.delete(
        'channels',
        where: 'playlist_id NOT IN (SELECT id FROM playlists)',
      );
    }
    // LECTURE PAR LOTS + PLAFOND MÉMOIRE (anti-OOM box faibles). Avant, un
    // SEUL gros SELECT ramenait TOUTES les lignes d'un coup, puis on
    // construisait la liste complète de Channel : sur une grosse source
    // (50k–100k+ chaînes), le pic mémoire (lignes brutes + objets) faisait
    // planter/redémarrer les petites box. On lit désormais par tranches
    // (keyset sur local_id, l'ordre natif de la playlist est préservé) et on
    // s'arrête au plafond. Voir _readChannelsBounded.
    final List<Channel> all = await _readChannelsBounded(db, activeId);

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

  /// Plafond de chaînes chargées EN MÉMOIRE — garde-fou anti-OOM des box
  /// faibles. DÉSORMAIS ADAPTÉ À LA RAM (cf. DeviceMemory.channelCap) au lieu
  /// d'un 50 000 fixe : une box 1 Go plafonne à 10 000, une grosse box à
  /// 50 000. Au-delà, on s'arrête : les chaînes supplémentaires restent en base
  /// (rien n'est perdu) mais ne sont pas matérialisées en RAM, ce qui
  /// empêchait la TV de planter/redémarrer sur les sources géantes.
  static int get kMaxInMemoryChannels => DeviceMemory.channelCap;

  /// Taille d'un lot de lecture. On lit la table par tranches (keyset sur
  /// `local_id`, la clé primaire) au lieu d'un unique gros SELECT : le pic
  /// mémoire transitoire (lignes brutes SQLite) est borné à UN lot au lieu de
  /// TOUTE la playlist → moitié moins de pression mémoire à l'ouverture.
  static const int _kReadChunk = 5000;

  /// Lit les chaînes par lots successifs et borne le total à
  /// [kMaxInMemoryChannels]. Keyset pagination : `local_id > dernier` (O(1) par
  /// lot grâce à l'index PK), l'ORDRE NATIF de la playlist est préservé.
  Future<List<Channel>> _readChannelsBounded(Database db, int? activeId) async {
    final List<Channel> out = <Channel>[];
    int afterLocalId = 0; // local_id (AUTOINCREMENT) démarre à 1
    while (out.length < kMaxInMemoryChannels) {
      final List<Map<String, Object?>> rows = await db.query(
        'channels',
        where: activeId != null
            ? 'playlist_id = ? AND local_id > ?'
            : 'local_id > ?',
        whereArgs: activeId != null
            ? <Object>[activeId, afterLocalId]
            : <Object>[afterLocalId],
        orderBy: 'local_id ASC',
        limit: _kReadChunk,
      );
      if (rows.isEmpty) break;
      for (final Map<String, Object?> r in rows) {
        out.add(_channelFromMap(r));
        afterLocalId = r['local_id'] as int;
      }
      if (rows.length < _kReadChunk) break; // dernière tranche
    }
    if (out.length >= kMaxInMemoryChannels) {
      debugPrint('[Playlist] plafond mémoire atteint '
          '($kMaxInMemoryChannels chaînes) → tranches suivantes NON chargées '
          '(garde-fou anti-OOM box faibles).');
    }
    return out;
  }

  Future<List<Playlist>> getAllPlaylists() async {
    await SecretCipher.instance.ensureReady();
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows =
        await db.query('playlists', orderBy: 'created_at DESC');
    return rows.map(_playlistFromRow).toList();
  }

  /// Phase 1+/Multi-serveurs : retourne la playlist active, ou la 1ere
  /// (la plus ancienne) si aucune n'est marquee. `null` si la base
  /// est vide.
  Future<Playlist?> getActivePlaylist() async {
    await SecretCipher.instance.ensureReady();
    final Database db = await PlaylistDatabase.instance.database;
    // 1) Tente la marquee active
    final List<Map<String, Object?>> active = await db.query(
      'playlists',
      where: 'is_active = 1',
      limit: 1,
    );
    if (active.isNotEmpty) return _playlistFromRow(active.first);
    // 2) Fallback sur la plus ancienne
    final List<Map<String, Object?>> first = await db.query(
      'playlists',
      orderBy: 'created_at ASC',
      limit: 1,
    );
    if (first.isEmpty) return null;
    return _playlistFromRow(first.first);
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

      // 3) Parse (dans un ISOLATE → pas de gel UI) + insertion en batch.
      //    Plafond chaînes ADAPTÉ À LA RAM passé à l'isolate (anti-OOM).
      final M3uParseResult parsed = await M3uParser.parseInBackground(
        body,
        playlistId: playlistId,
        maxChannels: DeviceMemory.channelCap,
      );

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

      // CORRECTIF « les chaînes n'arrivent jamais » : on ACTIVE la
      // playlist qu'on vient d'ajouter. Sans ça, seule la TOUTE 1re
      // playlist était auto-active (cf. _insertPlaylist) ; un 2e ajout
      // (nouveau code, nouvelle tentative, source poussée…) restait
      // `is_active=0` → `getAllChannels` filtrait ses chaînes et l'accueil
      // affichait l'ancienne source (ou rien) malgré le « connecté ».
      // setActivePlaylist ré-émet l'état → l'accueil bascule aussitôt.
      await setActivePlaylist(playlistId);

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

      // CORRECTIF « les chaînes n'arrivent jamais » : on ACTIVE la
      // playlist Xtream qu'on vient d'ajouter (même raison que pour le
      // M3U). Sans ça, un 2e compte ajouté restait invisible car
      // `getAllChannels` ne renvoie que les chaînes de la playlist active.
      await setActivePlaylist(playlistId);

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

  /// RÉCUPÉRATION (mode sans échec) : supprime TOUTES les playlists et leurs
  /// chaînes, directement en base, SANS dépendre des streams ni du cache (donc
  /// utilisable très tôt au démarrage, avant `initialize()`). Sert au bouton
  /// « Supprimer ma source / Réinitialiser » de l'écran de récupération.
  Future<void> deleteAllPlaylists() async {
    final Database db = await PlaylistDatabase.instance.database;
    await db.delete('channels');
    await db.delete('playlists');
    _channelsCache = const <Channel>[];
    _playlistsCache = const <Playlist>[];
  }

  // ============================================================
  //  REFRESH — re-télécharge la même source
  // ============================================================

  /// Re-télécharge une playlist existante en utilisant les mêmes
  /// paramètres d'origine. Supprime les anciennes chaînes et
  /// Re-synchronise TOUTES les playlists en parallèle. Renvoie le
  /// nombre de playlists actualisées avec succès. Sert au bouton
  /// "Actualiser" de la home et à l'auto-refresh au démarrage.
  // Anti-concurrence (P1-1) : refreshAll re-télécharge + re-parse TOUTES les
  // sources (gros pics mémoire). Il est appelé par le bouton « Actualiser », le
  // timer 24 h et l'auto-refresh — sans verrou, deux passes pouvaient se
  // chevaucher et DOUBLER le pic mémoire (suspect OOM). On garantit une seule
  // passe à la fois.
  bool _refreshingAll = false;

  Future<int> refreshAll() async {
    if (_refreshingAll) return 0; // une passe déjà en cours → on ne double pas
    _refreshingAll = true;
    try {
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
    } finally {
      _refreshingAll = false;
    }
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
        final M3uParseResult parsed = await M3uParser.parseInBackground(
          body,
          playlistId: playlist.id!,
          maxChannels: DeviceMemory.channelCap,
        );
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
    // CHIFFREMENT AU REPOS : on chiffre le mot de passe Xtream AVANT l'écriture
    // en base (fail-open : si la clé n'est pas dispo, la valeur reste en clair).
    // C'est le SEUL point d'écriture du mot de passe → un seul endroit à chiffrer.
    await SecretCipher.instance.ensureReady();
    final Object? pw = map['xtream_password'];
    if (pw is String && pw.isNotEmpty) {
      map['xtream_password'] = SecretCipher.instance.encrypt(pw);
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
    // Suppression EXPLICITE des chaînes de cette liste AVANT la liste.
    // On ne se repose pas sur le seul `ON DELETE CASCADE` : il exige que
    // `PRAGMA foreign_keys = ON` soit actif (ce qui est désormais le cas,
    // cf. PlaylistDatabase._onConfigure), mais ce delete direct garantit
    // le nettoyage même sur d'anciennes bases et purge toute chaîne déjà
    // orpheline. Sans ça, les chaînes réapparaissaient après suppression.
    await db.delete('channels', where: 'playlist_id = ?', whereArgs: <Object>[id]);
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
    CrashReporting.instance.recordMemoryBreadcrumbWithCounts(
        'sqlite.insert.start', channels: channels.length);
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
    }
    CrashReporting.instance.recordMemoryBreadcrumbWithCounts(
        'sqlite.insert.done', channels: channels.length);
    // ANTI-OOM (P1-3) : on N'ÉMET PLUS d'état ICI — ni par tranche, ni à la
    // fin. Chaque appelant ré-émet l'état UNE seule fois APRÈS l'insertion
    // (addM3u/addXtream → setActivePlaylist ; refreshPlaylist →
    // _emitCurrentState). Avant, `_emitCurrentState()` relisait TOUTE la base
    // (jusqu'à 50k Channel) pendant l'import → une matérialisation complète
    // supplémentaire EN PLUS de `parsed.channels` déjà en RAM = pic mémoire qui
    // faisait planter les box faibles. On lit la base une seule fois, à la fin.
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
