// =========================================================
//  epg_id.dart — Normalisation des identifiants EPG
// =========================================================
//  POURQUOI (Vague 4). Le XMLTV du panel dit « TF1.fr », Xtream dit
//  « TF1 », un M3U dit « tf1.fr ». Sans normalisation, le pont
//  `epg_aliases` existait déjà… et ne matchait presque rien
//  (matching exact, sensible à la casse). TiviMate, lui, rabote
//  ces variantes. On documente ICI les règles — une seule
//  implémentation, testée sans réseau, pour que le support puisse
//  dire « c'est le fournisseur » vs « c'était le pont ».
//
//  Règles (dans cet ordre, une seule passe) :
//    1. trim des blancs en tête/queue
//    2. minuscules
//    3. on retire UN suffixe TLD courant en fin de chaîne
//       (`.co.uk` d'abord — plus long — puis `.com` `.net` `.org`
//       `.fr` `.tv` `.uk` `.de` `.it` `.es` `.be` `.ch` `.nl`
//       `.pt` `.pl` `.eu` `.info`)
//    4. on retire un point final orphelin (après le strip)
//
//  Exemples :
//    TF1.fr / TF1 / tf1.fr / TF1.COM  →  « tf1 »
//    BBC One.co.uk                    →  « bbc one »
//    tf1.hd                           →  « tf1.hd »  (pas un TLD)
//    xtream-42                        →  « xtream-42 »
//
//  On ne touche PAS aux tirets, espaces internes, ni aux suffixes
//  techniques (.hd, .fhd) : trop de faux positifs sur un bouquet
//  de 900 chaînes. Casse + TLD courant, c'est le gap mesuré.
// =========================================================

/// Identifiants EPG : normalisation unique (pure, sans I/O).
abstract final class EpgId {
  /// Suffixes retirés, plus longs d'abord (`.co.uk` avant `.uk`).
  static const List<String> tldSuffixes = <String>[
    '.co.uk',
    '.com',
    '.net',
    '.org',
    '.info',
    '.fr',
    '.tv',
    '.uk',
    '.de',
    '.it',
    '.es',
    '.be',
    '.ch',
    '.nl',
    '.pt',
    '.pl',
    '.eu',
  ];

  /// Forme canonique d'un id XMLTV / `epg_channel_id` / `tvg-id`.
  /// Chaîne vide si [raw] n'est que des blancs.
  static String normalize(String raw) {
    String s = raw.trim().toLowerCase();
    if (s.isEmpty) return '';
    for (final String suffix in tldSuffixes) {
      if (s.endsWith(suffix) && s.length > suffix.length) {
        s = s.substring(0, s.length - suffix.length);
        break; // UN seul suffixe — « something.fr.com » → « something.fr »
      }
    }
    if (s.endsWith('.')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// True si [a] et [b] désignent le même id après normalisation.
  static bool same(String a, String b) {
    final String na = normalize(a);
    final String nb = normalize(b);
    return na.isNotEmpty && na == nb;
  }
}
