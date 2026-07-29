// =========================================================
//  xmltv_parser.dart — Parser XMLTV en streaming
// =========================================================
//  Pourquoi streaming : un EPG XMLTV typique fait 100-500 Mo,
//  parfois 1 Go pour les EPG mondiaux. Charger tout en RAM
//  ferait crasher l'app sur la plupart des téléphones.
//
//  On utilise `XmlEventReader` du package `xml` qui lit les
//  événements XML un à un sans construire l'arbre complet.
//
//  Pour chaque <programme> rencontré → on émet un EpgProgram
//  via le callback `onProgram`. L'appelant peut batcher dans
//  SQLite, écarter les programmes périmés, etc.
//
//  Format XMLTV pris en charge :
//    <programme start="20260524180000 +0200"
//               stop ="20260524200000 +0200"
//               channel="canal-plus">
//      <title>...</title>
//      <desc>...</desc>
//      <category>...</category>
//      <icon src="..." />
//    </programme>
// =========================================================

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:xml/xml_events.dart';

import '../domain/epg_program.dart';

/// Configuration envoyée à l'isolate de parsing (tout est « sendable » :
/// SendPort, Set de String, entiers).
class _XmltvIsolateConfig {
  const _XmltvIsolateConfig({
    required this.sendPort,
    required this.knownChannelIds,
    required this.nowMs,
    required this.keepHoursBeforeNow,
    required this.keepHoursAfterNow,
    required this.batchSize,
  });

  final SendPort sendPort;
  final Set<String>? knownChannelIds;
  final int nowMs;
  final int keepHoursBeforeNow;
  final int keepHoursAfterNow;
  final int batchSize;
}

class XmltvParser {
  XmltvParser._();

