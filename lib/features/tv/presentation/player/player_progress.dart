// =========================================================
//  player_progress.dart — la lecture d'une durée, sans Flutter
// =========================================================
//  Extrait de la barre de contrôle du lecteur PC pour une seule raison :
//  ces trois règles sont celles qui se trompent en silence. Une durée mal
//  formatée, une barre de progression qui déborde, un direct pris pour un
//  film — rien de tout ça ne plante, ça s'affiche simplement faux. Un
//  test les attrape ; un coup d'œil sur une capture d'écran, non.
//
//  Fonctions PURES : aucun widget, aucun lecteur. C'est ce qui les rend
//  vérifiables sans lancer l'application.
// =========================================================

/// Un flux EN DIRECT n'a pas de fin connue.
///
/// libmpv rend alors une durée nulle — parfois une poignée de secondes le
/// temps que le tampon se remplisse. On considère donc « direct » tout ce
/// qui est en dessous d'une seconde : afficher « 0:03 / 0:00 » sur une
/// chaîne de télévision n'aurait aucun sens, et une barre de progression
/// y serait un mensonge (elle laisserait croire qu'on peut avancer).
bool estDirect(Duration duree) => duree.inMilliseconds < 1000;

/// Avancement entre 0 et 1, borné.
///
/// Le bornage n'est pas de la coquetterie : sur un flux live, la position
/// dépasse régulièrement la durée annoncée (le tampon a de l'avance).
/// Sans borne, la barre sortirait de son cadre.
double progression(Duration position, Duration duree) {
  if (estDirect(duree)) return 0;
  final double p = position.inMilliseconds / duree.inMilliseconds;
  if (p.isNaN || p < 0) return 0;
  return p > 1 ? 1 : p;
}

/// Fraction 0..1 correspondant à une abscisse sur la réglette.
///
/// La souris SORT de la piste pendant un glisser : on continue de recevoir
/// des abscisses négatives, ou plus grandes que la largeur, tant que le
/// bouton reste enfoncé. Sans bornage, la poignée s'échapperait du cadre et
/// le saut demandé serait hors du film.
///
/// Une largeur nulle arrive pour de vrai : c'est la toute première image,
/// avant que Flutter ait mesuré la fenêtre. Diviser par elle donnerait NaN,
/// et un NaN dans une largeur fait une exception de rendu, pas un dessin
/// approximatif.
double ratioDepuisX(double dx, double largeur) {
  if (largeur <= 0 || dx.isNaN) return 0;
  final double r = dx / largeur;
  if (r < 0) return 0;
  return r > 1 ? 1 : r;
}

/// Endroit du film visé par une fraction de la réglette.
///
/// Bornée elle aussi : libmpv accepte qu'on lui demande une position
/// négative ou au-delà de la fin, et ne revient pas toujours proprement de
/// l'état où ça le met. Le clic sur l'extrémité droite de la barre est le
/// cas qu'on rencontre tous les jours.
Duration positionDepuisRatio(double ratio, Duration duree) {
  if (estDirect(duree)) return Duration.zero;
  final double r = ratio.isNaN ? 0 : (ratio < 0 ? 0 : (ratio > 1 ? 1 : ratio));
  return Duration(milliseconds: (r * duree.inMilliseconds).round());
}

/// Position obtenue en avançant (ou reculant) de quelques secondes.
///
/// Le recul de 10 s dans les dix premières secondes du film doit ramener au
/// tout début, pas avant : « avant » n'existe pas.
Duration positionApresSaut(Duration position, Duration duree, int secondes) {
  if (estDirect(duree)) return position;
  final Duration cible = position + Duration(seconds: secondes);
  if (cible < Duration.zero) return Duration.zero;
  return cible > duree ? duree : cible;
}

/// « 4:07 » ou « 1:02:07 ».
///
/// On n'affiche l'heure QUE si elle existe : « 0:04:07 » pour quatre
/// minutes se lit moins bien que « 4:07 », et sur une télé regardée de
/// loin, chaque caractère inutile est un caractère de trop.
///
/// Une durée négative (position inconnue au tout début) devient « 0:00 »
/// plutôt qu'un « -1:59 » incompréhensible.
String formatDuree(Duration d) {
  final int total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final int h = total ~/ 3600;
  final int m = (total % 3600) ~/ 60;
  final int s = total % 60;
  final String ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}
