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
//
//  ---------------------------------------------------------
//  LE MILLION DE CHAÎNES (05/09/2026)
//  ---------------------------------------------------------
//  MESURE AVANT CORRECTIF, sur un vrai M3U d'UN MILLION d'entrées
//  (204 Mo, format fournisseur) :
//
//      readAsString  ......  407 Mo   (UTF-16 : 2 octets par caractère)
//      + 2 replaceAll ....   407 Mo
//      + split('\n') .....   486 Mo   ← PIC, avant même de commencer
//
//  486 Mo rien que pour PRÉPARER les lignes, auxquels s'ajoutaient
//  ensuite ~600 Mo d'objets Channel. Plus d'un gigaoctet : impossible
//  sur une box, risqué sur un téléphone.
//
//  DEUX CHEMINS, UNE SEULE LOGIQUE. Le corps de la boucle — celui qui
//  sait lire #EXTINF, #EXTGRP et une URL — est extrait tel quel dans
//  [_M3uLineConsumer]. Les deux entrées s'en servent :
//
//   • [parse] (String) — inchangé pour l'appelant, mais parcourt les
//     lignes PARESSEUSEMENT : plus de `split` qui matérialise deux
//     millions de String, plus de `replaceAll` qui recopie tout le
//     fichier. Les « \r » sont mangés par le `trim()` qui existait déjà.
//
//   • [parseStream] (octets) — ne tient JAMAIS le fichier. Il décode au
//     fil de l'eau et rend les chaînes par PAQUETS, que l'appelant
//     insère en base puis relâche. La mémoire devient CONSTANTE : elle
//     ne dépend plus du nombre de chaînes, seulement de la taille du
//     paquet.
//
//  Écrire la logique une seule fois n'est pas de l'élégance : deux
//  copies auraient dérivé au premier attribut ajouté, et l'import
//  streaming aurait silencieusement produit des chaînes différentes de
//  l'import classique.
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../channels/domain/channel.dart';
import '../../vod/domain/m3u_vod_classifier.dart';
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


/// Le corps de la boucle de parsing, sorti de [M3uParser.parse] pour être
/// partagé avec [M3uParser.parseStream].
///
///  ÉTAT PORTÉ : les attributs d'un `#EXTINF` valent pour la LIGNE URL
///  SUIVANTE. Un parseur M3U est donc forcément à état — c'est pour ça
///  que c'est une classe et non une fonction pure.
///
///  [feed] rend la [Channel] produite, ou `null` si la ligne était une
///  directive, un commentaire, ou du bruit. Les avertissements
///  s'accumulent dans [warnings].
class _M3uLineConsumer {
  _M3uLineConsumer({required this.playlistId});

  final int playlistId;
  final List<String> warnings = <String>[];

  /// Nombre de chaînes produites — sert aux identifiants de repli
  /// (`m3u-<playlist>-<index>`) et au nom « Chaîne N ». En streaming, la
  /// liste n'existe plus, donc ce compteur remplace `channels.length`.
  int count = 0;

  Map<String, String>? _pendingAttrs;
  String? _pendingName;
  String? _pendingGroup;

