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
import 'dart:isolate' show TransferableTypedData;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../channels/domain/channel.dart';
import 'import_progress.dart';
import '../../../core/blackbox/black_box.dart';
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
  }) {
    return compute(_m3uParseEntry, (content, playlistId));
  }

  /// Variante OCTETS (performance, 25/09/2026) : les octets bruts du
  /// téléchargement sont TRANSFÉRÉS (pas copiés) à l'isolate, qui fait le
  /// décodage (UTF-8 strict → repli Latin-1, BOM) PUIS le parsing. Avant, le
  /// décodage d'un fichier de 20-60 Mo se faisait sur le fil UI (gel visible
  /// à l'import et à chaque synchro auto). Le fil UI ne touche plus jamais
  /// au contenu de la playlist : il ne reçoit que la liste de chaînes.
  static Future<M3uParseResult> parseBytesInBackground(
    Uint8List bytes, {
    required int playlistId,
  }) {
    BlackBox.instance.breadcrumb('Analyse M3U (${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} Mo, isolate)');
    ImportProgressBus.decoding(bytes.length);
    return compute(
      _m3uParseBytesEntry,
      (TransferableTypedData.fromList(<Uint8List>[bytes]), playlistId),
    ).then((M3uParseResult r) {
      BlackBox.instance.info('M3U', '${r.channels.length} chaînes analysées');
      ImportProgressBus.found(r.channels.length);
      BlackBox.instance.breadcrumb('');
      return r;
    });
  }

  /// Décodage UTF-8 → Latin-1 fallback + BOM strip. Partagé avec M3uFetcher.
  /// On travaille sur les octets bruts pour garder le contrôle de l'encodage.
  static String decodeBytes(List<int> bytes) {
    if (bytes.isEmpty) return '';
    // Strip BOM UTF-8 (EF BB BF) si présent.
    final List<int> stripped =
        (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
            ? (bytes is Uint8List
                ? Uint8List.sublistView(bytes, 3) // vue, pas de copie
                : bytes.sublist(3))
            : bytes;
    // UTF-8 strict d'abord — c'est le format légal de M3U_PLUS.
    try {
      return utf8.decode(stripped, allowMalformed: false);
    } catch (_) {
      // Pas du UTF-8 valide → Latin-1 / Windows-1252 (ne lève jamais).
      return latin1.decode(stripped);
    }
  }

  /// Parse un contenu M3U complet (String) → liste de chaînes.
  /// [playlistId] est assigné à chaque chaîne.
  static M3uParseResult parse(String content, {required int playlistId}) {
    final List<Channel> channels = <Channel>[];
    final List<String> warnings = <String>[];

    int lineNumber = 0;
    int ignored = 0;
    const sampleLimit = 16;

    // ----- Normalisation préalable -----

    // Strip BOM UTF-8 si présent (commun sur les exports Windows).
    if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) {
      content = content.substring(1);
    }

    // Parcours paresseux : LineSplitter reconnaît LF, CRLF et CR sans
    // recopier tout le fichier ni matérialiser toutes ses lignes. Le plafond
    // de chaînes arrête donc aussi la découpe d'une très grosse playlist.
    final Iterator<String> lines = LineSplitter.split(content).iterator;
    if (!lines.moveNext()) {
      warnings.add('Fichier vide.');
      return M3uParseResult(channels: channels, warnings: warnings);
    }
    final bool hasHeader =
        lines.current.trim().toUpperCase().startsWith('#EXTM3U');
    if (!hasHeader) {
      warnings.add(
        'Pas de #EXTM3U au début — on tente quand même de parser.',
      );
    }

    // ----- Boucle principale -----

    Map<String, String>? pendingAttrs;
    String? pendingName;
    String? pendingGroup; // #EXTGRP: hors EXTINF

    do {
      lineNumber++;
      final String raw = lines.current;
      final String line = raw.trim();

      if (line.isEmpty) continue;

      // PLAFOND MÉMOIRE (anti-OOM box faibles) : au-delà de
      // kMaxChannelsPerImport on arrête de matérialiser des chaînes — le reste
      // de la playlist est ignoré (la source reste utilisable, juste tronquée
      // à une taille tenable). Aligné sur le plafond de LECTURE du repository.
      if (channels.length >= kMaxChannelsPerImport) {
        warnings.add(
          'Limite atteinte ($kMaxChannelsPerImport chaînes) — le reste de la '
          'playlist est ignoré (garde-fou mémoire des appareils faibles).',
        );
        break;
      }

      // ----- Directives connues -----

      if (line.startsWith('#')) {
        // Comparer uniquement le préfixe : les URL et les métadonnées
        // longues n'ont jamais besoin d'une copie entière en majuscules.
        final prefix = line.substring(0, line.length < 8 ? line.length : 8).toUpperCase();
        if (prefix == '#EXTINF:') {
          final parsed = _parseExtInf(line);
          pendingAttrs = parsed.attrs;
          pendingName = parsed.name;
        } else if (prefix == '#EXTGRP:') {
          pendingGroup = line.substring(8).trim();
        }
        continue;
      }

      // ----- Ligne URL -----

      // On accepte tout schéma — l'utilisateur sait ce qu'il met
      // dans sa playlist. media_kit gère http/https/rtmp/udp.
      final bool looksLikeUrl = _looksLikeUrl(line);
      if (!looksLikeUrl) {
        // Un catalogue corrompu peut contenir des millions de lignes.
        // Garder quelques positions suffit et ne copie aucun identifiant.
        if (++ignored <= sampleLimit) {
          warnings.add('Ligne $lineNumber ignorée (pas une URL valide).');
        }
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
    } while (lines.moveNext());

    if (ignored > sampleLimit) {
      warnings.add('${ignored - sampleLimit} autres lignes ignorées.');
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
    const comma = 0x2c;
    const equals = 0x3d;
    const space = 0x20;
    const singleQuote = 0x27;
    const doubleQuote = 0x22;
    final attrs = <String, String>{};
    int i = 8; // Après « #EXTINF: ».
    while (i < line.length) {
      final code = line.codeUnitAt(i);
      if (code == comma) {
        return _ExtInf(attrs: attrs, name: line.substring(i + 1).trim());
      }
      if (code <= space || code == equals) {
        i++;
        continue;
      }
      final start = i;
      while (i < line.length) {
        final c = line.codeUnitAt(i);
        if (c <= space || c == comma || c == equals) break;
        i++;
      }
      final end = i;
      while (i < line.length && line.codeUnitAt(i) <= space) {
        i++;
      }
      // Durée ou champ isolé, sans signe égal.
      if (i == line.length || line.codeUnitAt(i) != equals) continue;
      i++;
      while (i < line.length && line.codeUnitAt(i) <= space) {
        i++;
      }
      final quote = i < line.length ? line.codeUnitAt(i) : 0;
      final quoted = quote == doubleQuote || quote == singleQuote;
      if (quoted) i++;
      final valueStart = i;
      while (i < line.length) {
        final c = line.codeUnitAt(i);
        if (quoted ? c == quote : c <= space || c == comma) break;
        i++;
      }
      attrs[line.substring(start, end).toLowerCase()] = line.substring(valueStart, i);
      if (quoted && i < line.length) i++;
    }
    return _ExtInf(attrs: attrs, name: '');
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

/// Entrée isolate de [M3uParser.parseBytesInBackground] : matérialise les
/// octets transférés, décode, parse. Tout hors du fil UI.
M3uParseResult _m3uParseBytesEntry((TransferableTypedData, int) args) {
  final Uint8List bytes = args.$1.materialize().asUint8List();
  return M3uParser.parse(M3uParser.decodeBytes(bytes), playlistId: args.$2);
}
