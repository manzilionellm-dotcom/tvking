// =========================================================
//  structured_logger.dart — Logger structuré non-invasif
// =========================================================
//  Ajout Phase 0 (audit Cast + Recording). Utilitaire ADDITIF :
//  on n'enleve aucun `debugPrint('[Rec] ...')` ni `[Cast]`
//  existant, on ajoute juste un canal complementaire qui emet
//  des evenements typees (avec champs cles=valeur) plus
//  faciles a grep, parser, ou pousser vers un sink distant
//  (Sentry, Cloudflare Worker, fichier local) dans Phase 1+.
//
//  Pourquoi pas un package tier (`logging`, `logger`, `talker`) ?
//    - On veut zero dependance externe : Phase 0 = audit only,
//      pas de nouvelle dep dans pubspec.yaml.
//    - Le format JSON-Lines (1 evenement = 1 ligne JSON) est
//      universel : un sed | jq lit ca trivialement, n'importe
//      quel collector (Sentry, Datadog, fichier rotatif) le mange.
//
//  Forme d'un evenement :
//    {
//      "ts": "2026-05-31T22:14:09.412Z",
//      "lvl": "info",
//      "domain": "rec",            // 'rec' | 'cast' | 'native'
//      "event": "job.start",       // verbe.action canonique
//      "ctx": {                    // champs libres typees
//        "filePath": "/sdcard/.../bfm.ts",
//        "isHls": false,
//        "activeCount": 1
//      }
//    }
//
//  Convention de nommage des events (Phase 0 documente, Phase 1
//  instrumente reellement les call sites) :
//
//    rec.job.start          rec.job.stop        rec.job.auto_stop
//    rec.job.reconnect      rec.job.reconnect_fail
//    rec.svc.start          rec.svc.stop        rec.svc.wakelock
//    cast.discovery.start   cast.discovery.add  cast.discovery.stop
//    cast.session.probe     cast.session.attempt cast.session.success
//    cast.session.failure   cast.session.disconnect
//
//  Niveaux :
//    info  : transition normale du state machine
//    warn  : echec recuperable (retry, fallback)
//    error : echec terminal (abandon, propagation a l'utilisateur)
//
//  Mode d'utilisation :
//    StructuredLogger.instance.info(
//      domain: 'rec',
//      event: 'job.start',
//      ctx: <String, Object?>{'filePath': path, 'isHls': isHls},
//    );
//
//  Par defaut, le sink unique = `debugPrint` (visible dans
//  `flutter logs` / Android Studio Logcat). On garde une API
//  pluggable (`addSink`) pour brancher Phase 1+ un fichier
//  rotatif ou un upload vers un endpoint diagnostic.
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../crash/secret_redactor.dart';

/// Niveau de gravite d'un evenement.
enum LogLevel {
  /// Transition normale (un cast a demarre, un recording reconnecte).
  info,

  /// Echec recuperable (retry, fallback strategy active).
  warn,

  /// Echec terminal (l'utilisateur va voir un message d'erreur).
  error,
}

extension LogLevelShort on LogLevel {
  /// Forme courte pour la sortie JSON (`info` / `warn` / `error`).
  String get short {
    switch (this) {
      case LogLevel.info:
        return 'info';
      case LogLevel.warn:
        return 'warn';
      case LogLevel.error:
        return 'error';
    }
  }
}

/// Signature d'un sink. Recoit le JSON deja serialise (1 ligne).
typedef LogSink = void Function(String jsonLine);

/// Logger singleton. Toutes les APIs sont synchrones et non-bloquantes
/// (les sinks tournent dans le contexte courant). Si un sink throw,
/// on l'avale silencieusement pour ne JAMAIS impacter la logique
/// metier qui appelle le logger.
class StructuredLogger {
  StructuredLogger._();
  static final StructuredLogger instance = StructuredLogger._();

  /// Liste des sinks actifs. Initialement = un sink `debugPrint` qui
  /// route vers Logcat / `flutter logs`.
  final List<LogSink> _sinks = <LogSink>[
    (String line) {
      // debugPrint plutot que print : respecte la convention AGENTS.md
      // et n'est pas strippe en release contrairement a `print`.
      if (kDebugMode) debugPrint(line);
    },
  ];

  /// Ajoute un sink supplementaire (fichier, upload, etc.).
  /// Pas thread-safe mais Flutter est mono-thread sur l'isolate
  /// principal — l'usage normal est de configurer les sinks au boot
  /// puis de ne plus y toucher.
  void addSink(LogSink sink) => _sinks.add(sink);

  /// Vide la liste des sinks (utile pour les tests).
  @visibleForTesting
  void clearSinks() => _sinks.clear();

  void info({
    required String domain,
    required String event,
    Map<String, Object?> ctx = const <String, Object?>{},
  }) =>
      _emit(LogLevel.info, domain, event, ctx);

  void warn({
    required String domain,
    required String event,
    Map<String, Object?> ctx = const <String, Object?>{},
  }) =>
      _emit(LogLevel.warn, domain, event, ctx);

  void error({
    required String domain,
    required String event,
    Map<String, Object?> ctx = const <String, Object?>{},
  }) =>
      _emit(LogLevel.error, domain, event, ctx);

  void _emit(
    LogLevel lvl,
    String domain,
    String event,
    Map<String, Object?> ctx,
  ) {
    // On serialise UNE fois, on diffuse aux N sinks. Si la
    // serialisation echoue (cycle dans ctx, type non-JSON…), on
    // fallback sur une ligne textuelle pour ne PAS perdre l'evenement.
    String line;
    try {
      line = jsonEncode(<String, Object?>{
        'ts': DateTime.now().toUtc().toIso8601String(),
        'lvl': lvl.short,
        'domain': domain,
        'event': event,
        if (ctx.isNotEmpty) 'ctx': ctx,
      });
    } on JsonUnsupportedObjectError {
      line =
          '${DateTime.now().toUtc().toIso8601String()} ${lvl.short} $domain.$event '
          '(ctx non-serialisable: ${ctx.keys.join(",")})';
    }

    // Caviardage AVANT diffusion : beaucoup de call sites passent
    // `e.toString()` (une ClientException embarque l'URI complète, donc
    // les identifiants Xtream de l'abonné) et la boîte noire — sink de ce
    // logger — écrit chaque ligne SUR DISQUE puis dans le rapport collable.
    // Un seul point d'étranglement couvre les 60+ sites existants et tous
    // les futurs. SecretRedactor est idempotent et ne throw jamais.
    line = SecretRedactor.redact(line);

    for (final LogSink sink in _sinks) {
      try {
        sink(line);
      } catch (_) {
        // Un sink defaillant ne doit jamais bloquer les autres ni
        // remonter dans l'appelant.
      }
    }
  }
}