  Channel? feed(String raw) {
    // `trim()` mange aussi le « \r » d'un fichier Windows : c'est ce qui
    // permet de supprimer les deux `replaceAll` qui recopiaient tout le
    // fichier en mémoire.
    final String line = raw.trim();
    if (line.isEmpty) return null;

    if (line.toUpperCase().startsWith('#EXTM3U')) return null;

    if (line.toUpperCase().startsWith('#EXTINF:')) {
      final _ExtInf parsed = M3uParser._parseExtInf(line);
      _pendingAttrs = parsed.attrs;
      _pendingName = parsed.name;
      return null;
    }

    if (line.toUpperCase().startsWith('#EXTGRP:')) {
      // Group title sur ligne séparée — s'applique à la prochaine
      // chaîne (variante M3U_PLUS).
      _pendingGroup = line.substring('#EXTGRP:'.length).trim();
      return null;
    }

    // Toutes les autres directives sont ignorées proprement
    // (#EXTVLCOPT, #KODIPROP, #EXT-X-*, commentaires).
    if (line.startsWith('#')) return null;

    // ----- Ligne URL -----
    // On accepte tout schéma — l'utilisateur sait ce qu'il met dans sa
    // playlist. Le lecteur gère http/https/rtmp/udp.
    if (!M3uParser._looksLikeUrl(line)) {
      warnings.add('Ligne ignorée (pas une URL valide) : '
          '${line.length > 80 ? "${line.substring(0, 80)}…" : line}');
      return null;
    }

    // URL SANS #EXTINF avant : M3U « simple ». On génère un nom et une
    // catégorie par défaut plutôt que de jeter l'entrée.
    //
    // NB i18n : le repli « Chaîne N » reste volontairement en dur. Ce
    // code tourne dans un ISOLATE où LocaleRepository n'existe pas, et
    // le nom est PERSISTÉ en SQLite : le localiser figerait la langue en
    // base. Idem pour « Autres », qui est en plus pattern-matchée en SQL
    // (cf. PlaylistRepository.getChannelsPage) — NE PAS traduire.
    if (_pendingAttrs == null && _pendingName == null) {
      final Channel c = Channel(
        id: 'm3u-$playlistId-$count',
        playlistId: playlistId,
        name: 'Chaîne ${count + 1}',
        category: _pendingGroup ?? 'Autres',
        streamUrl: line,
        // Sans nom, seule l'URL peut trahir un fichier VOD (décision
        // conservatrice — cf. M3uVodClassifier).
        isLive: M3uVodClassifier.classify(url: line, name: '') ==
            M3uVodKind.live,
        logoUrl: null,
        catchupSupported: false,
      );
      _pendingGroup = null;
      count++;
      return c;
    }

    final Map<String, String> attrs = _pendingAttrs ?? <String, String>{};
    final String tvgId = attrs['tvg-id'] ?? '';
    final String logoUrl = attrs['tvg-logo'] ?? attrs['logo'] ?? '';
    final String groupFromAttrs = attrs['group-title'] ?? attrs['group'] ?? '';
    final String groupTitle = groupFromAttrs.isNotEmpty
        ? groupFromAttrs
        : (_pendingGroup ?? 'Autres');
    final String catchupRaw = attrs['catchup'] ?? '';
    final String catchupDaysRaw = attrs['catchup-days'] ?? '';
    final String catchupSource = attrs['catchup-source'] ?? '';

    String name = (_pendingName ?? '').trim();
    if (name.isEmpty) name = 'Chaîne ${count + 1}';

    // ID stable : tvg-id si disponible, sinon « m3u-<playlist>-<index> ».
    final String channelId =
        tvgId.isNotEmpty ? tvgId : 'm3u-$playlistId-$count';

    final Channel c = Channel(
      id: channelId,
      playlistId: playlistId,
      name: name,
      category: groupTitle.isEmpty ? 'Autres' : groupTitle,
      streamUrl: line,
      // FILM/ÉPISODE M3U (fichier fini) → isLive:false : l'entrée sort des
      // listes live (requêtes is_live=1) et rejoint le Cinéma via
      // PlaylistRepository.getVodChannels.
      isLive: M3uVodClassifier.classify(url: line, name: name) ==
          M3uVodKind.live,
      logoUrl: logoUrl.isEmpty ? null : logoUrl,
      catchupSupported: catchupRaw.isNotEmpty || catchupSource.isNotEmpty,
      catchupDays: int.tryParse(catchupDaysRaw),
      catchupSource: catchupSource.isEmpty ? null : catchupSource,
    );

    _pendingAttrs = null;
    _pendingName = null;
    _pendingGroup = null;
    count++;
    return c;
  }
}

