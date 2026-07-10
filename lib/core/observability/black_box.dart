// =========================================================
//  black_box.dart — Boîte noire de l'application (« flight recorder »)
// =========================================================
//  Demande produit (2026-07-09) : un enregistreur qui capture TOUT ce
//  qui se passe dans l'app et sait dire, de A à Z, ce qui a mal tourné
//  — même après un crash ou un redémarrage.
//
//  Trois responsabilités, trois couches :
//
//    1. CAPTURE — la boîte noire est un SINK du StructuredLogger (tous
//       les domaines : cast, player, xtream, relay, net…) et un
//       AUDITEUR du CrashReporting (erreurs Flutter, erreurs async non
//       rattrapées, crashs fatals). Zéro appel à instrumenter dans le
//       code métier : tout ce qui est déjà loggué est capturé.
//
//    2. PERSISTANCE — anneau mémoire (consultation immédiate) + fichier
//       JSONL sur disque avec rotation (2 générations). Le fichier
//       SURVIT au crash et au redémarrage : au boot suivant, la boîte
//       noire contient encore les dernières secondes avant la mort de
//       l'app — c'est LE point qui manquait (le ring CrashReporting et
//       le journal vivaient en RAM).
//
//    3. ANALYSE — `analyze()` passe les enregistrements au crible de
//       SIGNATURES DE PANNES CONNUES (proxy cloud bloqué 456, relais
//       upstream mort, LOAD Cast rejeté, crashs répétés, mémoire…) et
//       produit des constats lisibles par un humain, triés par
//       gravité. `buildReport()` assemble le tout en un bloc texte
//       collable dans un ticket / un chat.
//
//  Règles de survie (comme le logger) : AUCUNE exception ne sort d'ici,
//  aucun await sur le chemin d'écriture des événements (buffer + flush
//  périodique), et si le disque est indisponible la boîte noire
//  continue en mémoire seule.
// =========================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../crash/crash_reporting.dart';
import 'structured_logger.dart';

/// Un constat produit par l'analyse automatique.
class BlackBoxFinding {
  const BlackBoxFinding({
    required this.severity,
    required this.title,
    required this.detail,
    required this.occurrences,
  });

  /// 'critique' | 'majeur' | 'info'
  final String severity;
  final String title;
  final String detail;
  final int occurrences;

  @override
  String toString() =>
      '[$severity] $title (×$occurrences) — $detail';
}

class BlackBox {
  BlackBox._();
  static final BlackBox instance = BlackBox._();

  /// Anneau mémoire : assez profond pour couvrir plusieurs sessions de
  /// cast/lecture, assez petit pour être négligeable en RAM (~200 Ko).
  static const int kMaxRingEntries = 800;

  /// Rotation disque : au-delà, le fichier courant devient la
  /// génération .1 (l'ancienne .1 est écrasée) → ~2 Mo au pire.
  static const int kMaxFileBytes = 1024 * 1024;

  /// Flush groupé : les événements sont bufferisés puis écrits par
  /// paquet — pas d'I/O disque sur le chemin chaud du logger.
  static const Duration kFlushEvery = Duration(seconds: 3);

  final List<String> _ring = <String>[];
  final StringBuffer _pendingWrites = StringBuffer();
  Directory? _dir;
  File? _file;
  Timer? _flushTimer;
  bool _initialized = false;

  /// Hooks logger/crash posés une seule fois par process (pas d'API de
  /// retrait côté logger — cf. MINEUR 4 de la revue 2026-07-09).
  bool _hooksAttached = false;

  /// Lignes de la session PRÉCÉDENTE retrouvées sur disque au boot
  /// (la fin du fichier). Non vide après un crash = or massif.
  List<String> previousSessionTail = <String>[];

  bool get isInitialized => _initialized;

