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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/observability/structured_logger.dart';
import '../../playlists/data/playlist_database.dart';
import '../domain/epg_program.dart';
import 'epg_alias_index.dart';
import 'epg_id.dart';
import 'epg_import_stats.dart';
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

  /// Dernier rapport d'import (mémoire). La boîte noire le relit aussi
  /// depuis SharedPreferences après un reboot.
  EpgImportReport? _lastImportReport;
  int _lastEmptyEpgIdCount = 0;

  static const String _kReportPrefsKey = 'epg.last_import_report';

  /// Rapport de la dernière sync XMLTV (null = jamais mesurée).
  EpgImportReport? get lastImportReport => _lastImportReport;

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
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_epg_start_time
      ON epg_programs(start_time)
    ''');
    // PONT EPG XTREAM : le XMLTV du panel identifie les chaînes par
    // `epg_channel_id` (« TF1.fr ») alors que nos chaînes Xtream sont
    // `xtream-<stream_id>` → sans table de correspondance, AUCUN programme
    // ne matchait (« Programme non disponible » permanent, mismatch vu par
    // la boîte noire). Remplie à l'import Xtream, lue à l'import XMLTV.
    //
    // Vague 4 : PK composite (epg_id, channel_id) — UN programme XMLTV
    // va sur TOUTES les variantes (TF1 HD + TF1 FHD), plus de
    // last-write-wins 1:1. epg_id stocké NORMALISÉ (cf. EpgId).
    await _ensureAliasTable(db);
    // Dédup : UNIQUE(channel_id, start_time) pour que les compteurs
    // d'import ne mentent plus (re-sync ≠ explosion de doublons).
    await _ensureProgramDedup(db);

    _initialized = true;
    await _loadPersistedReport();
  }

  // ============================================================
  //  Schéma alias + dédup (migrations IDEMPOTENTES)
  // ============================================================

  /// Table `epg_aliases` : PK composite, epg_id normalisé.
  /// Les bases Vague 1–3 avaient `epg_id TEXT PRIMARY KEY` (1:1) :
  /// on recopie en normalisant, puis on bascule.
  Future<void> _ensureAliasTable(Database db) async {
    final List<Map<String, Object?>> master = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='epg_aliases'",
    );
    if (master.isEmpty) {
      await db.execute('''
        CREATE TABLE epg_aliases (
          epg_id TEXT NOT NULL,
          channel_id TEXT NOT NULL,
          PRIMARY KEY (epg_id, channel_id)
        )
      ''');
      return;
    }
    final String sql = (master.first['sql'] as String?) ?? '';
    final bool composite = sql.contains('PRIMARY KEY (epg_id, channel_id)') ||
        sql.contains('PRIMARY KEY(epg_id, channel_id)');
    if (composite) return;

    // Ancien schéma 1:1 → on bascule. DELETE+INSERT plutôt que
    // d'empiler deux tables : volume = taille du bouquet, pas du XMLTV.
    await db.execute('''
      CREATE TABLE epg_aliases_v2 (
        epg_id TEXT NOT NULL,
        channel_id TEXT NOT NULL,
        PRIMARY KEY (epg_id, channel_id)
      )
    ''');
    final List<Map<String, Object?>> rows = await db.query('epg_aliases');
    final Batch batch = db.batch();
    for (final Map<String, Object?> r in rows) {
      final String norm = EpgId.normalize(r['epg_id']?.toString() ?? '');
      final String ch = (r['channel_id']?.toString() ?? '').trim();
      if (norm.isEmpty || ch.isEmpty) continue;
      batch.insert(
        'epg_aliases_v2',
        <String, Object?>{'epg_id': norm, 'channel_id': ch},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
    await db.execute('DROP TABLE epg_aliases');
    await db.execute('ALTER TABLE epg_aliases_v2 RENAME TO epg_aliases');
  }

  /// UNIQUE(channel_id, start_time) : un re-import ne double plus
  /// les lignes (compteurs menteurs). On déduplique UNE FOIS les
  /// bases déjà polluées, sinon CREATE UNIQUE échoue — pas un
  /// DELETE global à chaque boot (Firestick 1 Go).
  Future<void> _ensureProgramDedup(Database db) async {
    final List<Map<String, Object?>> idx = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type='index' AND name='idx_epg_channel_time'",
    );
    final String sql =
        idx.isEmpty ? '' : ((idx.first['sql'] as String?) ?? '');
    if (sql.toUpperCase().contains('UNIQUE')) return;

    await db.execute('''
      DELETE FROM epg_programs WHERE rowid NOT IN (
        SELECT MIN(rowid) FROM epg_programs GROUP BY channel_id, start_time
      )
    ''');
    await db.execute('DROP INDEX IF EXISTS idx_epg_channel_time');
    await db.execute('''
      CREATE UNIQUE INDEX idx_epg_channel_time
      ON epg_programs(channel_id, start_time)
    ''');
  }

  // ============================================================
  //  ALIAS EPG (pont epg_channel_id ↔ ids de chaînes, 1:N)
  // ============================================================

  /// Enregistre les correspondances collectées pendant un import
  /// Xtream / M3U (upsert idempotent, par lots). 1:N : un même
  /// epg_id peut viser plusieurs Channel.id.
  Future<void> saveAliases(
    Map<String, List<String>> aliases, {
    int emptyEpgIdCount = 0,
  }) async {
    final EpgAliasIndex idx = EpgAliasIndex.fromMap(aliases);
    idx.emptyEpgIdCount = emptyEpgIdCount;
    await saveAliasIndex(idx);
  }

  /// Variante index (appelée par le resync : on reconstruit depuis
  /// la colonne `channels.epg_channel_id` SANS re-télécharger le
  /// bouquet — pas 900 get_short_epg, pas de get_live_streams).
  Future<void> saveAliasIndex(EpgAliasIndex index) async {
    _lastEmptyEpgIdCount = index.emptyEpgIdCount;
    if (index.isEmpty) return;
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    final Batch batch = db.batch();
    for (final MapEntry<String, List<String>> e in index.toMap().entries) {
      for (final String ch in e.value) {
        batch.insert(
          'epg_aliases',
          <String, Object?>{'epg_id': e.key, 'channel_id': ch},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
    await batch.commit(noResult: true);
  }

  /// Charge tous les alias (epg_id déjà normalisé → Channel.id).
  Future<Map<String, List<String>>> _loadAliases() async {
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows =
        await db.query('epg_aliases', columns: <String>['epg_id', 'channel_id']);
    final Map<String, List<String>> out = <String, List<String>>{};
    for (final Map<String, Object?> r in rows) {
      final String epg = r['epg_id'].toString();
      final String ch = r['channel_id'].toString();
      out.putIfAbsent(epg, () => <String>[]).add(ch);
    }
    return out;
  }

  /// #aliases en table — la boîte noire le lit EN LIVE (pas le log).
  Future<int> aliasCount() async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows =
        await db.rawQuery('SELECT COUNT(*) as c FROM epg_aliases');
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Relit le rapport persisté (reboot → la boîte noire a encore le POURQUOI).
  Future<EpgImportReport?> loadLastImportReport() async {
    if (_lastImportReport != null) return _lastImportReport;
    await _loadPersistedReport();
    return _lastImportReport;
  }

  Future<void> _loadPersistedReport() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_kReportPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) {
        _lastImportReport =
            EpgImportReport.fromMap(Map<String, Object?>.from(decoded));
        _lastEmptyEpgIdCount = _lastImportReport!.emptyEpgChannelIdCount;
      }
    } catch (_) {
      // Best-effort : un JSON corrompu n'empêche pas l'import.
    }
  }

  Future<void> _persistReport(EpgImportReport report) async {
    _lastImportReport = report;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kReportPrefsKey, jsonEncode(report.toMap()));
    } catch (_) {}
  }

  /// Élargit le filtre du parseur XMLTV aux ids EPG des chaînes connues :
  /// le XMLTV parle en `epg_channel_id`, nos chaînes en `Channel.id` — on
  /// n'accepte un alias QUE si sa chaîne fait partie du filtre demandé
  /// (jamais d'élargissement sauvage). `known == null` = pas de filtre.
  ///
  /// Vague 4 : [aliases] est 1:N, et le filtre contient aussi les formes
  /// NORMALISÉES (TF1.fr = tf1). Statique et pure → testée sans base.
  @visibleForTesting
  static Set<String>? mergeKnownWithAliases(
    Set<String>? known,
    Map<String, List<String>> aliases,
  ) {
    return EpgAliasIndex.mergeKnown(known, EpgAliasIndex.fromMap(aliases));
  }

  /// Range une ligne programme sous l'id de SA chaîne quand `channel_id`
  /// est un alias EPG ; les ids déjà canoniques passent inchangés.
  /// 1:1 seulement (premier match) — préférer [remapProgramRows].
  @visibleForTesting
  static Map<String, Object?> remapProgramRow(
    Map<String, Object?> row,
    Map<String, List<String>> aliases,
  ) {
    return remapProgramRows(row, aliases).first;
  }

  /// Un programme XMLTV → une ligne PAR variante Channel (TF1 HD + FHD).
  /// Statique et pure → testée sans base.
  @visibleForTesting
  static List<Map<String, Object?>> remapProgramRows(
    Map<String, Object?> row,
    Map<String, List<String>> aliases,
  ) {
    return EpgAliasIndex.fromMap(aliases).expandRow(row);
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

      final http.Client client = httpClient ?? http.Client();
      try {
        final http.Request req = http.Request('GET', Uri.parse(url));
        final http.StreamedResponse resp = await client.send(req);
        if (resp.statusCode != 200) {
          throw Exception('HTTP ${resp.statusCode}');
        }

        // Source de bytes (gzip décompressé si nécessaire)
        Stream<List<int>> bytes = resp.stream;
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
        //
        // Vague 4 : 1:N + normalisation + self-alias M3U (tvg-id = Channel.id
        // mais « tf1.fr » ≠ « TF1.fr » sans rabotage).
        final Map<String, List<String>> aliases = await _loadAliases();
        final EpgAliasIndex index = EpgAliasIndex.fromMap(aliases);
        if (knownChannelIds != null) {
          index.addSelfAliases(knownChannelIds);
        }
        final Set<String>? effectiveKnown =
            EpgAliasIndex.mergeKnown(knownChannelIds, index);

        // FLUIDITÉ — le parse XML (décodage UTF-8 + événements + dates)
        // tourne dans un ISOLATE DÉDIÉ : une sync EPG de plusieurs
        // centaines de Mo ne gèle plus une seule frame de l'UI. Seuls
        // les INSERTS SQLite restent ici (sqflite = platform channels,
        // isolate principal obligatoire), servis par lots de 500 déjà
        // convertis en Map par l'isolate.
        final Database db = await PlaylistDatabase.instance.database;
        final EpgParseStats parseStats = await XmltvParser.parseInIsolate(
          bytes,
          knownChannelIds: effectiveKnown,
          onBatch: (List<Map<String, Object?>> rows) async {
            final Batch batch = db.batch();
            for (final Map<String, Object?> row in rows) {
              // 1:N : UN programme XMLTV → toutes les variantes Channel.
              // REPLACE sur UNIQUE(channel_id, start_time) : un re-import
              // ne double plus les lignes (compteurs menteurs).
              for (final Map<String, Object?> mapped
                  in index.expandRow(row)) {
                batch.insert(
                  'epg_programs',
                  mapped,
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
              }
            }
            await batch.commit(noResult: true);
          },
        );
        final int total = parseStats.emitted;

        if (kDebugMode) {
          debugPrint('[EpgRepository] $total programmes importés '
              '(${parseStats.xmltvChannelIdsSeen} ids XMLTV, '
              '${parseStats.skippedUnknownId} id inconnu, '
              '${parseStats.skippedOutsideWindow} hors fenêtre)');
        }

        final int covered = await coveredChannelCount();
        final int aliasesInTable = await aliasCount();
        final int knownCount = knownChannelIds?.length ?? 0;
        final String why = explainEpgCoverage(
          aliasCount: aliasesInTable,
          xmltvChannelIdsSeen: parseStats.xmltvChannelIdsSeen,
          retained: parseStats.emitted,
          skippedUnknownId: parseStats.skippedUnknownId,
          skippedOutsideWindow: parseStats.skippedOutsideWindow,
          coveredChannelCount: covered,
          knownChannelCount: knownCount,
          emptyEpgChannelIdCount: _lastEmptyEpgIdCount,
        );
        final EpgImportReport report = EpgImportReport(
          aliasCount: aliasesInTable,
          xmltvChannelIdsSeen: parseStats.xmltvChannelIdsSeen,
          retained: parseStats.emitted,
          skippedUnknownId: parseStats.skippedUnknownId,
          skippedOutsideWindow: parseStats.skippedOutsideWindow,
          skippedInvalid: parseStats.skippedInvalid,
          coveredChannelCount: covered,
          knownChannelCount: knownCount,
          emptyEpgChannelIdCount: _lastEmptyEpgIdCount,
          whyFr: why,
        );
        await _persistReport(report);

        // BOÎTE NOIRE : plus seulement count/known. Le support lit
        // fournisseur vs pont vs filtre dans le même événement.
        StructuredLogger.instance.info(
          domain: 'epg',
          event: 'epg.import_ok',
          ctx: <String, Object?>{
            'host': Uri.tryParse(url)?.host,
            'count': total,
            'known': knownCount,
            'aliases': aliasesInTable,
            'xmltvSeen': parseStats.xmltvChannelIdsSeen,
            'retained': parseStats.emitted,
            'skipUnknown': parseStats.skippedUnknownId,
            'skipWindow': parseStats.skippedOutsideWindow,
            'skipInvalid': parseStats.skippedInvalid,
            'covered': covered,
            'emptyEpgId': _lastEmptyEpgIdCount,
            'why': why,
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

  // ============================================================
  //  RECHERCHE PAR ÉMISSION — « ce qui passe EN CE MOMENT »
  // ============================================================
  //  Demande du propriétaire (05/09/2026) : « je ne sais pas le nom de
  //  la chaîne, mais je sais l'émission qui est en train de passer. Je
  //  tape "info 24" et les chaînes qui la diffusent en direct viennent
  //  dans la recherche. »
  //
  //  C'est l'inverse de tout ce que le guide savait faire : on part du
  //  TITRE et on remonte à la chaîne. Netflix cherche des titres ; une
  //  télé cherche des chaînes ; ici on fait les deux à la fois.
  //
  //  POURQUOI C'EST RAPIDE MÊME AVEC 300 000 PROGRAMMES EN BASE. On ne
  //  cherche pas dans tout le guide : on ne regarde que ce qui est à
  //  l'antenne MAINTENANT (`start_time <= now < stop_time`). L'index
  //  `idx_epg_start_time` réduit d'abord la table à la tranche en cours —
  //  au plus une ligne par chaîne, quelques milliers — et le LIKE sur le
  //  titre ne balaie que celles-là. Sans ce filtre, le LIKE parcourrait
  //  toute la table à chaque frappe.

  /// Programmes diffusés EN CE MOMENT dont le titre contient [query].
  ///
  /// Une même émission passant sur plusieurs chaînes (une chaîne HD et
  /// sa jumelle SD, une rediffusion simultanée) rend une ligne PAR
  /// CHAÎNE : c'est voulu, l'utilisateur choisira laquelle ouvrir.
  Future<List<EpgProgram>> searchAiringNow(String query, {int limit = 40}) async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    return searchAiringNowIn(db, query,
        now: DateTime.now().millisecondsSinceEpoch, limit: limit);
  }

  /// Comme [searchAiringNow], mais à un INSTANT CHOISI.
  ///
  //  POURQUOI (07/09/2026). Le propriétaire regarde l'écran Sport à
  //  21 h 30 ; le match commence à 22 h 00. « Quelle chaîne le montre ? »
  //  ne peut pas se répondre avec « ce qui passe MAINTENANT » : à cet
  //  instant, la chaîne diffuse encore autre chose. Il faut interroger le
  //  guide à l'heure du COUP D'ENVOI.
  //
  //  Le cœur ne change pas d'une ligne : `searchAiringNowIn` prenait déjà
  //  l'instant en paramètre pour être testable. On expose simplement ce
  //  qui existait — aucune deuxième requête à maintenir.
  Future<List<EpgProgram>> searchAiringAt(
    String query, {
    required int atMs,
    int limit = 40,
  }) async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    return searchAiringNowIn(db, query, now: atMs, limit: limit);
  }

  /// Cœur de [searchAiringNow], sur une base fournie — pour être testé sur
  /// une base en mémoire sans passer par le singleton (même découpage que
  /// [remapProgramRow] et [mergeKnownWithAliases]).
  @visibleForTesting
  static Future<List<EpgProgram>> searchAiringNowIn(
    DatabaseExecutor db,
    String query, {
    required int now,
    int limit = 40,
  }) async {
    final String q = query.trim();
    if (q.isEmpty) return const <EpgProgram>[];
    final List<Map<String, Object?>> rows = await db.query(
      'epg_programs',
      // L'ordre des conditions compte pour le planificateur SQLite :
      // start_time d'abord (indexé), le LIKE en dernier.
      where: 'start_time <= ? AND stop_time > ? AND title LIKE ?',
      whereArgs: <Object>[now, now, '%$q%'],
      // Les émissions qui viennent de commencer en premier : ce sont
      // celles qu'on a le plus de chances de vouloir rattraper.
      orderBy: 'start_time DESC',
      limit: limit,
    );
    // Une ligne par chaîne : si le guide contient deux entrées qui se
    // chevauchent pour la même chaîne (données fournisseur imparfaites),
    // on ne l'affiche qu'une fois.
    final Set<String> vues = <String>{};
    final List<EpgProgram> out = <EpgProgram>[];
    for (final Map<String, Object?> r in rows) {
      final EpgProgram p = EpgProgram.fromMap(r);
      if (vues.add(p.channelId)) out.add(p);
    }
    return out;
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

  /// COMBIEN DE CHAÎNES ONT RÉELLEMENT UN GUIDE.
  ///
  /// Ajouté le 10/09/2026, après une question de client : « pourquoi une
  /// seule chaîne affiche le programme ? ». On savait dire combien de
  /// programmes étaient en base — jamais sur combien de chaînes ils
  /// étaient répartis. Or c'est ce second nombre qui répond.
  ///
  /// 200 000 programmes sur 12 chaînes et 200 000 sur 900 chaînes, c'est
  /// le même compteur et deux situations opposées : dans un cas le
  /// fournisseur ne publie de guide que pour une poignée de chaînes, dans
  /// l'autre tout va bien. Sans ce chiffre, le support devait deviner.
  Future<int> coveredChannelCount() async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows = await db
        .rawQuery('SELECT COUNT(DISTINCT channel_id) as c FROM epg_programs');
    return (rows.first['c'] as int?) ?? 0;
  }
}
