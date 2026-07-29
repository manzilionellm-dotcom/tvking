// =========================================================
//  epg_repository.dart — Stockage et accès aux programmes EPG
// =========================================================
//  Table SQLite `epg_programs` indexée par (channel_id, start_time).
//
//  Opérations principales :
//    - downloadAndImport(url) : télécharge un XMLTV (avec support
//      gzip), parse en streaming, insère par batch dans SQLite,
//      purge les programmes périmés
//    - currentProgram(channelId) : programme qui se joue maintenant
//    - nextProgram(channelId) : programme suivant
//    - programsBetween(channelId, start, end) : pour la grille TV
//
//  Émet sur un Stream à chaque mise à jour pour que les UI
//  réactives (TV Guide, cards) se rafraîchissent.
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../../../core/observability/structured_logger.dart';
import '../../playlists/data/iptv_http.dart';
import '../../playlists/data/playlist_database.dart';
import '../domain/epg_program.dart';
import 'xmltv_parser.dart';

class EpgRepository {
  EpgRepository._();
  static final EpgRepository instance = EpgRepository._();

  final StreamController<void> _changesController =
      StreamController<void>.broadcast();

  /// Émet à chaque sync EPG → les écrans rebuildent.
  Stream<void> get changes => _changesController.stream;

  bool _initialized = false;
  bool _syncing = false;

  bool get isSyncing => _syncing;

  // ============================================================
  //  CACHE MÉMOIRE « programme en cours » (fluidité du défilement)
  // ============================================================
  //  Défiler une liste de chaînes créait autant de requêtes SQLite que de
  //  tuiles affichées (chaque tuile demande son programme en cours) → rafale
  //  de requêtes + setState pendant le scroll = saccades. Ce cache court
  //  (60 s) rend instantané tout ré-affichage d'une chaîne déjà vue : on
  //  défile de haut en bas sans re-toucher la base. Vidé à chaque sync EPG
  //  (les données changent) et borné (LRU) pour ne pas peser sur une box.
  final Map<String, ({DateTime at, EpgProgram? prog})> _nowCache =
      <String, ({DateTime at, EpgProgram? prog})>{};
  static const Duration _nowTtl = Duration(seconds: 60);
  static const int _nowCacheMax = 600;

  /// Programme en cours DÉJÀ EN CACHE (synchrone, zéro I/O) — `null` si absent
  /// ou périmé. Les tuiles l'utilisent pour s'afficher SANS attendre la base.
  EpgProgram? cachedCurrent(String channelId) {
    final ({DateTime at, EpgProgram? prog})? e = _nowCache[channelId];
    if (e == null) return null;
    if (DateTime.now().difference(e.at) > _nowTtl) return null;
    return e.prog;
  }

  void _rememberNow(String channelId, EpgProgram? prog) {
    if (_nowCache.length >= _nowCacheMax) {
      _nowCache.remove(_nowCache.keys.first); // éviction FIFO simple
    }
    _nowCache[channelId] = (at: DateTime.now(), prog: prog);
  }

  // ============================================================
  //  Initialisation (création des tables)
  // ============================================================

