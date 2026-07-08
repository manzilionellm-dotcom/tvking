// =========================================================
//  hls_playlist_normalizer.dart — Réparation locale des playlists HLS
// =========================================================
//  CAUSE RACINE terrain (logs mpv du 2026-07-08) :
//    « Reading plaintext playlist » puis « Failed to recognize file
//    format » — alors que les SEGMENTS sont du TS valide (0x47).
//  ffmpeg (le démuxeur HLS de mpv) exige `#EXTM3U` à la POSITION 0 de
//  la playlist. Beaucoup de panels Xtream la servent avec un BOM, des
//  espaces/lignes vides devant, des fins de ligne \r\n, voire SANS la
//  balise du tout — les autres lecteurs (IBO, Smarters) tolèrent, mpv
//  non : il retombe en « liste texte » et échoue.
//
//  Ce normaliseur PUR (testable sans réseau) répare le document :
//    - retire le BOM UTF-8 et les blancs/lignes vides de tête ;
//    - normalise les fins de ligne (\r\n / \r → \n) ;
//    - GARANTIT `#EXTM3U` en première ligne ;
//    - résout les URIs en ABSOLU contre l'URL FINALE de la playlist
//      (token compris) : les SEGMENTS partent en direct vers le CDN ;
//      les SOUS-PLAYLISTS (master → media, pistes #EXT-X-MEDIA) sont
//      réécrites vers la route locale de normalisation (sinon mpv
//      irait chercher la media playlist cassée directement au CDN) ;
//    - absolutise aussi #EXT-X-KEY / #EXT-X-MAP (clés AES, init fMP4).
//
//  Il fournit aussi la PREUVE demandée : une description des premières
//  lignes BRUTES avec les octets invisibles rendus visibles
//  (⟨BOM⟩, ⟨CR⟩, ␣ pour les espaces de tête).
// =========================================================

/// Résultat de la normalisation d'une playlist.
class NormalizedPlaylist {
  const NormalizedPlaylist({
    required this.text,
    required this.hadExtM3uAtStart,
    required this.isMaster,
    required this.rawHead,
    required this.repairs,
  });

  /// Document réparé, prêt à servir à mpv.
  final String text;

  /// `true` si `#EXTM3U` était déjà à la position 0 (aucune réparation
  /// de balise nécessaire).
  final bool hadExtM3uAtStart;

  /// `true` si c'est une playlist MAÎTRE (#EXT-X-STREAM-INF).
  final bool isMaster;

  /// Les 3 premières lignes BRUTES, octets invisibles rendus visibles —
  /// la preuve terrain (« pourquoi mpv la lisait en plaintext »).
  final String rawHead;

  /// Liste lisible des réparations effectuées (vide = document sain).
  final List<String> repairs;
}

class HlsPlaylistNormalizer {
  HlsPlaylistNormalizer._();

  /// Rend visibles les octets invisibles des 3 premières lignes de
  /// [raw] : ⟨BOM⟩ pour U+FEFF, ⟨CR⟩ pour \r, ␣ pour les espaces de
  /// tête. C'est la PREUVE brute à journaliser.
  static String describeRawHead(String raw) {
    final List<String> lines = raw.split('\n');
    final StringBuffer b = StringBuffer();
    for (int i = 0; i < lines.length && i < 3; i++) {
      String l = lines[i];
      l = l.replaceAll('﻿', '⟨BOM⟩').replaceAll('\r', '⟨CR⟩');
      // Espaces de tête rendus visibles (un ␣ par espace).
      final int lead = l.length - l.trimLeft().length;
      l = '${'␣' * lead}${l.trimLeft()}';
      b.write('L${i + 1}: «$l»');
      if (i < 2 && i < lines.length - 1) b.write('  ');
    }
    return b.toString();
  }

  /// Normalise [raw] (téléchargée depuis [baseUrl], URL FINALE après
  /// redirections). [rewriteSubPlaylist] transforme l'URL ABSOLUE d'une
  /// sous-playlist en URL locale de normalisation (fournie par le
  /// relais). Les segments et clés restent en absolu direct.
  static NormalizedPlaylist normalize(
    String raw,
    Uri baseUrl, {
    required String Function(String absoluteUrl) rewriteSubPlaylist,
  }) {
    final List<String> repairs = <String>[];
    final String rawHead = describeRawHead(raw);

    String body = raw;
    if (body.startsWith('﻿')) {
      body = body.substring(1);
      repairs.add('BOM UTF-8 retiré');
    }
    if (body.contains('\r')) {
      body = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      repairs.add('fins de ligne CR normalisées');
    }

    List<String> lines = body.split('\n').map((String l) => l.trim()).toList();
    // Lignes vides de tête : ffmpeg n'accepte RIEN avant #EXTM3U.
    final int firstContent =
        lines.indexWhere((String l) => l.isNotEmpty);
    if (firstContent > 0) {
      lines = lines.sublist(firstContent);
      repairs.add('$firstContent ligne(s) vide(s) de tête retirée(s)');
    }
    if (firstContent < 0) lines = <String>[];

    final bool hadExtM3uAtStart =
        lines.isNotEmpty && lines.first.startsWith('#EXTM3U');
    if (!hadExtM3uAtStart) {
      lines.insert(0, '#EXTM3U');
      repairs.add('#EXTM3U AJOUTÉ en tête (absent — la cause du '
          '« plaintext playlist » de mpv)');
    }

    final bool isMaster =
        lines.any((String l) => l.startsWith('#EXT-X-STREAM-INF'));

    final List<String> out = <String>[];
    for (final String line in lines) {
      if (line.isEmpty) {
        out.add(line);
        continue;
      }
      if (line.startsWith('#')) {
        // Balises porteuses d'URI : sous-playlists de pistes → route
        // locale ; clés AES / init fMP4 → absolu direct.
        if (line.startsWith('#EXT-X-MEDIA')) {
          out.add(_rewriteUriAttribute(line, baseUrl, rewriteSubPlaylist));
        } else if (line.startsWith('#EXT-X-KEY') ||
            line.startsWith('#EXT-X-MAP')) {
          out.add(_rewriteUriAttribute(
              line, baseUrl, (String abs) => abs)); // absolu direct
        } else {
          out.add(line);
        }
        continue;
      }
      // Ligne URI : segment (media playlist) ou sous-playlist (master).
      final String absolute = baseUrl.resolve(line).toString();
      out.add(isMaster ? rewriteSubPlaylist(absolute) : absolute);
    }

    return NormalizedPlaylist(
      text: '${out.join('\n')}\n',
      hadExtM3uAtStart: hadExtM3uAtStart,
      isMaster: isMaster,
      rawHead: rawHead,
      repairs: repairs,
    );
  }

  /// Réécrit l'attribut `URI="…"` d'une balise, résolu en absolu puis
  /// transformé par [map].
  static String _rewriteUriAttribute(
    String line,
    Uri baseUrl,
    String Function(String absoluteUrl) map,
  ) {
    final RegExp uriAttr = RegExp('URI="([^"]*)"');
    return line.replaceAllMapped(uriAttr, (Match m) {
      final String abs = baseUrl.resolve(m.group(1)!).toString();
      return 'URI="${map(abs)}"';
    });
  }
}