  /// FLUIDITÉ — Parse XMLTV dans un ISOLATE DÉDIÉ, par lots.
  ///
  /// Pourquoi : `parse()` (décodage UTF-8 + événements XML + parsing de
  /// dates) est du travail 100 % CPU. Exécuté sur l'isolate principal,
  /// une sync EPG de plusieurs centaines de Mo gèle des frames pendant
  /// des secondes (stutter visible pendant qu'on navigue). Ici :
  ///   - le TÉLÉCHARGEMENT (I/O non bloquant) reste sur l'appelant, qui
  ///     pousse les chunks bruts vers l'isolate (protocole SendPort) ;
  ///   - l'isolate parse EN STREAMING (jamais tout le fichier en RAM,
  ///     même bénéfice mémoire que `parse`) et renvoie des LOTS de
  ///     [batchSize] programmes déjà convertis en `Map` prêts pour
  ///     `batch.insert` ;
  ///   - les inserts SQLite restent sur l'isolate appelant via
  ///     [onBatch] — sqflite passe par les platform channels,
  ///     indisponibles dans un isolate secondaire.
  ///
  /// [onBatch] est attendu séquentiellement (jamais deux commits SQLite
  /// entrelacés). Retourne le nombre total de programmes émis.
  static Future<int> parseInIsolate(
    Stream<List<int>> bytes, {
    required Future<void> Function(List<Map<String, Object?>> batch) onBatch,
    Set<String>? knownChannelIds,
    DateTime? now,
    int keepHoursBeforeNow = 1,
    int keepHoursAfterNow = 48,
    int batchSize = 500,
  }) async {
    final ReceivePort fromIsolate = ReceivePort();
    // Ports DÉDIÉS pour la mort de l'isolate. Surtout pas le port de
    // données : un message onError est une List de 2 String et serait
    // pris pour un lot de programmes par le handler `msg is List`.
    // Sans eux, un isolate tué (OOM sur petite box en plein parse de
    // centaines de Mo, erreur fatale hors du try/catch interne) laissait
    // `done` en attente POUR TOUJOURS → le verrou _syncing du
    // EpgRepository restait collé → plus AUCUNE sync EPG jusqu'au
    // redémarrage de l'app (terrain 2026-07-16 : « Programme non
    // disponible » permanent).
    final ReceivePort onIsolateError = ReceivePort();
    final ReceivePort onIsolateExit = ReceivePort();
    final Completer<int> done = Completer<int>();
    final Completer<SendPort> ready = Completer<SendPort>();
    // Les lots s'insèrent DANS L'ORDRE : on chaîne les écritures pour ne
    // jamais entrelacer deux commits, et la fin attend la dernière.
    Future<void> writes = Future<void>.value();

    onIsolateError.listen((Object? e) {
      if (!done.isCompleted) {
        done.completeError(Exception('XMLTV isolate crash: $e'));
      }
    });
    // AUDIT 2026-07-29 : la sortie de l'isolate fait la COURSE avec la
    // chaîne d'écritures SQLite (`writes`). Le chemin nominal est :
    // total reçu → l'isolate retourne (exit part) → le dernier commit
    // SQLite se termine → done.complete. Si l'événement exit est délivré
    // avant la fin du commit (latence DB réelle : quasi systématique),
    // l'ancien code déclarait à tort « terminé avant la fin » et la sync
    // échouait alors que tout s'était bien passé. On n'alerte donc que si
    // l'isolate meurt AVANT d'avoir émis son total (OOM, kill) — c'est le
    // seul cas anormal ; après le total, `writes` pilote la fin.
    bool totalReceived = false;
    onIsolateExit.listen((Object? _) {
      if (!totalReceived && !done.isCompleted) {
        done.completeError(
            Exception('XMLTV isolate terminé avant la fin du parse'));
      }
    });

    final Isolate iso = await Isolate.spawn<_XmltvIsolateConfig>(
      _parseIsolateMain,
      _XmltvIsolateConfig(
        sendPort: fromIsolate.sendPort,
        knownChannelIds: knownChannelIds,
        nowMs: (now ?? DateTime.now()).millisecondsSinceEpoch,
        keepHoursBeforeNow: keepHoursBeforeNow,
        keepHoursAfterNow: keepHoursAfterNow,
        batchSize: batchSize,
      ),
      onError: onIsolateError.sendPort,
      onExit: onIsolateExit.sendPort,
      errorsAreFatal: true,
    );

    final StreamSubscription<Object?> sub =
        fromIsolate.listen((Object? msg) {
      if (msg is SendPort) {
        // Premier message : le port de commande de l'isolate.
        ready.complete(msg);
      } else if (msg is List) {
        // Un lot de programmes (List<Map<String, Object?>>).
        final List<Map<String, Object?>> rows =
            msg.cast<Map<String, Object?>>();
        writes = writes.then((_) => onBatch(rows));
      } else if (msg is int) {
        // Fin normale : total émis — après la dernière écriture.
        totalReceived = true;
        writes.then((_) {
          if (!done.isCompleted) done.complete(msg);
        }).catchError((Object e, StackTrace st) {
          if (!done.isCompleted) done.completeError(e, st);
        });
      } else if (msg is Map && msg.containsKey('error')) {
        if (!done.isCompleted) {
          done.completeError(Exception('XMLTV isolate: ${msg['error']}'));
        }
      }
    });

    try {
      // Bornes dures : une sync EPG ne doit JAMAIS pendre — un blocage
      // silencieux collerait le verrou _syncing du repository. 30 s
      // pour le handshake, 15 min pour un EPG mondial sur box lente.
      final SendPort toIsolate =
          await ready.future.timeout(const Duration(seconds: 30));
      // On pousse les chunks bruts ; `null` = fin du flux.
      await for (final List<int> chunk in bytes) {
        toIsolate.send(chunk);
      }
      toIsolate.send(null);
      return await done.future.timeout(const Duration(minutes: 15));
    } finally {
      await sub.cancel();
      fromIsolate.close();
      onIsolateError.close();
      onIsolateExit.close();
      iso.kill(priority: Isolate.immediate);
    }
  }