/// Parcourt les lignes d'un texte SANS le découper en liste.
///
///  `content.split('\n')` matérialise deux millions de String pour un
///  M3U d'un million d'entrées — 79 Mo mesurés, en plus des 407 Mo du
///  texte lui-même. Ce générateur n'en tient qu'une à la fois.
Iterable<String> _lignesParesseuses(String content) sync* {
  int debut = 0;
  while (debut <= content.length) {
    final int fin = content.indexOf('\n', debut);
    if (fin < 0) {
      if (debut < content.length) yield content.substring(debut);
      return;
    }
    yield content.substring(debut, fin);
    debut = fin + 1;
  }
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
    final _M3uLineConsumer conso = _M3uLineConsumer(playlistId: playlistId);

    // Strip BOM UTF-8 si présent (commun sur les exports Windows).
    if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) {
      content = content.substring(1);
    }
    if (content.isEmpty) {
      return M3uParseResult(
        channels: channels,
        warnings: <String>['Fichier vide.'],
      );
    }

    //  PLUS DE `replaceAll` NI DE `split` (05/09/2026). Ces trois appels
    //  recopiaient le fichier entier — 486 Mo mesurés sur un M3U d'un
    //  million d'entrées, avant même la première chaîne produite. Le
    //  `trim()` du consommateur mange déjà les « \r » de Windows, et
    //  [_lignesParesseuses] ne tient qu'une ligne à la fois.
    bool premiere = true;
    for (final String ligne in _lignesParesseuses(content)) {
      if (premiere) {
        premiere = false;
        if (!ligne.trim().toUpperCase().startsWith('#EXTM3U')) {
          conso.warnings.add(
            'Pas de #EXTM3U au début — on tente quand même de parser.',
          );
        }
      }
      // PLAFOND MÉMOIRE (anti-OOM box faibles) : au-delà de [maxChannels]
      // on arrête de matérialiser — le reste reste en source, l'app est
      // utilisable, juste tronquée à une taille tenable. [maxChannels] est
      // ADAPTÉ À LA RAM par l'appelant (DeviceMemory.channelCap).
      if (channels.length >= maxChannels) {
        conso.warnings.add(
          'Limite atteinte ($maxChannels chaînes) — le reste de la '
          'playlist est ignoré (garde-fou mémoire des appareils faibles).',
        );
        break;
      }
      final Channel? c = conso.feed(ligne);
      if (c != null) channels.add(c);
    }

    if (kDebugMode) {
      debugPrint(
        '[M3uParser] ${channels.length} chaînes parsées, '
        '${conso.warnings.length} warning(s).',
      );
    }
    return M3uParseResult(channels: channels, warnings: conso.warnings);
  }

  /// Parse un flux d'octets et rend les chaînes PAR PAQUETS.
  ///
  ///  C'est le chemin du MILLION. Il ne construit jamais le fichier en
  ///  mémoire : les octets arrivent, sont décodés au fil de l'eau,
  ///  découpés en lignes, et les chaînes partent par paquets de
  ///  [tailleLot] que l'appelant insère en base puis relâche.
  ///
  ///  La mémoire ne dépend donc plus du NOMBRE de chaînes, seulement de
  ///  la taille du paquet. Un million passe avec la même empreinte que
  ///  mille.
  ///
  ///  ⚠ [maxChannels] borne toujours le total : sur une petite box, on
  ///  s'arrête au plafond RAM. Ce qui change, c'est qu'on n'explose plus
  ///  AVANT d'y arriver.
  static Stream<List<Channel>> parseStream(
    Stream<List<int>> octets, {
    required int playlistId,
    int maxChannels = kMaxChannelsPerImport,
    int tailleLot = 1000,
  }) async* {
    final _M3uLineConsumer conso = _M3uLineConsumer(playlistId: playlistId);
    List<Channel> lot = <Channel>[];
    int total = 0;

    //  `allowMalformed` : une seule séquence UTF-8 abîmée au milieu d'un
    //  fichier de 200 Mo ne doit pas faire perdre les 999 999 autres
    //  chaînes. Même posture tolérante que le reste du parseur.
    final Stream<String> lignes = octets
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());

    await for (final String ligne in lignes) {
      if (total >= maxChannels) {
        conso.warnings.add(
          'Limite atteinte ($maxChannels chaînes) — le reste de la '
          'playlist est ignoré (garde-fou mémoire des appareils faibles).',
        );
        break;
      }
      final Channel? c = conso.feed(ligne);
      if (c == null) continue;
      lot.add(c);
      total++;
      if (lot.length >= tailleLot) {
        yield lot;
        lot = <Channel>[]; // nouvelle liste : l'appelant garde la sienne
      }
    }
    if (lot.isNotEmpty) yield lot;
  }

  /// Les avertissements du dernier [parseStream]. Le flux ne rend que des
  /// chaînes ; les avertissements sont secondaires et se lisent après.
  static List<String> derniersAvertissementsStream = <String>[];

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