  Future<void> initialize() async {
    if (_initialized) return;
    final Database db = await PlaylistDatabase.instance.database;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS epg_programs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        channel_id TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        stop_time INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        category TEXT,
        icon_url TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_epg_channel_time
      ON epg_programs(channel_id, start_time)
    ''');
    // ANTI-DOUBLONS (audit 2026-07-29) : l'import XMLTV ré-insérait toute la
    // fenêtre future à chaque sync (aucune contrainte d'unicité) → la table
    // doublait à chaque refresh et le guide affichait les programmes en
    // double. Index UNIQUE (channel_id, start_time) + insertion en REPLACE.
    // Les bases existantes peuvent déjà contenir des doublons : on les purge
    // UNE fois (garde : l'index n'existe pas encore) avant de créer l'index.
    final List<Map<String, Object?>> hasUniq = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_epg_uniq'",
    );
    if (hasUniq.isEmpty) {
      await db.execute('''
        DELETE FROM epg_programs WHERE id NOT IN (
          SELECT MIN(id) FROM epg_programs GROUP BY channel_id, start_time
        )
      ''');
      await db.execute('''
        CREATE UNIQUE INDEX idx_epg_uniq
        ON epg_programs(channel_id, start_time)
      ''');
    }
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_epg_start_time
      ON epg_programs(start_time)
    ''');
    // PONT EPG XTREAM : le XMLTV du panel identifie les chaînes par
    // `epg_channel_id` (« TF1.fr ») alors que nos chaînes Xtream sont
    // `xtream-<stream_id>` → sans table de correspondance, AUCUN programme
    // ne matchait (« Programme non disponible » permanent, mismatch vu par
    // la boîte noire). Remplie à l'import Xtream, lue à l'import XMLTV.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS epg_aliases (
        epg_id TEXT PRIMARY KEY,
        channel_id TEXT NOT NULL
      )
    ''');

    _initialized = true;
  }

  // ============================================================
  //  ALIAS EPG (pont epg_channel_id ↔ id de chaîne Xtream)
  // ============================================================

  /// Enregistre les correspondances `epg_channel_id → Channel.id` collectées
  /// pendant un import Xtream (upsert idempotent, par lots).
  Future<void> saveAliases(Map<String, String> aliases) async {
    if (aliases.isEmpty) return;
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    final Batch batch = db.batch();
    for (final MapEntry<String, String> e in aliases.entries) {
      batch.insert(
        'epg_aliases',
        <String, Object?>{'epg_id': e.key, 'channel_id': e.value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Charge tous les alias connus (epg_id → channel_id). Une entrée par
  /// chaîne au maximum → volume borné par la taille du bouquet.
  Future<Map<String, String>> _loadAliases() async {
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows =
        await db.query('epg_aliases', columns: <String>['epg_id', 'channel_id']);
    return <String, String>{
      for (final Map<String, Object?> r in rows)
        r['epg_id'].toString(): r['channel_id'].toString(),
    };
  }

  /// Élargit le filtre du parseur XMLTV aux ids EPG des chaînes connues :
  /// le XMLTV parle en `epg_channel_id`, nos chaînes en `Channel.id` — on
  /// n'accepte un alias QUE si sa chaîne fait partie du filtre demandé
  /// (jamais d'élargissement sauvage). `known == null` = pas de filtre.
  /// Statique et pure → testée sans base.
  @visibleForTesting
  static Set<String>? mergeKnownWithAliases(
    Set<String>? known,
    Map<String, String> aliases,
  ) {
    if (known == null || aliases.isEmpty) return known;
    return <String>{
      ...known,
      for (final MapEntry<String, String> e in aliases.entries)
        if (known.contains(e.value)) e.key,
    };
  }

  /// Range une ligne programme sous l'id de SA chaîne quand `channel_id`
  /// est un alias EPG ; les ids déjà canoniques passent inchangés.
  /// Statique et pure → testée sans base.
  @visibleForTesting
  static Map<String, Object?> remapProgramRow(
    Map<String, Object?> row,
    Map<String, String> aliases,
  ) {
    final String? mapped = aliases[row['channel_id']];
    return mapped == null
        ? row
        : <String, Object?>{...row, 'channel_id': mapped};
  }

  // ============================================================
  //  TÉLÉCHARGEMENT + IMPORT
  // ============================================================

  /// Télécharge un fichier XMLTV depuis [url] (supporte .gz et plain)
  /// et l'insère en base. Optionnellement filtre par les IDs des
  /// chaînes actuellement connues pour économiser stockage et CPU.
  Future<int> downloadAndImport({
    required String url,
    Set<String>? knownChannelIds,
    http.Client? httpClient,
    void Function(int progressBytes)? onProgress,
  }) async {
    if (_syncing) return 0;
    _syncing = true;
    try {
      await initialize();

      // Client IPTV (audit 2026-07-29) : l'URL EPG d'un compte Xtream pointe
      // sur le MÊME panel que le M3U/player_api — qui, eux, passent par
      // createIptvHttpClient() (certificats auto-signés tolérés + DoH). Le
      // client standard faisait échouer la sync EPG sur ces panels.
      final http.Client client = httpClient ?? createIptvHttpClient();
      try {
        final http.Request req = http.Request('GET', Uri.parse(url));
        // Timeout de connexion/en-têtes : sans lui, un serveur qui accepte la
        // connexion sans répondre gardait `_syncing = true` pour toute la
        // session (plus aucune sync EPG jusqu'au redémarrage).
        final http.StreamedResponse resp = await client
            .send(req)
            .timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) {
          throw Exception('HTTP ${resp.statusCode}');
        }

        // Source de bytes (gzip décompressé si nécessaire). Timeout
        // inter-chunk : un flux qui se fige (serveur mort en cours de
        // transfert) libère la sync au lieu de pendre indéfiniment.
        Stream<List<int>> bytes = resp.stream.timeout(
          const Duration(seconds: 60),
          onTimeout: (EventSink<List<int>> sink) {
            sink.addError(
              TimeoutException('Flux XMLTV figé (60 s sans données)'),
            );
            sink.close();
          },
        );
        final String lower = url.toLowerCase();
        final bool isGzip = lower.endsWith('.gz') ||
            lower.endsWith('.gzip') ||
            (resp.headers['content-encoding']?.toLowerCase() == 'gzip') ||
            (resp.headers['content-type']?.toLowerCase() ?? '')
                .contains('gzip');

        if (isGzip) {
          // Décompression streaming via dart:io
          bytes = bytes.transform<List<int>>(gzip.decoder);
        }

        // Compteur progression simple
        if (onProgress != null) {
          int total = 0;
          bytes = bytes.map<List<int>>((List<int> chunk) {
            total += chunk.length;
            onProgress(total);
            return chunk;
          });
        }

        // On purge d'abord les vieux programmes pour faire de la place
        await purgeStale();

        // PONT EPG : les alias `epg_channel_id → Channel.id` (import Xtream)
        // élargissent le filtre du parseur (le XMLTV parle en epg_channel_id)
        // et chaque programme retenu est RANGÉ sous l'id de SA chaîne — c'est
        // ce remap qui fait enfin matcher lectures (`Channel.id`) et données.
        final Map<String, String> aliases = await _loadAliases();
        final Set<String>? effectiveKnown =
            mergeKnownWithAliases(knownChannelIds, aliases);

        // FLUIDITÉ — le parse XML (décodage UTF-8 + événements + dates)
        // tourne dans un ISOLATE DÉDIÉ : une sync EPG de plusieurs
        // centaines de Mo ne gèle plus une seule frame de l'UI. Seuls
        // les INSERTS SQLite restent ici (sqflite = platform channels,
        // isolate principal obligatoire), servis par lots de 500 déjà
        // convertis en Map par l'isolate.
        final Database db = await PlaylistDatabase.instance.database;
        final int total = await XmltvParser.parseInIsolate(
          bytes,
          knownChannelIds: effectiveKnown,
          onBatch: (List<Map<String, Object?>> rows) async {
            final Batch batch = db.batch();
            for (final Map<String, Object?> row in rows) {
              // Remap alias → id de chaîne (cf. commentaire ci-dessus). Les
              // ids déjà canoniques (M3U tvg-id) passent inchangés.
              batch.insert(
                'epg_programs',
                remapProgramRow(row, aliases),
                // REPLACE + index unique (channel_id, start_time) : une
                // re-sync remplace le programme au lieu de le dupliquer.
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
            await batch.commit(noResult: true);
          },
        );

        if (kDebugMode) {
          debugPrint('[EpgRepository] $total programmes importés');
        }
        // BOÎTE NOIRE (terrain 2026-07-16, « Programme non disponible ») :
        // la sync EPG était totalement muette en release — impossible de
        // distinguer « pas d'URL EPG », « 0 programme (tvg-id qui ne
        // matchent pas) » ou « sync plantée ». `count: 0` avec un `known`
        // élevé pointe un mismatch d'identifiants ; l'absence totale de
        // cet événement pointe une sync jamais lancée ou plantée (voir
        // epg.import_fail côté PlaylistRepository).
        StructuredLogger.instance.info(
          domain: 'epg',
          event: 'epg.import_ok',
          ctx: <String, Object?>{
            'host': Uri.tryParse(url)?.host,
            'count': total,
            'known': knownChannelIds?.length,
          },
        );

        _nowCache.clear(); // nouvelles données EPG → cache mémoire périmé
        if (!_changesController.isClosed) {
          _changesController.add(null);
        }
        return total;
      } finally {
        if (httpClient == null) client.close();
      }
    } finally {
      _syncing = false;
    }
  }

  /// Supprime tous les programmes terminés depuis plus d'une heure.
  /// Garde 1h dans le passé pour le catch-up immédiat.
  Future<int> purgeStale() async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    final int cutoff = DateTime.now()
        .subtract(const Duration(hours: 1))
        .millisecondsSinceEpoch;
    return db.delete(
      'epg_programs',
      where: 'stop_time < ?',
      whereArgs: <Object>[cutoff],
    );
  }

  /// Vide complètement la base EPG.
  Future<void> clearAll() async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    await db.delete('epg_programs');
    _nowCache.clear();
    if (!_changesController.isClosed) _changesController.add(null);
  }

  // ============================================================
  //  LECTURE
  // ============================================================

  /// Programme actuellement diffusé sur cette chaîne (null si rien).
  /// Sert d'abord le CACHE MÉMOIRE (60 s) → défiler une liste ne re-tape
  /// pas la base pour des chaînes déjà vues (fluidité).
  Future<EpgProgram?> currentProgram(String channelId) async {
    final ({DateTime at, EpgProgram? prog})? hit = _nowCache[channelId];
    if (hit != null && DateTime.now().difference(hit.at) <= _nowTtl) {
      return hit.prog;
    }
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final List<Map<String, Object?>> rows = await db.query(
      'epg_programs',
      where: 'channel_id = ? AND start_time <= ? AND stop_time > ?',
      whereArgs: <Object>[channelId, now, now],
      limit: 1,
    );
    final EpgProgram? prog =
        rows.isEmpty ? null : EpgProgram.fromMap(rows.first);
    _rememberNow(channelId, prog);
    return prog;
  }

  /// Programme suivant après celui en cours (null si rien programmé).
  Future<EpgProgram?> nextProgram(String channelId) async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final List<Map<String, Object?>> rows = await db.query(
      'epg_programs',
      where: 'channel_id = ? AND start_time > ?',
      whereArgs: <Object>[channelId, now],
      orderBy: 'start_time ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return EpgProgram.fromMap(rows.first);
  }

  /// Programmes d'une chaîne entre deux instants (pour la grille TV).
  Future<List<EpgProgram>> programsBetween(
    String channelId,
    int startMs,
    int endMs,
  ) async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows = await db.query(
      'epg_programs',
      where:
          'channel_id = ? AND stop_time > ? AND start_time < ?',
      whereArgs: <Object>[channelId, startMs, endMs],
      orderBy: 'start_time ASC',
    );
    return rows.map(EpgProgram.fromMap).toList(growable: false);
  }

  /// Récupère les programmes d'aujourd'hui pour une chaîne donnée.
  Future<List<EpgProgram>> todayPrograms(String channelId) {
    final DateTime now = DateTime.now();
    final DateTime startOfDay =
        DateTime(now.year, now.month, now.day);
    final DateTime endOfDay = startOfDay.add(const Duration(days: 1));
    return programsBetween(
      channelId,
      startOfDay.millisecondsSinceEpoch,
      endOfDay.millisecondsSinceEpoch,
    );
  }

  // ============================================================
  //  STATS
  // ============================================================

  /// Nombre total de programmes en base (pour l'écran EPG).
  Future<int> totalCount() async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows =
        await db.rawQuery('SELECT COUNT(*) as c FROM epg_programs');
    return (rows.first['c'] as int?) ?? 0;
  }
}
