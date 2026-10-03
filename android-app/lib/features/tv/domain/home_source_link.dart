// =========================================================
//  home_source_link.dart — Lien du QR « j'ajoute ma source »
// =========================================================
//  Fonctions pures : pas de Flutter, pas de réseau. L'écran TV
//  s'en sert pour dessiner le QR, les tests pour vérifier qu'on
//  n'invente aucune adresse de flux.
//
//  Le lien ouvre la page DÉJÀ servie par le Worker (`/mon-espace`).
//  La base est celle de l'application (kSubscriptionBaseUrl), pas
//  un serveur de chaînes. Le fragment porte la MAC (en clair, les
//  « : » ne sont pas encodés) et, quand la box a pu le déclarer,
//  un code court de 20 minutes.
//
//  Alphabet, longueur et délai : identiques à
//  cloudflare/source_pair.js.
// =========================================================

import 'dart:math';

/// Signes faciles à lire sur une télé : pas de 0/O, pas de 1/I.
const String kHomeSourcePairAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// Six signes : assez court pour l'écran, assez long pour 20 minutes.
const int kHomeSourcePairLength = 6;

/// Même fenêtre que SOURCE_PAIR_TTL_MS côté Worker.
const Duration kHomeSourcePairTtl = Duration(minutes: 20);

final RegExp _macRx = RegExp(r'^MK(?::[0-9A-F]{2}){5}$');
final RegExp _pairRx = RegExp('^[$kHomeSourcePairAlphabet]{$kHomeSourcePairLength}\$');

/// Vrai seulement pour un code de la bonne longueur et du bon alphabet.
bool homeSourcePairCodeOk(String? code) {
  return _pairRx.hasMatch((code ?? '').trim().toUpperCase());
}

/// Tire un code. [random] est injecté dans les tests.
String mintHomeSourcePairCode(Random random) {
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < kHomeSourcePairLength; i++) {
    out.write(
      kHomeSourcePairAlphabet[random.nextInt(kHomeSourcePairAlphabet.length)],
    );
  }
  return out.toString();
}

/// URL à mettre dans le QR.
///
/// Retourne `null` si la base n'est pas http(s) ou si la MAC n'a pas
/// la forme MK:XX:XX:XX:XX:XX. Un code illisible est ignoré : on
/// garde quand même le lien avec la MAC (les box pas encore enrôlées
/// acceptent la page sans code).
String? homeSourcePortalUrl({
  required String baseUrl,
  required String mac,
  String? pair,
}) {
  final String base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  if (!base.startsWith('http://') && !base.startsWith('https://')) {
    return null;
  }
  final String upper = mac.trim().toUpperCase();
  if (!_macRx.hasMatch(upper)) return null;
  // Fragment, pas le chemin : les « : » restent lisibles et le
  // Worker ne les voit pas tant que la page ne les renvoie pas.
  final StringBuffer hash = StringBuffer('#mac=$upper');
  final String code = (pair ?? '').trim().toUpperCase();
  if (homeSourcePairCodeOk(code)) {
    hash.write('&pair=$code');
  }
  return '$base/mon-espace$hash';
}
