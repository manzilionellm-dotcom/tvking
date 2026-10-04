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
  final String lower = url.toLowerCase();
  final bool isGzip = lower.endsWith('.gz') ||
      lower.endsWith('.gzip') ||
      (resp.headers['content-encoding']?.toLowerCase() == 'gzip') ||
      (resp.headers['content-type']?.toLowerCase() ?? '').contains('gzip');
  if (isGzip) bytes = bytes.transform<List<int>>(gzip.decoder);

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
