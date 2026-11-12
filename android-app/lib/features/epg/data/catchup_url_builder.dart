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
//
//  Corrections du 12/11/2026 (aucun test ne couvrait ce fichier) :
//    - Xtream `/live/USER/PASS/ID` donnait `/live/timeshift/…`, une adresse
//      qui n'existe pas → `/timeshift/…` ;
//    - l'heure Xtream est écrite dans le fuseau DU SERVEUR quand il est
//      connu (XtreamServerClock), plus dans celui de la box ;
//    - les gabarits écrits `{utc}`, `{lutc}`, `{utcend}`, `{duration:60}`…
//      (forme la plus répandue dans les listes M3U) sont reconnus, plus
//      seulement la forme `${…}` ;
//    - un gabarit relatif (`?utc={utc}&lutc={lutc}`) est AJOUTÉ à l'adresse
//      du flux au lieu d'être pris pour une adresse complète.
// =========================================================

import '../../channels/domain/channel.dart';
import '../../epg/domain/epg_program.dart';
import '../../playlists/data/xtream_server_clock.dart';

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
      final String filled = _fillTemplate(channel.catchupSource!, program);
      // Gabarit « append » : seulement des paramètres (`?utc=…` ou `&utc=…`),
      // à coller derrière l'adresse du flux.
      if (filled.startsWith('?') || filled.startsWith('&')) {
        final String base = channel.streamUrl;
        final String sep = base.contains('?') ? '&' : '?';
        return '$base$sep${filled.substring(1)}';
      }
      return filled;
    }

    // 2. Xtream auto-detect
    final String? xtream = _tryXtream(channel, program);
    if (xtream != null) return xtream;

    // 3. M3U "default" → append params
    return _appendDefaultParams(channel.streamUrl, program);
  }

  // ----- Helpers -----

  /// Remplace les variables d'un gabarit catch-up. Les deux écritures du
  /// marché sont acceptées : `${nom}` et `{nom}`. Variables :
  ///   start, utc        → début du programme (secondes epoch)
  ///   end, utcend       → fin du programme
  ///   lutc, now, timestamp → maintenant
  ///   duration, duration:N → durée en secondes (÷ N)
  ///   offset, offset:N  → retard sur le direct en secondes (÷ N)
  ///   Y m d H M S       → date et heure UTC du début
  ///   start-time        → AAAAMMJJTHHMMSS (UTC)
  /// Une variable inconnue est laissée telle quelle.
  static String _fillTemplate(String template, EpgProgram p) {
    final int startSec = p.startTime ~/ 1000;
    final int endSec = p.stopTime ~/ 1000;
    final int duration = endSec - startSec;
    final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final int offset = nowSec - startSec;
    final DateTime start = p.startDateTime.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');

    final String yyyyMMddHHmmss =
        '${start.year.toString().padLeft(4, '0')}'
        '${two(start.month)}${two(start.day)}T'
        '${two(start.hour)}${two(start.minute)}${two(start.second)}';

    return template.replaceAllMapped(
      RegExp(r'\$?\{([A-Za-z][A-Za-z-]*)(?::(\d+))?\}'),
      (Match m) {
        final String name = m.group(1)!;
        final int divisor = int.tryParse(m.group(2) ?? '') ?? 1;
        int div(int value) => divisor > 0 ? value ~/ divisor : value;
        switch (name) {
          case 'start':
          case 'utc':
            return startSec.toString();
          case 'end':
          case 'utcend':
            return endSec.toString();
          case 'lutc':
          case 'now':
          case 'timestamp':
            return nowSec.toString();
          case 'duration':
            return div(duration).toString();
          case 'offset':
            return div(offset).toString();
          case 'Y':
            return start.year.toString();
          case 'm':
            return two(start.month);
          case 'd':
            return two(start.day);
          case 'H':
            return two(start.hour);
          case 'M':
            return two(start.minute);
          case 'S':
            return two(start.second);
          case 'start-time':
            return yyyyMMddHHmmss;
          default:
            return m.group(0)!; // variable inconnue : on n'invente rien
        }
      },
    );
  }

  /// Détection automatique Xtream Codes :
  ///   http://server:port/USERNAME/PASSWORD/STREAMID.ts
  ///   http://server:port/live/USERNAME/PASSWORD/STREAMID.ts
  ///   http://server:port/USERNAME/PASSWORD/STREAMID.m3u8
  /// → on transforme en
  ///   http://server:port/timeshift/USERNAME/PASSWORD/MINUTES/YYYY-MM-DD:HH-MM/STREAMID.ts
  /// (jamais `/live/timeshift/…` : cette route n'existe pas), avec l'heure
  /// dans le fuseau du serveur quand il est connu.
  static String? _tryXtream(Channel channel, EpgProgram p) {
    final Uri uri = Uri.tryParse(channel.streamUrl) ?? Uri();
    if (uri.host.isEmpty) return null;

    final List<String> seg = uri.pathSegments;
    if (seg.length < 3) return null;

    // On cherche soit "/USER/PASS/STREAM" soit "/live/USER/PASS/STREAM"
    String? user;
    String? pass;
    String? streamWithExt;

    if (seg[0] == 'live' && seg.length >= 4) {
      user = seg[1];
      pass = seg[2];
      streamWithExt = seg[3];
    } else {
      user = seg[0];
      pass = seg[1];
      streamWithExt = seg[2];
    }

    // Sanity check : le dernier segment doit être un id numérique + ext
    final RegExp streamRe = RegExp(r'^(\d+)(\.\w+)?$');
    final Match? m = streamRe.firstMatch(streamWithExt);
    if (m == null) return null;
    final String streamId = m.group(1)!;

    final int minutes = ((p.stopTime - p.startTime) / 60000).round();
    // Heure murale du SERVEUR si son fuseau est connu, sinon celle de la
    // box (ancien comportement, juste quand les deux fuseaux coïncident).
    final DateTime start =
        XtreamServerClock.wallClock(channel.streamUrl, p.startTime) ??
            p.startDateTime;
    final String formatted =
        '${start.year.toString().padLeft(4, '0')}'
        '-${start.month.toString().padLeft(2, '0')}'
        '-${start.day.toString().padLeft(2, '0')}'
        ':${start.hour.toString().padLeft(2, '0')}'
        '-${start.minute.toString().padLeft(2, '0')}';

    final List<String> newSegs = <String>[
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
