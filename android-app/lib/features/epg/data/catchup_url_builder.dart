// =========================================================
//  catchup_url_builder.dart — Génération d'URLs catch-up
// =========================================================
//  Couvre les 3 conventions principales du marché IPTV :
//
//  1. Xtream Codes (stream URL contient `/live/...`)
//     → on remplace par `/timeshift/{minutes}/{start}/...`
//     → format start : "YYYY-MM-DD:HH-MM"
//
//  2. M3U avec catchup-source explicite (template)
//     → on substitue ${start}, ${end}, ${duration}, ${utc},
//       ${lutc}, ${timestamp}, ${offset}
//
//  3. M3U "default" sans template
//     → on append ?utc=<start>&lutc=<now> à la stream URL
//
//  Si rien ne match → retourne null (catch-up non disponible).
// =========================================================

import '../../channels/domain/channel.dart';
import '../../epg/domain/epg_program.dart';

abstract final class CatchupUrlBuilder {
  /// Construit l'URL catch-up pour une chaîne et un programme passé.
  /// Retourne null si la chaîne n'a pas l'air de supporter le catch-up.
  static String? build({
    required Channel channel,
    required EpgProgram program,
  }) {
    if (!channel.catchupSupported && channel.catchupSource == null) {
      // Tentons quand même Xtream — beaucoup de chaînes Xtream
      // supportent le timeshift sans le déclarer.
      final String? xt = _tryXtream(channel, program);
      if (xt != null) return xt;
      return null;
    }

    // 1. Template explicite catchup-source
    if (channel.catchupSource != null &&
        channel.catchupSource!.isNotEmpty) {
      return _fillTemplate(channel.catchupSource!, program);
    }

    // 2. Xtream auto-detect
    final String? xtream = _tryXtream(channel, program);
    if (xtream != null) return xtream;

    // 3. M3U "default" → append params
    return _appendDefaultParams(channel.streamUrl, program);
  }

  // ----- Helpers -----

  static String _fillTemplate(String template, EpgProgram p) {
    final int startSec = p.startTime ~/ 1000;
    final int endSec = p.stopTime ~/ 1000;
    final int duration = endSec - startSec;
    final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final int offset = nowSec - startSec;
    final DateTime start = p.startDateTime.toUtc();

    final String yyyyMMddHHmmss =
        '${start.year.toString().padLeft(4, '0')}'
        '${start.month.toString().padLeft(2, '0')}'
        '${start.day.toString().padLeft(2, '0')}T'
        '${start.hour.toString().padLeft(2, '0')}'
        '${start.minute.toString().padLeft(2, '0')}'
        '${start.second.toString().padLeft(2, '0')}';

    return template
        .replaceAll(r'${start}', startSec.toString())
        .replaceAll(r'${end}', endSec.toString())
        .replaceAll(r'${duration}', duration.toString())
        .replaceAll(r'${utc}', startSec.toString())
        .replaceAll(r'${lutc}', nowSec.toString())
        .replaceAll(r'${timestamp}', nowSec.toString())
        .replaceAll(r'${offset}', offset.toString())
        .replaceAll(r'${Y}', start.year.toString())
        .replaceAll(r'${m}', start.month.toString().padLeft(2, '0'))
        .replaceAll(r'${d}', start.day.toString().padLeft(2, '0'))
        .replaceAll(r'${H}', start.hour.toString().padLeft(2, '0'))
        .replaceAll(r'${M}', start.minute.toString().padLeft(2, '0'))
        .replaceAll(r'${S}', start.second.toString().padLeft(2, '0'))
        .replaceAll(r'${start-time}', yyyyMMddHHmmss);
  }

  /// Détection automatique Xtream Codes :
  ///   http://server:port/USERNAME/PASSWORD/STREAMID.ts
  ///   http://server:port/live/USERNAME/PASSWORD/STREAMID.ts
  ///   http://server:port/USERNAME/PASSWORD/STREAMID.m3u8
  /// → on transforme en
  ///   http://server:port/timeshift/USERNAME/PASSWORD/MINUTES/YYYY-MM-DD:HH-MM/STREAMID.ts
  static String? _tryXtream(Channel channel, EpgProgram p) {
    final Uri uri = Uri.tryParse(channel.streamUrl) ?? Uri();
    if (uri.host.isEmpty) return null;

    final List<String> seg = uri.pathSegments;
    if (seg.length < 3) return null;

    // On cherche soit "/USER/PASS/STREAM" soit "/live/USER/PASS/STREAM"
    String? user;
    String? pass;
    String? streamWithExt;
    int? userIdx;

    if (seg[0] == 'live' && seg.length >= 4) {
      user = seg[1];
      pass = seg[2];
      streamWithExt = seg[3];
      userIdx = 1;
    } else {
      user = seg[0];
      pass = seg[1];
      streamWithExt = seg[2];
      userIdx = 0;
    }

    // Sanity check : le dernier segment doit être un id numérique + ext
    final RegExp streamRe = RegExp(r'^(\d+)(\.\w+)?$');
    final Match? m = streamRe.firstMatch(streamWithExt);
    if (m == null) return null;
    final String streamId = m.group(1)!;

    final int minutes = ((p.stopTime - p.startTime) / 60000).round();
    final DateTime start = p.startDateTime;
    final String formatted =
        '${start.year.toString().padLeft(4, '0')}'
        '-${start.month.toString().padLeft(2, '0')}'
        '-${start.day.toString().padLeft(2, '0')}'
        ':${start.hour.toString().padLeft(2, '0')}'
        '-${start.minute.toString().padLeft(2, '0')}';

    final List<String> newSegs = <String>[
      ...seg.take(userIdx),
      'timeshift',
      user,
      pass,
      minutes.toString(),
      formatted,
      '$streamId.ts',
    ];
    final Uri result = uri.replace(pathSegments: newSegs);
    return result.toString();
  }

  static String _appendDefaultParams(String streamUrl, EpgProgram p) {
    final int start = p.startTime ~/ 1000;
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final String sep = streamUrl.contains('?') ? '&' : '?';
    return '$streamUrl${sep}utc=$start&lutc=$now';
  }
}
