// =========================================================
//  m3u_parser.dart — Parser M3U / M3U_PLUS ultra tolérant
// =========================================================
//  Conçu pour avaler n'importe quelle playlist IPTV dans la
//  nature, y compris :
//
//    - Standard M3U          (juste des URLs, une par ligne)
//    - M3U_PLUS / Extended   (avec #EXTINF + attributs)
//    - Header #EXTM3U absent  (on tente quand même)
//    - BOM UTF-8 au début     (EF BB BF strippé)
//    - Saut de ligne mixte    (\r\n, \n, \r)
//    - Attributs sans guillemets ou avec guillemets simples
//    - #EXTGRP: pour le group-title sur une ligne séparée
//    - #EXTVLCOPT:, #KODIPROP:, #EXT-X-* (ignorés proprement)
//    - URLs rtmp://, udp://, https://, http://
//    - Lignes vides multiples entre entrées
//    - Espaces/tabs aléatoires partout
//    - Noms de chaînes vides → fallback "Chaîne N"
//
//  Le parser ne casse JAMAIS sur une ligne malformée — il
//  warn et continue. C'est volontaire : 99% des playlists du
//  marché ont au moins une ligne tordue, on veut quand même
//  importer les 19 999 autres chaînes.
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../channels/domain/channel.dart';

/// Résultat du parsing : la liste des chaînes + warnings non
/// bloquants (lignes ignorées, attributs étranges, etc.).
class M3uParseResult {
  const M3uParseResult({
    required this.channels,
    required this.warnings,
  });

  final List<Channel> channels;
  final List<String> warnings;
}

abstract final class M3uParser {
  /// Comme [parse], mais exécuté dans un ISOLATE via `compute` → l'UI ne
  /// gèle JAMAIS, même pour une playlist de plusieurs Mo / des dizaines de
  /// milliers de chaînes. Variante à utiliser en production (anti-ANR,
  /// s'adapte aux téléphones modestes).
  static Future<M3uParseResult> parseInBackground(
    String content, {
    required int playlistId,
  }) {
    return compute(_m3uParseEntry, (content, playlistId));
  }

  /// Parse un contenu M3U complet (String) → liste de chaînes.
  /// [playlistId] est assigné à chaque chaîne.
  static M3uParseResult parse(String content, {required int playlistId}) {
    final List<Channel> channels = <Channel>[];
    final List<String> warnings = <String>[];

    // ----- Normalisation préalable -----

    // Strip BOM UTF-8 si présent (commun sur les exports Windows).
    if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) {
      content = content.substring(1);
    }

    // Normaliser les sauts de ligne (\r\n, \r → \n)
    final List<String> lines = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');

    if (lines.isEmpty) {
      warnings.add('Fichier vide.');
      return M3uParseResult(channels: channels, warnings: warnings);
    }
    final bool hasHeader =
        lines.first.trim().toUpperCase().startsWith('#EXTM3U');
    if (!hasHeader) {
      warnings.add(
        'Pas de #EXTM3U au début — on tente quand même de parser.',
      );
    }

    // ----- Boucle principale -----

    Map<String, String>? pendingAttrs;
    String? pendingName;
    String? pendingGroup; // #EXTGRP: hors EXTINF
    // En-têtes HTTP de la prochaine chaîne (User-Agent / Referer / Origin /
    // Cookie), collectés depuis #EXTVLCOPT, #EXTHTTP, #KODIPROP ou le
    // suffixe d'URL. Vidés après chaque chaîne (cf. helpers en bas).
    final Map<String, String> pendingHeaders = <String, String>{};

