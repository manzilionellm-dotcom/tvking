// =========================================================
//  quality_ladder.dart — Déclinaisons de qualité d'une même chaîne
// =========================================================
//  L'ABR (adaptation automatique de qualité, façon Netflix) n'existe que
//  si le FLUX propose plusieurs débits (HLS/DASH multi-variantes). Or 95 %
//  des chaînes IPTV live sont du MPEG-TS MONO-débit : impossible d'alléger
//  le flux lui-même. MAIS les panels publient presque toujours la même
//  chaîne en PLUSIEURS déclinaisons distinctes :
//
//      « FR| TF1 UHD »  ·  « FR| TF1 FHD »  ·  « FR| TF1 HD »  ·  « FR| TF1 SD »
//
//  Ce fichier retrouve ces déclinaisons dans la liste de zap : c'est la
//  brique « échelle de qualité » de l'ABR maison du lecteur TV — quand la
//  connexion ne suit plus (cf. stream_stability_monitor.dart), on bascule
//  sur la déclinaison JUSTE EN DESSOUS de la même chaîne au lieu de laisser
//  l'image geler ; quand la connexion redevient stable, on remonte.
//
//  Logique PURE (zéro I/O, zéro Flutter) : testable sur des noms réels
//  (cf. test/features/tv/data/quality_ladder_test.dart).
// =========================================================

import '../../channels/domain/channel.dart';

/// Outils de correspondance entre déclinaisons de qualité d'une chaîne.
abstract final class QualityLadder {
  /// Rang de « poids » d'une qualité (plus grand = plus de débit requis).
  static int rankOf(ChannelQuality q) {
    switch (q) {
      case ChannelQuality.sd:
        return 0;
      case ChannelQuality.hd:
        return 1;
      case ChannelQuality.fhd:
        return 2;
      case ChannelQuality.q4K:
        return 3;
      case ChannelQuality.q8K:
        return 4;
    }
  }

  /// Jetons de QUALITÉ/CODEC à retirer du nom pour retrouver la chaîne de
  /// base. Retirés uniquement comme jetons ENTIERS (« hd » ne mange pas le
  /// « hd » de « hdtv-golf » grâce à la tokenisation).
  static const Set<String> _qualityTokens = <String>{
    '8k', '4k', 'uhd', '2160', '2160p',
    'fhd', '1080', '1080p', 'fullhd',
    'hd', '720', '720p',
    'sd', '480', '480p', '576', '576p',
    'hevc', 'h265', 'x265', 'h264', 'x264', 'avc',
    'hq', 'lq',
  };

  /// Nom de BASE d'une chaîne : minuscules, accents aplatis, séparateurs
  /// (« | », « - », « · »…) neutralisés, jetons de qualité/codec retirés.
  /// « FR| TF1 FHD (HEVC) » et « fr - tf1 sd » ont le même nom de base.
  static String baseNameOf(String name) {
    String s = name.toLowerCase();
    const Map<String, String> accents = <String, String>{
      'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a',
      'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
      // Exposants fréquents dans les noms IPTV (« TF1 ᴴᴰ »).
      'ᴴ': 'h', 'ᴰ': 'd', 'ᵁ': 'u', 'ᶠ': 'f', 'ˢ': 's',
    };
    accents.forEach((String k, String v) => s = s.replaceAll(k, v));
    // Tout ce qui n'est pas [a-z0-9+] devient un espace (séparateurs de
    // panels : « | », « - », « : », parenthèses, « · », emoji…).
    s = s.replaceAll(RegExp(r'[^a-z0-9+]+'), ' ');
    final List<String> kept = <String>[];
    for (final String tok in s.split(' ')) {
      if (tok.isEmpty) continue;
      if (_qualityTokens.contains(tok)) continue;
      kept.add(tok);
    }
    return kept.join(' ');
  }

  /// Déclinaison de la MÊME chaîne au rang de qualité le plus élevé
  /// STRICTEMENT INFÉRIEUR à celui de [current] — la marche juste en
  /// dessous (UHD → FHD, pas UHD → SD directement : dégradation douce).
  ///
  /// Garde-fous : même source ([Channel.playlistId]), même type (live),
  /// nom de base identique et non vide, URL différente (une « déclinaison »
  /// qui pointe sur le même flux ne changerait rien).
  static Channel? lowerQualitySibling(
    Channel current,
    List<Channel> channels,
  ) {
    final String base = baseNameOf(current.name);
    if (base.isEmpty) return null;
    final int currentRank = rankOf(current.quality);
    Channel? best;
    int bestRank = -1;
    for (final Channel c in channels) {
      if (identical(c, current) || c.id == current.id) continue;
      if (c.playlistId != current.playlistId) continue;
      if (c.isLive != current.isLive) continue;
      if (c.streamUrl == current.streamUrl) continue;
      final int r = rankOf(c.quality);
      if (r >= currentRank) continue;
      if (baseNameOf(c.name) != base) continue;
      if (r > bestRank) {
        best = c;
        bestRank = r;
      }
    }
    return best;
  }
}