  /// Point d'entrée de l'isolate : reconstitue le flux d'octets depuis
  /// le port, délègue à [parse], renvoie des lots puis le total.
  static Future<void> _parseIsolateMain(_XmltvIsolateConfig cfg) async {
    final ReceivePort chunks = ReceivePort();
    cfg.sendPort.send(chunks.sendPort);
    final StreamController<List<int>> bytes = StreamController<List<int>>();
    chunks.listen((Object? msg) {
      if (msg == null) {
        bytes.close();
        chunks.close();
      } else if (msg is List) {
        bytes.add(msg.cast<int>());
      }
    });
    try {
      final Set<String>? known = cfg.knownChannelIds;
      List<Map<String, Object?>> batch = <Map<String, Object?>>[];
      final int total = await parse(
        bytes.stream,
        now: DateTime.fromMillisecondsSinceEpoch(cfg.nowMs),
        keepHoursBeforeNow: cfg.keepHoursBeforeNow,
        keepHoursAfterNow: cfg.keepHoursAfterNow,
        skipPredicate:
            known == null ? null : (String id) => !known.contains(id),
        onProgram: (EpgProgram p) async {
          batch.add(p.toMap());
          if (batch.length >= cfg.batchSize) {
            cfg.sendPort.send(batch);
            batch = <Map<String, Object?>>[];
          }
        },
      );
      if (batch.isNotEmpty) cfg.sendPort.send(batch);
      cfg.sendPort.send(total);
    } on Object catch (e) {
      // Un XML malformé ne doit jamais tuer l'app : l'erreur remonte
      // proprement à l'appelant qui décidera (log + sync ratée).
      cfg.sendPort.send(<String, Object?>{'error': e.toString()});
    }
  }

  /// Parse un Stream<List<int>> (typiquement la réponse HTTP du
  /// téléchargement de l'EPG) et émet les programmes au fil de l'eau.
  ///
  /// - [onProgram] : callback appelé pour chaque programme.
  /// - [now] : référence de temps pour décider quoi garder. Par
  ///   défaut DateTime.now().
  /// - [keepHoursBeforeNow] : combien d'heures de programmes passés
  ///   on garde (utile pour le catch-up). Défaut 1h.
  /// - [keepHoursAfterNow] : combien d'heures futures on garde.
  ///   Défaut 48h (2 jours), suffisant pour la plupart des usages.
  /// - [skipPredicate] : si fourni, retourne true pour les programmes
  ///   à ignorer (par ex. canal absent de la playlist).
  ///
  /// Retourne le nombre total de programmes émis.
  static Future<int> parse(
    Stream<List<int>> bytes, {
    required Future<void> Function(EpgProgram program) onProgram,
    DateTime? now,
    int keepHoursBeforeNow = 1,
    int keepHoursAfterNow = 48,
    bool Function(String channelId)? skipPredicate,
  }) async {
    final DateTime ref = now ?? DateTime.now();
    final int minStop = ref
        .subtract(Duration(hours: keepHoursBeforeNow))
        .millisecondsSinceEpoch;
    final int maxStart =
        ref.add(Duration(hours: keepHoursAfterNow)).millisecondsSinceEpoch;

    int emitted = 0;

    // État courant du parser
    bool insideProgramme = false;
    String? curChannelId;
    int? curStartMs;
    int? curStopMs;
    String? curTitle;
    String? curDesc;
    String? curCategory;
    String? curIconUrl;
    String? activeTag;
    final StringBuffer textBuf = StringBuffer();

    final Stream<List<XmlEvent>> events = bytes
        .transform(utf8.decoder)
        .transform(XmlEventDecoder());

    await for (final List<XmlEvent> chunk in events) {
      for (final XmlEvent event in chunk) {
        if (event is XmlStartElementEvent) {
          final String name = event.localName;
          if (name == 'programme') {
            insideProgramme = true;
            // Reset
            curChannelId = null;
            curStartMs = null;
            curStopMs = null;
            curTitle = null;
            curDesc = null;
            curCategory = null;
            curIconUrl = null;

            for (final XmlEventAttribute attr in event.attributes) {
              switch (attr.localName) {
                case 'channel':
                  curChannelId = attr.value;
                case 'start':
                  curStartMs = _parseXmltvDate(attr.value);
                case 'stop':
                  curStopMs = _parseXmltvDate(attr.value);
              }
            }
          } else if (insideProgramme) {
            activeTag = name;
            textBuf.clear();
            if (name == 'icon') {
              for (final XmlEventAttribute attr in event.attributes) {
                if (attr.localName == 'src') {
                  curIconUrl = attr.value;
                }
              }
            }
          }
        } else if (event is XmlTextEvent) {
          if (insideProgramme && activeTag != null) {
            textBuf.write(event.value);
          }
        } else if (event is XmlCDATAEvent) {
          if (insideProgramme && activeTag != null) {
            textBuf.write(event.value);
          }
        } else if (event is XmlEndElementEvent) {
          final String name = event.localName;
          if (insideProgramme) {
            if (name == 'title') {
              curTitle = textBuf.toString().trim();
            } else if (name == 'desc') {
              curDesc = textBuf.toString().trim();
            } else if (name == 'category') {
              curCategory ??= textBuf.toString().trim();
            } else if (name == 'programme') {
              // Fin d'un programme → on émet si valide
              insideProgramme = false;
              if (curChannelId != null &&
                  curStartMs != null &&
                  curStopMs != null &&
                  curTitle != null &&
                  curTitle.isNotEmpty) {
                final bool skip =
                    skipPredicate != null && skipPredicate(curChannelId);
                final bool inWindow =
                    curStopMs >= minStop && curStartMs <= maxStart;
                if (!skip && inWindow) {
                  final EpgProgram prog = EpgProgram(
                    channelId: curChannelId,
                    startTime: curStartMs,
                    stopTime: curStopMs,
                    title: curTitle,
                    description: curDesc == null || curDesc.isEmpty
                        ? null
                        : curDesc,
                    category: curCategory == null || curCategory.isEmpty
                        ? null
                        : curCategory,
                    iconUrl: curIconUrl,
                  );
                  await onProgram(prog);
                  emitted++;
                }
              }
            }
            activeTag = null;
          }
        }
      }
    }

    if (kDebugMode) {
      debugPrint('[XmltvParser] $emitted programmes ingérés');
    }
    return emitted;
  }

