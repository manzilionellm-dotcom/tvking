// =========================================================
//  epg_fetch.dart — Télécharge et lit un XMLTV, par lots de rangées SQLite
// =========================================================
//  Partagé par les deux chemins d'import du guide :
//    • dans un ISOLATE (défaut depuis le 4 octobre 2026) : le fil UI ne
//      décode plus 100 Mo de XML pendant que le client découvre ses
//      chaînes — c'est ce qui figeait la box, et la raison pour laquelle le
//      guide Xtream avait été coupé ;
//    • en ligne (repli `zuno.epg.inline_parse`, et tests avec un client
//      HTTP simulé).
//  Aucun accès à la base ici : on rend des rangées prêtes pour
//  `epg_programs`, par lots, à l'appelant.
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/app/repair_flags.dart';
import '../domain/epg_program.dart';
import 'epg_targets.dart';
import 'xmltv_parser.dart';

/// Lit [url] et appelle [onRows] à chaque lot de [batchSize] rangées.
/// Renvoie le nombre total de rangées produites (un programme XMLTV
/// apparié à N chaînes donne N rangées).
///
/// [connectTimeout] borne l'attente des en-têtes, [idleTimeout] le
/// silence entre deux paquets : dépassés, l'appel lève et l'appelant
/// rend son verrou. [knownIds] (M3U) et [idMap] (Xtream) décident quels
/// programmes sont gardés ; voir epg_targets.dart.
Future<int> fetchXmltvRows({
  required String url,
  required http.Client client,
  required Future<void> Function(List<Map<String, Object?>> rows) onRows,
  Set<String>? knownIds,
  Map<String, List<String>>? idMap,
  Duration connectTimeout = const Duration(seconds: 30),
  Duration idleTimeout = const Duration(seconds: 60),
  int batchSize = 500,
  void Function(int bytes)? onProgress,
  bool? gzipByHeader,
}) async {
  final http.Request req = http.Request('GET', Uri.parse(url));
  final http.StreamedResponse resp =
      await client.send(req).timeout(connectTimeout);
  if (resp.statusCode != 200) {
    throw Exception('HTTP ${resp.statusCode}');
  }

  Stream<List<int>> bytes = resp.stream.timeout(
    idleTimeout,
    onTimeout: (EventSink<List<int>> sink) {
      sink.addError(TimeoutException(
          'EPG : aucune donnée reçue depuis ${idleTimeout.inSeconds} s'));
      sink.close();
    },
  );
  // Décompression gzip. Mesuré le 06/10/2026 (boîte noire SHIELD) :
  // « FormatException: Filter error ». Le client HTTP de dart:io décompresse
  // DÉJÀ une réponse `Content-Encoding: gzip` mais laisse l'en-tête visible ;
  // décider d'après l'en-tête ou l'adresse redécompressait du XML en clair.
  // On regarde donc les deux premiers octets reçus (signature gzip 1f 8b),
  // seule vérité sur ce qui arrive (epg_gzip_sniff_test.dart).
  // Repli `zuno.epg.gzip_by_header` : ancienne décision par adresse/en-têtes.
  if (gzipByHeader ?? RepairFlags.epgGzipByHeader) {
    final String lower = url.toLowerCase();
    final bool isGzip = lower.endsWith('.gz') ||
        lower.endsWith('.gzip') ||
        (resp.headers['content-encoding']?.toLowerCase() == 'gzip') ||
        (resp.headers['content-type']?.toLowerCase() ?? '').contains('gzip');
    if (isGzip) bytes = bytes.transform<List<int>>(gzip.decoder);
  } else {
    bytes = sniffGzip(bytes);
  }

  if (onProgress != null) {
    int total = 0;
    bytes = bytes.map<List<int>>((List<int> chunk) {
      total += chunk.length;
      onProgress(total);
      return chunk;
    });
  }

  // Xtream : le XMLTV peut écrire l'identifiant avec une autre casse que
  // le serveur ; on compare normalisé (voir normalizeEpgId).
  final Map<String, List<String>>? map = idMap;
  bool Function(String id)? skip;
  if (map != null) {
    skip = (String id) => !map.containsKey(normalizeEpgId(id));
  } else if (knownIds != null) {
    skip = (String id) => !knownIds.contains(id);
  }

  List<Map<String, Object?>> pending = <Map<String, Object?>>[];
  int total = 0;
  await XmltvParser.parse(
    bytes,
    skipPredicate: skip,
    onProgram: (EpgProgram p) async {
      final List<String> targets = map == null
          ? expandEpgTargets(p.channelId, null)
          : expandEpgTargets(normalizeEpgId(p.channelId), map);
      for (final String channelId in targets) {
        final Map<String, Object?> row = p.toMap();
        row['channel_id'] = channelId;
        pending.add(row);
        total++;
      }
      if (pending.length >= batchSize) {
        final List<Map<String, Object?>> rows = pending;
        pending = <Map<String, Object?>>[];
        await onRows(rows);
      }
    },
  );
  if (pending.isNotEmpty) await onRows(pending);
  return total;
}

/// Rend [source] décompressé s'il commence par la signature gzip (1f 8b),
/// tel quel sinon. Les octets lus pour décider (même coupés entre deux
/// paquets) sont rendus au décodeur : rien n'est perdu.
Stream<List<int>> sniffGzip(Stream<List<int>> source) async* {
  final List<int> head = <int>[];
  final StreamIterator<List<int>> it = StreamIterator<List<int>>(source);
  try {
    while (head.length < 2 && await it.moveNext()) {
      head.addAll(it.current);
    }
    final bool isGzip = head.length >= 2 && head[0] == 0x1f && head[1] == 0x8b;
    Stream<List<int>> rest() async* {
      if (head.isNotEmpty) yield head;
      while (await it.moveNext()) {
        yield it.current;
      }
    }

    yield* isGzip ? rest().transform<List<int>>(gzip.decoder) : rest();
  } finally {
    await it.cancel();
  }
}