    for (int i = 0; i < lines.length; i++) {
      final String raw = lines[i];
      final String line = raw.trim();

      if (line.isEmpty) continue;

      // ----- Directives connues -----

      if (line.toUpperCase().startsWith('#EXTM3U')) {
        // Header initial — peut aussi contenir des attributs
        // globaux qu'on ignore pour l'instant.
        continue;
      }

      if (line.toUpperCase().startsWith('#EXTINF:')) {
        final _ExtInf parsed = _parseExtInf(line);
        pendingAttrs = parsed.attrs;
        pendingName = parsed.name;
        continue;
      }

      if (line.toUpperCase().startsWith('#EXTGRP:')) {
        // Group title sur ligne séparée — s'applique à la
        // prochaine chaîne (M3U_PLUS variant).
        pendingGroup = line.substring('#EXTGRP:'.length).trim();
        continue;
      }

      // ----- En-têtes HTTP par chaîne -----
      // Beaucoup de panels IPTV imposent un User-Agent / Referer précis
      // par chaîne. On les collecte ici pour les rejouer à la lecture
      // (sinon : 403 → « la chaîne ne marche pas »). Comme VLC / IBO Player.
      final String upper = line.toUpperCase();
      if (upper.startsWith('#EXTVLCOPT:')) {
        _absorbKeyValueHeader(line.substring('#EXTVLCOPT:'.length),
            pendingHeaders);
        continue;
      }
      if (upper.startsWith('#EXTHTTP:')) {
        _absorbExtHttp(line.substring('#EXTHTTP:'.length), pendingHeaders);
        continue;
      }
      if (upper.startsWith('#KODIPROP:')) {
        _absorbKodiProp(line.substring('#KODIPROP:'.length), pendingHeaders);
        continue;
      }

      // Ignorer silencieusement toutes les autres directives
      // (#EXT-X-*, commentaires, etc.).
      if (line.startsWith('#')) {
        continue;
      }

      // ----- Ligne URL -----

      // Suffixe d'en-têtes éventuel : URL|User-Agent=…|Referer=… (convention
      // VLC/Kodi répandue). On isole l'URL réelle et on absorbe les en-têtes.
      String urlPart = line;
      final int pipe = line.indexOf('|');
      if (pipe > 0) {
        urlPart = line.substring(0, pipe).trim();
        _absorbPipeHeaders(line.substring(pipe + 1), pendingHeaders);
      }

      // On accepte tout schéma — l'utilisateur sait ce qu'il met
      // dans sa playlist. media_kit gère http/https/rtmp/udp.
      final bool looksLikeUrl = _looksLikeUrl(urlPart);
      if (!looksLikeUrl) {
        warnings.add('Ligne ignorée (pas une URL valide) : '
            '${urlPart.length > 80 ? "${urlPart.substring(0, 80)}…" : urlPart}');
        pendingHeaders.clear();
        continue;
      }

      // Instantané des en-têtes collectés pour CETTE chaîne (null si aucun).
      final Map<String, String>? headers = pendingHeaders.isEmpty
          ? null
          : Map<String, String>.of(pendingHeaders);

      // Si on a une URL SANS #EXTINF avant, on l'accepte quand
      // même : c'est un M3U "simple" (juste des URLs). On génère
      // un nom et une catégorie par défaut.
      if (pendingAttrs == null && pendingName == null) {
        channels.add(
          Channel(
            id: 'm3u-$playlistId-${channels.length}',
            playlistId: playlistId,
            name: 'Chaîne ${channels.length + 1}',
            category: pendingGroup ?? 'Autres',
            streamUrl: urlPart,
            isLive: true,
            logoUrl: null,
            catchupSupported: false,
            httpHeaders: headers,
          ),
        );
        pendingGroup = null;
        pendingHeaders.clear();
        continue;
      }

      // Construire la Channel à partir des attrs accumulés
      final Map<String, String> attrs =
          pendingAttrs ?? <String, String>{};
      final String tvgId = attrs['tvg-id'] ?? '';
      final String logoUrl = attrs['tvg-logo'] ?? attrs['logo'] ?? '';
      final String groupFromAttrs =
          attrs['group-title'] ?? attrs['group'] ?? '';
      final String groupTitle = groupFromAttrs.isNotEmpty
          ? groupFromAttrs
          : (pendingGroup ?? 'Autres');
      final String catchupRaw = attrs['catchup'] ?? '';
      final String catchupDaysRaw = attrs['catchup-days'] ?? '';
      final String catchupSource = attrs['catchup-source'] ?? '';

      // Nom : fallback si vide
      String name = (pendingName ?? '').trim();
      if (name.isEmpty) name = 'Chaîne ${channels.length + 1}';

      // ID stable : tvg-id si dispo, sinon "m3u-<playlist>-<index>"
      final String channelId = tvgId.isNotEmpty
          ? tvgId
          : 'm3u-$playlistId-${channels.length}';

      channels.add(
        Channel(
          id: channelId,
          playlistId: playlistId,
          name: name,
          category: groupTitle.isEmpty ? 'Autres' : groupTitle,
          streamUrl: urlPart,
          isLive: true,
          logoUrl: logoUrl.isEmpty ? null : logoUrl,
          catchupSupported:
              catchupRaw.isNotEmpty || catchupSource.isNotEmpty,
          catchupDays: int.tryParse(catchupDaysRaw),
          catchupSource: catchupSource.isEmpty ? null : catchupSource,
          httpHeaders: headers,
        ),
      );

      // Reset des buffers pour la prochaine chaîne
      pendingAttrs = null;
      pendingName = null;
      pendingGroup = null;
      pendingHeaders.clear();
    }

