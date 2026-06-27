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

import 'package:flutter/foundation.dart';

import '../../channels/domain/channel.dart';
import 'playlist_import_limits.dart';

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
    int? maxChannels,
  }) {
    return compute(
      _m3uParseEntry,
      (content, playlistId, maxChannels ?? kMaxChannelsPerImport),
    );
  }

  /// Parse un contenu M3U complet (String) → liste de chaînes.
  /// [playlistId] est assigné à chaque chaîne. [maxChannels] borne le nombre de
  /// chaînes matérialisées (anti-OOM) ; on le PASSE en argument car le parsing
  /// tourne dans un ISOLATE où l'état statique (DeviceMemory) n'est PAS partagé
  /// — l'appelant (isolate principal) fournit le plafond adapté à la RAM.
  static M3uParseResult parse(
    String content, {
    required int playlistId,
    int maxChannels = kMaxChannelsPerImport,
  }) {
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

    for (int i = 0; i < lines.length; i++) {
      final String raw = lines[i];
      final String line = raw.trim();

      if (line.isEmpty) continue;

      // PLAFOND MÉMOIRE (anti-OOM box faibles) : au-delà de [maxChannels] on
      // arrête de matérialiser des chaînes — le reste de la playlist est ignoré
      // (la source reste utilisable, juste tronquée à une taille tenable).
      // [maxChannels] est ADAPTÉ À LA RAM par l'appelant (DeviceMemory.channelCap).
      if (channels.length >= maxChannels) {
        warnings.add(
          'Limite atteinte ($maxChannels chaînes) — le reste de la '
          'playlist est ignoré (garde-fou mémoire des appareils faibles).',
        );
        break;
      }

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

      // Ignorer silencieusement toutes les autres directives
      // (#EXTVLCOPT, #KODIPROP, #EXT-X-*, commentaires).
      if (line.startsWith('#')) {
        continue;
      }

      // ----- Ligne URL -----

      // On accepte tout schéma — l'utilisateur sait ce qu'il met
      // dans sa playlist. media_kit gère http/https/rtmp/udp.
      final bool looksLikeUrl = _looksLikeUrl(line);
      if (!looksLikeUrl) {
        warnings.add('Ligne ignorée (pas une URL valide) : '
            '${line.length > 80 ? "${line.substring(0, 80)}…" : line}');
        continue;
      }

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
            streamUrl: line,
            isLive: true,
            logoUrl: null,
            catchupSupported: false,
          ),
        );
        pendingGroup = null;
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
          streamUrl: line,
          isLive: true,
          logoUrl: logoUrl.isEmpty ? null : logoUrl,
          catchupSupported:
              catchupRaw.isNotEmpty || catchupSource.isNotEmpty,
          catchupDays: int.tryParse(catchupDaysRaw),
          catchupSource: catchupSource.isEmpty ? null : catchupSource,
        ),
      );

      // Reset des buffers pour la prochaine chaîne
      pendingAttrs = null;
      pendingName = null;
      pendingGroup = null;
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
}

class _ExtInf {
  const _ExtInf({required this.attrs, required this.name});
  final Map<String, String> attrs;
  final String name;
}

// Point d'entrée de l'isolate (`compute`) pour [M3uParser.parseInBackground].
// Top-level = forme la plus sûre pour `compute` ; le Record (String, int)
// est « sendable » entre isolates.
M3uParseResult _m3uParseEntry((String, int, int) args) =>
    M3uParser.parse(args.$1, playlistId: args.$2, maxChannels: args.$3);
