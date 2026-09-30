// =========================================================
//  remote_token.dart — Secret d'appairage de la télécommande
// =========================================================
//  Deux secrets distincts, jamais écrits dans les logs :
//    • le JETON (dans l'adresse du QR) : prouve qu'on a vu l'écran
//      de la box ;
//    • le SECRET DU TÉLÉPHONE (cookie) : prouve qu'on est LE
//      téléphone qui a appairé en premier.
//  Les deux font 128 bits, tirés dans le générateur sécurisé du
//  système (pas `Random()` qui est prévisible). 128 bits = 32
//  caractères hexadécimaux : impossible à deviner en essayant.
// =========================================================

import 'dart:math';

/// Durée de vie d'un appairage. Passé ce délai, PLUS AUCUNE commande
/// n'est acceptée : il faut un nouveau QR. On ne prolonge PAS le délai
/// quand le téléphone envoie des touches (sinon un téléphone oublié
/// resterait maître de la box indéfiniment).
const Duration kRemoteSessionTtl = Duration(minutes: 20);

/// 16 octets → 32 hex. Toujours la même longueur, pour pouvoir comparer
/// en temps constant (voir [constantTimeEquals]).
String newRemoteToken([Random? random]) {
  final Random r = random ?? Random.secure();
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < 16; i++) {
    out.write(r.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

/// Vrai seulement si [a] et [b] sont identiques.
///
/// On compare TOUJOURS jusqu'au bout quand les longueurs sont égales :
/// s'arrêter au premier caractère différent donnerait un indice de temps
/// à quelqu'un qui essaie de deviner le secret octet par octet.
/// (Les longueurs différentes sortent tout de suite : nos secrets font
/// tous 32 caractères, une autre longueur est de toute façon invalide.)
bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  int diff = 0;
  for (int i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