  /// À appeler UNE fois, tôt dans le boot (guarded_main). [directory]
  /// injectable pour les tests ; par défaut le dossier support de
  /// l'app est résolu par l'appelant (path_provider vit côté Flutter,
  /// on ne l'importe pas ici pour rester testable en pur Dart).
  Future<void> initialize({required Directory directory}) async {
    if (_initialized) return;
    _initialized = true;
    final bool firstAttach = !_hooksAttached;
    try {
      _dir = Directory('${directory.path}/black_box');
      await _dir!.create(recursive: true);
      _file = File('${_dir!.path}/blackbox.jsonl');
      // Queue de la session précédente (post-mortem de crash).
      if (await _file!.exists()) {
        try {
          final List<String> lines = await _file!.readAsLines();
          previousSessionTail = lines.length <= 120
              ? lines
              : lines.sublist(lines.length - 120);
        } on Exception {
          previousSessionTail = <String>[];
        }
      }
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('[BlackBox] disque indisponible: $e');
      _file = null; // mode mémoire seule
    }

    // ---- CAPTURE ----
    // Revue 2026-07-09 (MINEUR 4) : ni le logger ni le CrashReporting
    // n'ont de « removeSink » — on ne s'abonne qu'UNE fois par process,
    // même si initialize() est rappelé après dispose() (tests).
    if (firstAttach) {
      _hooksAttached = true;
      // 1. Tout ce qui passe par le StructuredLogger (déjà sérialisé).
      StructuredLogger.instance.addSink(_recordRaw);
      // 2. Toutes les erreurs signalées au CrashReporting (filet global
      //    FlutterError / PlatformDispatcher / runZonedGuarded compris).
      CrashReporting.instance.addLocalListener(
        (String line, {required bool fatal}) {
          _recordRaw(jsonEncode(<String, Object?>{
            'ts': DateTime.now().toUtc().toIso8601String(),
            'lvl': fatal ? 'fatal' : 'err',
            'domain': 'crash',
            'event': fatal ? 'fatal_error' : 'error',
            'ctx': <String, Object?>{'message': line},
          }));
        },
      );
    }

    _recordRaw(jsonEncode(<String, Object?>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'lvl': 'info',
      'domain': 'lifecycle',
      'event': 'boot',
      'ctx': <String, Object?>{
        'previousSessionLines': previousSessionTail.length,
      },
    }));

