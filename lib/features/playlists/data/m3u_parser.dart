// =========================================================
//  m3u_parser.dart — Parser de playlists M3U / M3U8
// =========================================================
//  Lit un fichier M3U (en mémoire, sous forme de String) et
//  retourne une liste de `Channel` prêts à être stockés ou
//  affichés.
//
//  Format M3U géré :
//
//    #EXTM3U
//    #EXTINF:-1 tvg-id="canal-plus" tvg-name="Canal+"
//             tvg-logo="http://..." group-title="Cinéma"
//             catchup="default" catchup-days="7"
//             catchup-source="http://...timeshift?utc=${start}",Canal+
//    http://serveur.com/stream/12345.ts
//
//  Stratégie :
//    1. Vérifie le header #EXTM3U
//    2. Pour chaque ligne #EXTINF :
//       a. extrait les attributs entre guillemets (tvg-id,
//          tvg-name, tvg-logo, group-title, catchup,
//          catchup-days, catchup-source)
//       b. extrait le nom de chaîne (texte après la virgule)
//       c. la ligne suivante non-commentée = URL du flux
//    3. Ignore les lignes vides et les commentaires hors EXTINF
//
//  Robustesse : on tolère les playlists imparfaites (champs
//  manquants, espaces variables, fins de ligne mixtes \r\n vs \n).
// =========================================================

import 'package:flutter/foundation.dart';

import '../../channels/domain/channel.dart';

/// Résultat du parsing : la liste des chaînes + d'éventuelles
/// erreurs non bloquantes rencontrées en route (lignes ignorées).
class M3uParseResult {
  const M3uParseResult({
    required this.channels,
    required this.warnings,
  });

  final List<Channel> channels;
  final List<String> warnings;
}

abstract final class M3uParser {
  /// Parse un contenu M3U complet (String) → liste de chaînes.
  ///
  /// [playlistId] sera assigné à chaque chaîne pour qu'on
  /// retrouve son origine en base.
  static M3uParseResult parse(String content, {required int playlistId}) {
    final List<Channel> channels = <Channel>[];
    final List<String> warnings = <String>[];

    // Normaliser les sauts de ligne et splitter
    final List<String> lines = content.replaceAll('\r\n', '\n').split('\n');

    if (lines.isEmpty || !lines.first.trim().startsWith('#EXTM3U')) {
      warnings.add(
        'Le fichier ne commence pas par #EXTM3U — on tente quand même.',
      );
    }

    Map<String, String>? pendingAttrs;
    String? pendingName;

    for (int i = 0; i < lines.length; i++) {
      final String raw = lines[i];
      final String line = raw.trim();

      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        // Démarre une nouvelle chaîne en cours d'agrégation
        final _ExtInf parsed = _parseExtInf(line);
        pendingAttrs = parsed.attrs;
        pendingName = parsed.name;
        continue;
      }

      if (line.startsWith('#')) {
        // Autres commentaires M3U (#EXTGRP, #KODIPROP, etc.)
        // → ignorés pour la Phase 1
        continue;
      }

      // Ligne URL (flux)
      if (pendingAttrs == null || pendingName == null) {
        warnings.add('URL orpheline (sans EXTINF) ignorée : $line');
        continue;
      }

      // Construire la Channel à partir des attrs accumulés
      final String tvgId = pendingAttrs['tvg-id'] ?? '';
      final String logoUrl = pendingAttrs['tvg-logo'] ?? '';
      final String groupTitle = pendingAttrs['group-title'] ?? 'Autres';
      final String catchupRaw = pendingAttrs['catchup'] ?? '';
      final String catchupDaysRaw = pendingAttrs['catchup-days'] ?? '';
      final String catchupSource = pendingAttrs['catchup-source'] ?? '';

      // Génère un id stable : tvg-id si dispo, sinon URL
      final String channelId =
          tvgId.isNotEmpty ? tvgId : 'm3u-$playlistId-${channels.length}';

      channels.add(
        Channel(
          id: channelId,
          playlistId: playlistId,
          name: pendingName,
          category: groupTitle.isEmpty ? 'Autres' : groupTitle,
          streamUrl: line,
          isLive: true,
          logoUrl: logoUrl.isEmpty ? null : logoUrl,
          catchupSupported: catchupRaw.isNotEmpty || catchupSource.isNotEmpty,
          catchupDays: int.tryParse(catchupDaysRaw),
          catchupSource: catchupSource.isEmpty ? null : catchupSource,
        ),
      );

      // On vide les buffers — prêt pour la prochaine chaîne
      pendingAttrs = null;
      pendingName = null;
    }

    if (kDebugMode) {
      debugPrint(
        '[M3uParser] Parsing terminé : ${channels.length} chaînes, '
        '${warnings.length} warning(s)',
      );
    }

    return M3uParseResult(channels: channels, warnings: warnings);
  }

  // ----------------------------------------------------------
  //  Parsing fin d'une ligne #EXTINF
  // ----------------------------------------------------------

  /// Extrait les attributs `clé="valeur"` et le nom de chaîne
  /// après la virgule finale.
  ///
  /// Exemple d'entrée :
  ///   #EXTINF:-1 tvg-id="x" tvg-logo="http://y/z.png" group-title="Sport",Canal+ Sport
  ///
  /// Sortie :
  ///   attrs = {tvg-id: "x", tvg-logo: "http://y/z.png", group-title: "Sport"}
  ///   name  = "Canal+ Sport"
  static _ExtInf _parseExtInf(String line) {
    // Couper à la 1ère virgule QUI EST EN DEHORS d'un attribut "..."
    final int splitIndex = _findNameSeparatorIndex(line);
    final String head =
        splitIndex >= 0 ? line.substring(0, splitIndex) : line;
    final String name = splitIndex >= 0
        ? line.substring(splitIndex + 1).trim()
        : '(Sans nom)';

    final Map<String, String> attrs = <String, String>{};
    // Regex qui matche `key="value"` (avec valeur pouvant contenir des espaces)
    final RegExp pattern =
        RegExp(r'([a-zA-Z0-9_\-]+)="([^"]*)"');
    for (final RegExpMatch m in pattern.allMatches(head)) {
      attrs[m.group(1)!.toLowerCase()] = m.group(2)!;
    }

    return _ExtInf(attrs: attrs, name: name);
  }

  /// Trouve l'index de la virgule "vraie" (séparateur attrs/nom),
  /// en ignorant celles qui se trouvent à l'intérieur de guillemets.
  static int _findNameSeparatorIndex(String line) {
    bool insideQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final String c = line[i];
      if (c == '"') {
        insideQuotes = !insideQuotes;
      } else if (c == ',' && !insideQuotes) {
        return i;
      }
    }
    return -1;
  }
}

class _ExtInf {
  const _ExtInf({required this.attrs, required this.name});

  final Map<String, String> attrs;
  final String name;
}
