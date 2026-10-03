// =========================================================
//  black_box_redaction.dart — Ce qu'on a le droit d'envoyer
// =========================================================
//  La boîte noire (Réglages → Boîte noire) reste sur la box,
//  telle quelle. La COPIE envoyée au panel, elle, ne doit
//  contenir :
//    • aucune adresse de flux (http, rtsp, chemin /live/…) ;
//    • aucun mot de passe ;
//    • aucun identifiant de compte (utilisateur, jeton, e-mail).
//
//  Les lignes techniques ([SON], mémoire, codec, « passthrough »)
//  ne sont pas des secrets : elles passent mot pour mot. C'est
//  ce texte-là que le revendeur lit dans le panel.
//
//  Même règles que cloudflare/blackbox_journal.js. Les deux
//  tests (Dart et Node) utilisent les mêmes phrases.
//  Aucune dépendance : que du texte.
// =========================================================

import 'dart:convert';

/// Taille max de la copie envoyée. Le journal sur disque peut
/// faire ~1 Mo ; on n'en garde que la fin. 32 Ko restent sous
/// la limite d'une requête D1 (~100 Ko) avec de la marge.
const int kBlackBoxUploadMaxBytes = 32 * 1024;

/// `null` si l'envoi est coupé ou s'il n'y a rien à dire.
/// Sinon : texte masqué, tronqué par la fin (les lignes les
/// plus récentes, celles que l'écran ouvre en bas).
String? prepareBlackBoxUpload(
  String raw, {
  required bool enabled,
  int maxBytes = kBlackBoxUploadMaxBytes,
}) {
  if (!enabled) return null;
  // Filet : on ne parcourt pas un journal énorme en entier.
  // La fin contient les lignes récentes.
  final String capped =
      raw.length > 256 * 1024 ? raw.substring(raw.length - 256 * 1024) : raw;
  final String clean = truncateBlackBoxTail(redactBlackBox(capped), maxBytes);
  if (clean.trim().isEmpty) return null;
  return clean;
}

/// Remplace les secrets par des marques stables (`[lien]`,
/// `[masqué]`, `[identifiants]`). Un deuxième passage ne
/// change plus le texte : on peut filtrer côté box ET côté
/// serveur sans abîmer les lignes déjà propres.
String redactBlackBox(String input) {
  var text = input;
  text = text.replaceAll(_url, '[lien]');
  text = text.replaceAll(_userInfo, '[identifiants]');
  text = text.replaceAllMapped(_pathCreds, (Match m) {
    return '/${m.group(1)}/[masqué]/[masqué]/';
  });
  text = text.replaceAllMapped(_secretField, (Match m) {
    return '${m.group(1)}=[masqué]';
  });
  text = text.replaceAllMapped(_accountLabel, (Match m) {
    return '${m.group(1)} [masqué]';
  });
  text = text.replaceAll(_email, '[identifiant]');
  return text;
}

/// Garde la FIN du texte, au plus [maxBytes] octets UTF-8.
/// On jette le début de la première ligne coupée pour que le
/// panel ne s'ouvre pas au milieu d'un mot.
String truncateBlackBoxTail(String text, int maxBytes) {
  if (maxBytes <= 0) return '';
  final List<int> bytes = utf8.encode(text);
  if (bytes.length <= maxBytes) return text;
  var slice = bytes.sublist(bytes.length - maxBytes);
  // Un octet 10xxxxxx est la suite d'un caractère coupé : on
  // l'enlève pour ne pas afficher un caractère cassé.
  var i = 0;
  while (i < slice.length && (slice[i] & 0xC0) == 0x80) {
    i++;
  }
  if (i > 0) slice = slice.sublist(i);
  var s = utf8.decode(slice, allowMalformed: true);
  final int nl = s.indexOf('\n');
  if (nl >= 0 && nl < s.length - 1) s = s.substring(nl + 1);
  return s;
}

// Adresse complète : schéma + reste jusqu'à l'espace. Couvre
// le lien M3U et le lien Xtream, y compris utilisateur:mot@hôte.
final RegExp _url = RegExp(
  r'''\b(?:https?|rtsps?|rtmps?|udp|rtp|mms|mmsh):\/\/[^\s<>"'()]+''',
  caseSensitive: false,
);

// utilisateur:mot@hôte écrit sans schéma.
final RegExp _userInfo = RegExp(
  r'\b[^:\s/@]{1,80}:[^:\s/@]{1,80}@[\w.-]+(?::\d+)?',
);

// /live/compte/mot/  (idem movie, series) — le chemin seul,
// quand l'adresse a été coupée avant le schéma.
final RegExp _pathCreds = RegExp(
  r'/(live|movie|series)/[^/\s]+/[^/\s]+/',
  caseSensitive: false,
);

// password=…, username=…, token: … Les mots longs d'abord
// pour que « password » ne soit pas lu comme « pass ».
final RegExp _secretField = RegExp(
  r'\b(password|passwd|pwd|username|user|login|token|auth|pass)\b\s*[:=]\s*[^\s&,;]+',
  caseSensitive: false,
);

// Fil d'Ariane déjà écrit par l'app : « utilisateur COMPTE ».
final RegExp _accountLabel = RegExp(
  r'\b(utilisateur|identifiant)\b\s*[:=]?\s+\S+',
  caseSensitive: false,
);

final RegExp _email = RegExp(
  r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
  caseSensitive: false,
);