    if (kDebugMode) {
      debugPrint(
        '[M3uParser] ${channels.length} chaînes parsées, '
        '${warnings.length} warning(s).',
      );
    }

    return M3uParseResult(channels: channels, warnings: warnings);
  }

  // ============================================================
  //  Helpers
  // ============================================================

  /// Vérifie qu'une ligne ressemble à une URL.
  ///
  /// On accepte MAINTENANT n'importe quel schéma `xxx://` (RFC 3986) —
  /// pas seulement une liste fixe. Ainsi srt://, rist://, et tout autre
  /// protocole que libmpv/FFmpeg sait ouvrir passent aussi → aucune
  /// entrée de playlist valide n'est écartée.
  static final RegExp _schemeRx =
      RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://');

  static bool _looksLikeUrl(String line) {
    if (_schemeRx.hasMatch(line)) return true;
    // Repli : certaines playlists mettent des chemins SANS schéma mais
    // pointant clairement vers un média (extension connue) → on accepte.
    final String lower = line.toLowerCase();
    const List<String> mediaExt = <String>[
      '.m3u8', '.ts', '.mp4', '.mkv', '.mpd', '.flv', '.avi', '.mov',
      '.webm', '.m4v', '.aac', '.mp3',
    ];
    for (final String ext in mediaExt) {
      if (lower.contains(ext)) return true;
    }
    return false;
  }

  /// Extrait les attributs et le nom de chaîne d'une ligne #EXTINF.
  ///
  /// Exemples acceptés :
  ///   #EXTINF:-1 tvg-id="x" tvg-logo="http://y/z.png",Canal+
  ///   #EXTINF:-1 tvg-id='x' tvg-logo='http://y',Canal+      ← simple quote
  ///   #EXTINF:-1 tvg-id=x tvg-logo=http://y/z.png,Canal+    ← sans quote
  ///   #EXTINF:-1,Canal+                                      ← sans attrs
  static _ExtInf _parseExtInf(String line) {
    // Couper à la 1ère virgule HORS guillemets pour séparer
    // les attributs du nom de chaîne.
    final int splitIndex = _findNameSeparatorIndex(line);
    final String head =
        splitIndex >= 0 ? line.substring(0, splitIndex) : line;
    final String name = splitIndex >= 0
        ? line.substring(splitIndex + 1).trim()
        : '';

    final Map<String, String> attrs = <String, String>{};

    // Pattern 1 : `key="value"` ou `key='value'` (le plus standard)
    final RegExp quoted =
        RegExp(r'''([a-zA-Z0-9_\-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''');
    for (final RegExpMatch m in quoted.allMatches(head)) {
      final String key = m.group(1)!.toLowerCase();
      final String value = m.group(2) ?? m.group(3) ?? '';
      attrs[key] = value;
    }

    // Pattern 2 : `key=value` sans guillemets, valeur jusqu'au prochain
    // espace. On ne le tente QUE si rien n'a été matché par le pattern
    // 1 — pour éviter de re-matcher des fragments d'attribut quoted.
    if (attrs.isEmpty) {
      final RegExp unquoted = RegExp(r'([a-zA-Z0-9_\-]+)=([^\s,]+)');
      for (final RegExpMatch m in unquoted.allMatches(head)) {
        attrs[m.group(1)!.toLowerCase()] = m.group(2)!;
      }
    }

    return _ExtInf(attrs: attrs, name: name);
  }

  /// Trouve l'index de la virgule "vraie" (séparateur attrs/nom),
  /// en ignorant celles dans les guillemets " ou '.
  static int _findNameSeparatorIndex(String line) {
    bool inDouble = false;
    bool inSingle = false;
    for (int i = 0; i < line.length; i++) {
      final String c = line[i];
      if (c == '"' && !inSingle) inDouble = !inDouble;
      if (c == "'" && !inDouble) inSingle = !inSingle;
      if (c == ',' && !inDouble && !inSingle) return i;
    }
    return -1;
  }

  // ============================================================
  //  En-têtes HTTP par chaîne (User-Agent / Referer / Origin…)
  // ============================================================

  /// Normalise un nom d'en-tête vers sa forme HTTP canonique. Renvoie
  /// `null` pour les clés qu'on ne veut pas propager (on se limite aux
  /// en-têtes utiles à l'accès au flux, pas aux options de décodage).
  static String? _canonHeaderKey(String raw) {
    // On retire un éventuel préfixe `http-` (convention #EXTVLCOPT).
    final String k = raw.trim().toLowerCase().replaceFirst('http-', '');
    switch (k) {
      case 'user-agent':
      case 'useragent':
      case 'user_agent':
        return 'User-Agent';
      case 'referer':
      case 'referrer': // VLC écrit "referrer" (2 r)
        return 'Referer';
      case 'origin':
        return 'Origin';
      case 'cookie':
      case 'cookies':
        return 'Cookie';
      default:
        return null;
    }
  }

  /// Nettoie une valeur d'en-tête : trim + retrait de guillemets entourants.
  static String _cleanHeaderValue(String raw) {
    String v = raw.trim();
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) ||
            (v.startsWith("'") && v.endsWith("'")))) {
      v = v.substring(1, v.length - 1);
    }
    return v;
  }

  /// Absorbe une directive `clé=valeur` (cas #EXTVLCOPT). Exemples :
  ///   http-user-agent=Mozilla/5.0      |  http-referrer="http://x"
  static void _absorbKeyValueHeader(String body, Map<String, String> out) {
    final int eq = body.indexOf('=');
    if (eq <= 0) return;
    final String? canon = _canonHeaderKey(body.substring(0, eq));
    if (canon == null) return;
    final String val = _cleanHeaderValue(body.substring(eq + 1));
    if (val.isNotEmpty) out[canon] = val;
  }

  /// Absorbe une directive #EXTHTTP, dont le corps est un objet JSON :
  ///   #EXTHTTP:{"User-Agent":"…","Referer":"…","Cookie":"…"}
  static void _absorbExtHttp(String body, Map<String, String> out) {
    try {
      final dynamic j = jsonDecode(body.trim());
      if (j is Map) {
        j.forEach((dynamic k, dynamic v) {
          final String? canon = _canonHeaderKey('$k');
          if (canon != null && v != null) {
            final String val = _cleanHeaderValue('$v');
            if (val.isNotEmpty) out[canon] = val;
          }
        });
      }
    } catch (_) {
      // JSON malformé → on ignore (on ne casse jamais le parsing).
    }
  }

  /// Absorbe une directive #KODIPROP. Deux formes gérées :
  ///   inputstream.adaptive.stream_headers=User-Agent=…&Referer=…
  ///   http-user-agent=…
  static void _absorbKodiProp(String body, Map<String, String> out) {
    final int eq = body.indexOf('=');
    if (eq <= 0) return;
    final String key = body.substring(0, eq).trim().toLowerCase();
    final String val = body.substring(eq + 1);
    if (key.endsWith('stream_headers') || key.endsWith('manifest_headers')) {
      _absorbPipeHeaders(val, out); // liste k=v séparée par & ou |
    } else {
      _absorbKeyValueHeader(body, out);
    }
  }

  /// Absorbe une liste d'en-têtes `clé=valeur` séparés par `|` ou `&`
  /// (suffixe d'URL `…|User-Agent=…|Referer=…` ou stream_headers Kodi).
  static void _absorbPipeHeaders(String body, Map<String, String> out) {
    for (final String part in body.split(RegExp(r'[|&]'))) {
      final int eq = part.indexOf('=');
      if (eq <= 0) continue;
      final String? canon = _canonHeaderKey(part.substring(0, eq));
      if (canon == null) continue;
      final String val = _cleanHeaderValue(part.substring(eq + 1));
      if (val.isNotEmpty) out[canon] = val;
    }
  }
}

class _ExtInf {
  const _ExtInf({required this.attrs, required this.name});
  final Map<String, String> attrs;
  final String name;
}

// Point d'entrée de l'isolate (`compute`) pour [M3uParser.parseInBackground].
// Top-level = forme la plus sûre pour `compute` ; le Record (String, int)
// est « sendable » entre isolates.
M3uParseResult _m3uParseEntry((String, int) args) =>
    M3uParser.parse(args.$1, playlistId: args.$2);
