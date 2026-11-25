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
//
//  Alignement sur la référence du marché, le module Kodi « IPTV Simple »
//  (lecture de CatchupController.cpp et Channel.cpp, branche Omega) :
//    - `{Y} {m} {d} {H} {M} {S}` sont l'heure MURALE du début, pas l'UTC
//      (Kodi : localtime). Ici : le fuseau du serveur s'il est connu, sinon
//      celui de la box. En UTC, le replay démarrait 1 à 2 h à côté ;
//    - les formes `{utc:Y-m-d H:M}`, `${start:…}`, `{utcend:…}`, `{lutc:…}`
//      sont reconnues (même heure murale, malgré le nom « utc ») ;
//    - un gabarit relatif qui ne commence ni par `?` ni par `&` est collé
//      tel quel derrière l'adresse du flux (mode « append » de Kodi).
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
      final String filled = _fillTemplate(
        channel.catchupSource!,
        program,
        streamUrl: channel.streamUrl,
      );
      // Gabarit « append » : seulement des paramètres (`?utc=…` ou `&utc=…`),
      // à coller derrière l'adresse du flux.
      if (filled.startsWith('?') || filled.startsWith('&')) {
        final String base = channel.streamUrl;
        final String sep = base.contains('?') ? '&' : '?';
        return '$base$sep${filled.substring(1)}';
      }
      // Autre gabarit relatif (pas de `schéma://`) : collé tel quel derrière
      // l'adresse du flux, comme le mode « append » de Kodi. Avant, il était
      // renvoyé seul : une adresse sans serveur, impossible à ouvrir.
      if (!_absolute.hasMatch(filled)) return '${channel.streamUrl}$filled';
      return filled;
    }

    // 2. Xtream auto-detect
    final String? xtream = _tryXtream(channel, program);
    if (xtream != null) return xtream;

    // 3. M3U "default" → append params
    return _appendDefaultParams(channel.streamUrl, program);
  }

  // ----- Helpers -----

  /// Adresse complète : commence par un schéma (`http://`, `https://`…).
  static final RegExp _absolute = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*://');

  /// Remplace les variables d'un gabarit catch-up. Les deux écritures du
  /// marché sont acceptées : `${nom}` et `{nom}`. Variables :
  ///   start, utc        → début du programme (secondes epoch)
  ///   end, utcend       → fin du programme
  ///   lutc, now, timestamp → maintenant
  ///   duration, duration:N → durée en secondes (÷ N)
  ///   offset, offset:N  → retard sur le direct en secondes (÷ N)
  ///   Y m d H M S       → date et heure MURALES du début (voir [wall])
  ///   utc:FORMAT, start:FORMAT, utcend:FORMAT, end:FORMAT, lutc:FORMAT…
  ///                     → même heure murale, FORMAT fait des lettres
  ///                       Y m d H M S (ex. `{utc:Y-m-d:H-M}`)
  ///   start-time        → AAAAMMJJTHHMMSS (UTC)
  /// Une variable inconnue est laissée telle quelle.
  static String _fillTemplate(
    String template,
    EpgProgram p, {
    required String streamUrl,
  }) {
    final int startSec = p.startTime ~/ 1000;
    final int endSec = p.stopTime ~/ 1000;
    final int duration = endSec - startSec;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final int nowSec = nowMs ~/ 1000;
    final int offset = nowSec - startSec;
    final DateTime start = p.startDateTime.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');

    // Heure murale : celle du serveur d'archives si son fuseau est connu
    // (gabarit complet → son hôte, gabarit relatif → celui du flux), sinon
    // celle de la box, comme Kodi. On ne lit que le début du gabarit, avant
    // la première variable, pour trouver l'hôte.
    final String clockUrl = _absolute.hasMatch(template)
        ? template.split(RegExp(r'[\$\{]')).first
        : streamUrl;
    DateTime wall(int epochMs) =>
        XtreamServerClock.wallClock(clockUrl, epochMs) ??
        DateTime.fromMillisecondsSinceEpoch(epochMs);
    final DateTime wallStart = wall(p.startTime);
    String field(DateTime t, String letter) {
      switch (letter) {
        case 'Y':
          return t.year.toString().padLeft(4, '0');
        case 'm':
          return two(t.month);
        case 'd':
          return two(t.day);
        case 'H':
          return two(t.hour);
        case 'M':
          return two(t.minute);
        case 'S':
          return two(t.second);
        default:
          return letter; // séparateur (- : / espace…) : recopié
      }
    }

    String formatted(DateTime t, String format) => <String>[
          for (int i = 0; i < format.length; i++) field(t, format[i]),
        ].join();

    final String yyyyMMddHHmmss =
        '${start.year.toString().padLeft(4, '0')}'
        '${two(start.month)}${two(start.day)}T'
        '${two(start.hour)}${two(start.minute)}${two(start.second)}';

    return template.replaceAllMapped(
      RegExp(r'\$?\{([A-Za-z][A-Za-z-]*)(?::([^{}]+))?\}'),
      (Match m) {
        final String name = m.group(1)!;
        final String? arg = m.group(2);
        final int? number = arg == null ? 1 : int.tryParse(arg);
        // Forme `{nom:FORMAT}` (FORMAT non numérique) : date murale écrite
        // avec les lettres Y m d H M S. Réservée aux variables de temps.
        if (number == null) {
          switch (name) {
            case 'start':
            case 'utc':
              return formatted(wallStart, arg!);
            case 'end':
            case 'utcend':
              return formatted(wall(p.stopTime), arg!);
            case 'lutc':
            case 'now':
            case 'timestamp':
              return formatted(wall(nowMs), arg!);
            default:
              return m.group(0)!; // ex. {duration:abc} : on n'invente rien
          }
        }
        final int divisor = number;
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
          case 'm':
          case 'd':
          case 'H':
          case 'M':
          case 'S':
            return field(wallStart, name);
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
