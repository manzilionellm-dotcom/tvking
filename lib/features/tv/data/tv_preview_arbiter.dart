// =========================================================
//  tv_preview_arbiter.dart — UN SEUL aperçu vivant dans l'app
// =========================================================
//  DEMANDE CLIENT (2026-08-01) : « si je passe du template A au B, tout
//  doit s'arrêter d'un coup pour que B travaille bien — comme des états
//  indépendants. Sinon les vidéos traînent à ouvrir, comme si on
//  regardait deux choses en même temps, alors que c'est faux. »
//
//  C'était exactement ce qui se passait : l'écran quitté n'avait pas fini
//  de rendre son décodeur (release MediaCodec = asynchrone) que le nouvel
//  écran ouvrait déjà son flux. Deux décodeurs + DEUX connexions chez le
//  fournisseur (comptes « 1 connexion » → la seconde est refusée) → le
//  nouvel aperçu mettait des secondes à venir, ou ne venait jamais.
//
//  L'arbitre impose une règle simple et vérifiable : à tout instant, UN
//  SEUL aperçu possède le créneau. Quand un nouvel écran le prend :
//    • l'ancien propriétaire est prévenu et libère TOUT DE SUITE ;
//    • le nouveau attend une brève PASSATION ([handover]) — le temps que
//      le décodeur matériel soit réellement rendu — puis ouvre ;
//    • si PERSONNE ne jouait (ouverture à froid, cas le plus courant),
//      l'attente est NULLE : l'image part instantanément.
//
//  Pur, sans plugin ni réseau → testable de bout en bout.
// =========================================================
import 'package:flutter/foundation.dart';

class TvPreviewArbiter extends ChangeNotifier {
  TvPreviewArbiter._();
  static final TvPreviewArbiter instance = TvPreviewArbiter._();

  /// Fabrique une instance INDÉPENDANTE (tests) — l'app utilise [instance].
  @visibleForTesting
  factory TvPreviewArbiter.forTest() = TvPreviewArbiter._;

  /// Délai de passation quand on prend le créneau à quelqu'un d'autre :
  /// `release()` côté ExoPlayer/MediaCodec n'est pas instantané. Assez
  /// court pour rester imperceptible, assez long pour ne pas empiler deux
  /// décodeurs sur une petite box.
  static const Duration handover = Duration(milliseconds: 250);

  Object? _owner;

  /// Propriétaire courant du créneau (`null` = personne ne joue).
  Object? get owner => _owner;

  /// `true` si [token] possède le créneau — les aperçus s'en servent pour
  /// se libérer d'eux-mêmes dès qu'un autre écran prend la main.
  bool holds(Object token) => identical(_owner, token);

  /// [token] prend le créneau. Renvoie le délai à respecter AVANT d'ouvrir
  /// le flux : `Duration.zero` si personne ne jouait (ouverture instantanée),
  /// [handover] si on vient de déloger un autre aperçu.
  Duration acquire(Object token) {
    if (identical(_owner, token)) return Duration.zero;
    final bool hadOther = _owner != null;
    _owner = token;
    // L'ancien propriétaire libère en voyant cette notification.
    notifyListeners();
    return hadOther ? handover : Duration.zero;
  }

  /// [token] rend le créneau (sortie d'écran, mise en pause, plein écran).
  /// Rendre un créneau qu'on ne possède PAS est sans effet : un écran en
  /// train de mourir ne doit jamais couper l'écran qui vient de naître.
  void release(Object token) {
    if (!identical(_owner, token)) return;
    _owner = null;
    notifyListeners();
  }
}