  // ----- Date XMLTV → millisecondes epoch UTC -----

  /// XMLTV utilise le format "yyyyMMddHHmmss +HHMM" (ou "Z" pour UTC).
  /// Exemple : "20260524180000 +0200" = 24 mai 2026, 18:00, GMT+2.
  static int? _parseXmltvDate(String value) {
    final String raw = value.trim();
    if (raw.length < 14) return null;
    final int? y = int.tryParse(raw.substring(0, 4));
    final int? mo = int.tryParse(raw.substring(4, 6));
    final int? d = int.tryParse(raw.substring(6, 8));
    final int? h = int.tryParse(raw.substring(8, 10));
    final int? mi = int.tryParse(raw.substring(10, 12));
    final int? s = int.tryParse(raw.substring(12, 14));
    if (y == null || mo == null || d == null || h == null ||
        mi == null || s == null) {
      return null;
    }

    // Offset éventuel après l'espace
    int offsetMinutes = 0;
    final int spaceIdx = raw.indexOf(' ', 14);
    if (spaceIdx > 0 && raw.length >= spaceIdx + 5) {
      final String tz = raw.substring(spaceIdx + 1);
      if (tz.toUpperCase() == 'Z') {
        offsetMinutes = 0;
      } else if (tz.length >= 5 && (tz[0] == '+' || tz[0] == '-')) {
        final int sign = tz[0] == '-' ? -1 : 1;
        final int? oh = int.tryParse(tz.substring(1, 3));
        final int? om = int.tryParse(tz.substring(3, 5));
        if (oh != null && om != null) {
          offsetMinutes = sign * (oh * 60 + om);
        }
      }
    }

    // Construire en UTC en soustrayant l'offset
    final DateTime asUtc = DateTime.utc(y, mo, d, h, mi, s)
        .subtract(Duration(minutes: offsetMinutes));
    return asUtc.millisecondsSinceEpoch;
  }
}