    _flushTimer = Timer.periodic(kFlushEvery, (_) => _flushToDisk());
  }

  /// Enregistre une ligne (JSON de préférence). JAMAIS bloquant.
  void _recordRaw(String line) {
    if (!_initialized) return; // post-dispose (tests) : on ignore
    _ring.add(line);
    if (_ring.length > kMaxRingEntries) _ring.removeAt(0);
    // Revue 2026-07-09 (MAJEUR 3) : en mode « mémoire seule » (disque
    // indisponible) le buffer d'écriture n'était jamais vidé →
    // croissance illimitée sur une longue session. Sans fichier, on
    // n'accumule tout simplement pas.
    if (_file != null) _pendingWrites.writeln(line);
  }

  /// Événement applicatif direct (pour du code qui ne passe pas par le
  /// StructuredLogger).
  void record({
    required String domain,
    required String event,
    String level = 'info',
    Map<String, Object?> ctx = const <String, Object?>{},
  }) {
    try {
      _recordRaw(jsonEncode(<String, Object?>{
        'ts': DateTime.now().toUtc().toIso8601String(),
        'lvl': level,
        'domain': domain,
        'event': event,
        if (ctx.isNotEmpty) 'ctx': ctx,
      }));
    } on Object {
      // une boîte noire ne fait JAMAIS planter l'avion
    }
  }

  Future<void> _flushToDisk() async {
    if (_file == null || _pendingWrites.isEmpty) return;
    final String chunk = _pendingWrites.toString();
    _pendingWrites.clear();
    try {
      await _file!.writeAsString(chunk, mode: FileMode.append, flush: true);
      if (await _file!.length() > kMaxFileBytes) {
        final File gen1 = File('${_dir!.path}/blackbox.1.jsonl');
        try {
          if (await gen1.exists()) await gen1.delete();
        } on Exception {/* best effort */}
        await _file!.rename(gen1.path);
        _file = File('${_dir!.path}/blackbox.jsonl');
      }
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('[BlackBox] flush: $e');
    }
  }

  /// Force l'écriture (à appeler avant un export).
  @visibleForTesting
  Future<void> flushNow() => _flushToDisk();

  /// Les [n] derniers enregistrements (récent → ancien).
  List<String> recent([int n = 120]) {
    final List<String> out = _ring.length <= n
        ? List<String>.of(_ring)
        : _ring.sublist(_ring.length - n);
    return out.reversed.toList(growable: false);
  }

  // ============================================================
  //  ANALYSE — signatures de pannes connues
  // ============================================================

  /// Passe l'anneau au crible et rend les constats triés (critique →
  /// info). Chaque règle est une paire (prédicat sur l'entrée JSON,
  /// constat) ; les occurrences sont agrégées.
  List<BlackBoxFinding> analyze() {
    final List<Map<String, Object?>> entries = <Map<String, Object?>>[];
    for (final String line in _ring) {
      try {
        final Object? decoded = jsonDecode(line);
        if (decoded is Map<String, dynamic>) entries.add(decoded);
      } on Object {
        // ligne non-JSON (fallback texte du logger) — ignorée par les
        // règles, mais toujours présente dans le journal exporté.
      }
    }

    final List<BlackBoxFinding> findings = <BlackBoxFinding>[];
    void addIf(
      int count, {
      required String severity,
      required String title,
      required String detail,
    }) {
      if (count > 0) {
        findings.add(BlackBoxFinding(
          severity: severity,
          title: title,
          detail: detail,
          occurrences: count,
        ));
      }
    }

    int countWhere(bool Function(Map<String, Object?> e) test) {
      int n = 0;
      for (final Map<String, Object?> e in entries) {
        try {
          if (test(e)) n++;
        } on Object {
          // une règle cassée n'invalide pas l'analyse
        }
      }
      return n;
    }

    String ctxStr(Map<String, Object?> e) {
      final Object? c = e['ctx'];
      return c == null ? '' : c.toString();
    }

    // --- crashs / erreurs ---
    addIf(
      countWhere((Map<String, Object?> e) => e['lvl'] == 'fatal'),
      severity: 'critique',
      title: 'Crash de l\'application',
      detail: 'Une erreur FATALE a été enregistrée — la queue de la '
          'session précédente est conservée dans la boîte noire.',
    );
    addIf(
      countWhere((Map<String, Object?> e) =>
          e['domain'] == 'crash' && e['lvl'] == 'err'),
      severity: 'majeur',
      title: 'Erreurs non rattrapées',
      detail: 'Des exceptions ont atteint le filet global (FlutterError / '
          'zone). Voir les entrées domain=crash.',
    );

    // --- cast : proxy cloud bloqué par le fournisseur ---
    addIf(
      countWhere((Map<String, Object?> e) =>
          e['event'] == 'proxy.verify' &&
          RegExp(r'upstream: (4\d\d|5\d\d)').hasMatch(ctxStr(e))),
      severity: 'majeur',
      title: 'Proxy cloud refusé par le fournisseur IPTV',
      detail: 'Le serveur IPTV rejette l\'IP datacenter du proxy '
          '(/cast-proxy). L\'app bascule sur le relais du téléphone — '
          'comportement attendu, mais le téléphone doit rester allumé.',
    );
    addIf(
      countWhere((Map<String, Object?> e) =>
          e['event'] == 'proxy.blocked_fallback_relay' ||
          e['event'] == 'proxy.memo_blocked_skip'),
      severity: 'info',
      title: 'Bascule proxy → relais téléphone',
      detail: 'Le chemin prioritaire /cast-proxy était indisponible ; le '
          'relais HLS local a pris le relais (memo_blocked_skip = verdict '
          '« bloqué » mémorisé, bascule immédiate sans re-tester).',
    );

    // --- cast : la TV a rejeté la lecture ---
    addIf(
      countWhere((Map<String, Object?> e) =>
          e['domain'] == 'cast' &&
          (e['event'] == 'load_failed' ||
              ctxStr(e).contains('load_failed'))),
      severity: 'majeur',
      title: 'Commande de lecture rejetée par la TV',
      detail: 'LOAD refusé par le récepteur Cast — flux injoignable '
          'depuis la TV ou récepteur indisponible.',
    );

    // --- relais HLS : upstream mort ---
    addIf(
      countWhere((Map<String, Object?> e) =>
          ctxStr(e).contains('upstream KO') ||
          (e['domain'] == 'cast' && ctxStr(e).contains('reconnexions épuisées'))),
      severity: 'majeur',
      title: 'Flux IPTV coupé pendant le relais',
      detail: 'Le serveur IPTV a cessé de répondre au relais du téléphone '
          'malgré les reconnexions (token expiré ? chaîne morte ?).',
    );

    // --- mémoire ---
    addIf(
      countWhere((Map<String, Object?> e) =>
          e['domain'] == 'mem' ||
          ctxStr(e).contains('lowmemory') ||
          ctxStr(e).contains('OutOfMemory')),
      severity: 'info',
      title: 'Pression mémoire détectée',
      detail: 'Des fils d\'Ariane mémoire ont été posés — utile si l\'app '
          'a été tuée par Android (appareil à faible RAM).',
    );

    // --- agrégat générique : domaines les plus bruyants en warn/err ---
    final Map<String, int> noisy = <String, int>{};
    for (final Map<String, Object?> e in entries) {
      if (e['lvl'] == 'warn' || e['lvl'] == 'err') {
        final String d = '${e['domain']}';
        noisy[d] = (noisy[d] ?? 0) + 1;
      }
    }
    noisy.forEach((String domain, int n) {
      if (n >= 5) {
        findings.add(BlackBoxFinding(
          severity: 'info',
          title: 'Domaine bruyant : $domain',
          detail: '$n avertissements/erreurs enregistrés dans « $domain » '
              'sur la fenêtre de la boîte noire.',
          occurrences: n,
        ));
      }
    });

    const Map<String, int> rank = <String, int>{
      'critique': 0,
      'majeur': 1,
      'info': 2,
    };
    findings.sort((BlackBoxFinding a, BlackBoxFinding b) =>
        (rank[a.severity] ?? 3).compareTo(rank[b.severity] ?? 3));
    return findings;
  }

  /// Rapport texte complet, collable tel quel : constats d'analyse,
  /// journal récent, et queue de la session précédente si elle existe
  /// (post-mortem de crash).
  String buildReport({int journalLines = 120}) {
    final StringBuffer b = StringBuffer()
      ..writeln('=== BOÎTE NOIRE — 7 MOTION ===')
      ..writeln('Généré : ${DateTime.now().toIso8601String()}')
      ..writeln();
    final List<BlackBoxFinding> findings = analyze();
    b.writeln('--- Constats automatiques (${findings.length}) ---');
    if (findings.isEmpty) {
      b.writeln('Aucune anomalie connue détectée sur la fenêtre enregistrée.');
    } else {
      for (final BlackBoxFinding f in findings) {
        b.writeln(f.toString());
      }
    }
    b
      ..writeln()
      ..writeln('--- Journal boîte noire (récent → ancien) ---');
    for (final String line in recent(journalLines)) {
      b.writeln(line);
    }
    if (previousSessionTail.isNotEmpty) {
      b
        ..writeln()
        ..writeln('--- Session PRÉCÉDENTE (fin de fichier au boot — '
            'post-mortem) ---');
      for (final String line in previousSessionTail.reversed) {
        b.writeln(line);
      }
    }
    return b.toString();
  }

  /// Arrêt propre (tests / fin de vie). L'app réelle ne l'appelle pas :
  /// la boîte noire vit aussi longtemps que le process.
  @visibleForTesting
  Future<void> dispose() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flushToDisk();
    _initialized = false;
    _pendingWrites.clear();
    _ring.clear();
    previousSessionTail = <String>[];
  }
}
