// =========================================================
//  assistance_miroir.dart — voir l'écran du client, pour de vrai
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (19/09/2026), après avoir essayé le doigt
//  sur sa vraie box :
//
//    « Ça marche, mais je vois pas l'écran. Ça pointe bien, mais je
//      vois rien côté admin. »
//
//  Il a raison, et je le lui avais dit comme une limite acceptable :
//  « tu ne vois pas ses pixels, tu vois ce que l'appareil répond ».
//  Sauf qu'en vrai, montrer du doigt SANS voir, c'est viser dans le
//  noir. Le support dit « regarde en haut à droite » sans savoir ce
//  qu'il y a en haut à droite.
//
//  ---------------------------------------------------------
//  CE QUE CE MIROIR MONTRE — ET CE QU'IL NE MONTRERA PAS
//  ---------------------------------------------------------
//  Il capture ce que FLUTTER dessine : menus, listes de chaînes,
//  réglages, focus de la télécommande, boîtes de dialogue. Tout ce
//  dont le support a besoin pour « je ne trouve pas les favoris ».
//
//  LA VIDÉO, ELLE, SORTIRA NOIRE. Ce n'est pas un bug à corriger plus
//  tard, c'est ainsi que fonctionne Android : le lecteur ne dessine
//  pas dans l'arbre Flutter, il peint dans une surface matérielle que
//  le processeur graphique compose PAR-DESSOUS. `toImage()` ne la voit
//  pas. La capturer demanderait MediaProjection — une autorisation
//  système que le client doit accorder à CHAQUE fois, ce qui tuerait
//  le « automatique » qu'il vient de me demander.
//
//  C'EST DIT DANS LE PANEL, sous l'image. Un support qui croirait voir
//  une chaîne plantée alors qu'elle joue très bien raccrocherait en
//  ayant « diagnostiqué » un problème qui n'existe pas.
//
//  ---------------------------------------------------------
//  POURQUOI CE FICHIER EST À PART, ET PRESQUE PUR
//  ---------------------------------------------------------
//  Les deux décisions qui coûtent cher ici sont des CALCULS : quelle
//  taille d'image, et à quelle cadence. Les mettre dans un widget
//  voudrait dire ne jamais pouvoir les tester, et les régler à
//  l'oreille — sur une box qu'on n'a pas sous la main.
// =========================================================

import 'dart:typed_data';
import 'dart:ui' as ui;

// TROIS IMPORTS, et chacun sert : ce fichier fait le pont entre un
// widget et son rendu. `GlobalKey` vient de widgets.dart, la classe
// `RenderRepaintBoundary` — celle qui sait rendre son image — de
// rendering.dart, et `kDebugMode` de foundation.dart. Aucune des trois
// n'exporte les autres.
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Largeur maximale de l'image envoyée, en pixels.
///
///  420 px : assez pour LIRE un menu et repérer où est le focus, pas
///  assez pour peser lourd. Une télé fait 1920 px de large ; envoyer
///  ça toutes les deux secondes, c'est 8 fois plus d'octets pour une
///  information que le support n'utilise pas — il ne lit pas les
///  sous-titres, il cherche un bouton.
const double largeurMiroir = 420;

/// Combien de temps entre deux images.
///
///  DEUX SECONDES, ET C'EST UN COMPROMIS ASSUMÉ. Plus rapide, la box
///  passe son temps à encoder du PNG au lieu de décoder de la vidéo —
///  et ces box-là ont déjà du mal. Plus lent, le support clique et
///  attend sans savoir si son geste a pris.
///
///  Le journal des accusés, lui, répond en moins d'une seconde : c'est
///  lui qui dit « fait », l'image ne fait que MONTRER.
const Duration periodeMiroir = Duration(seconds: 2);

/// Au-delà, on jette l'image au lieu de l'envoyer.
///
///  Le hub refuse les frames trop grosses ; une image refusée coûte
///  toute l'encodage ET toute la montée réseau pour rien. Mieux vaut
///  s'en apercevoir ici, sauter ce tour, et laisser le suivant passer.
const int poidsMaxMiroir = 90 * 1024;

/// Le facteur d'échelle à demander à `toImage()` pour obtenir une
/// image d'au plus [largeurMax] pixels de large.
///
///  ON NE GROSSIT JAMAIS. Sur un téléphone en 360 points de large, un
///  ratio supérieur à 1 fabriquerait des pixels qui n'existent pas :
///  plus d'octets, pas un détail de plus. D'où le plafond à 1.
///
///  Une largeur absurde (0, négative, NaN) rend 1 plutôt que de jeter :
///  une image à la mauvaise taille reste utile, une exception au milieu
///  d'une session d'assistance ne l'est pas.
double ratioMiroir(double largeurLogique, {double largeurMax = largeurMiroir}) {
  //  `isFinite` EN PLUS DE `> 0`, et c'est un test qui me l'a appris :
  //  l'infini est bien « supérieur à 0 », donc il passait la garde, et
  //  420 / infini rend ZÉRO. On aurait demandé au moteur graphique une
  //  image à l'échelle 0 — c'est-à-dire rien, ou une exception, au
  //  milieu d'une assistance.
  if (!largeurLogique.isFinite || largeurLogique <= 0) return 1;
  if (!largeurMax.isFinite || largeurMax <= 0) return 1;
  final double r = largeurMax / largeurLogique;
  //  Et une dernière ceinture : si le calcul rendait malgré tout
  //  quelque chose d'inutilisable, on préfère l'échelle 1 — une image
  //  trop grande reste une image, une image à l'échelle 0 n'est rien.
  if (!r.isFinite || r <= 0) return 1;
  return r > 1 ? 1 : r;
}

/// Capture ce qui est dessiné sous [cle], en PNG.
///
///  Rend `null` — jamais une exception — dans tous les cas où l'on ne
///  peut PAS capturer proprement :
///   • l'arbre n'est pas encore monté (l'app démarre) ;
///   • la zone n'a pas fini de se peindre (`debugNeedsPaint`) : lui
///     demander son image la ferait jeter ;
///   • l'image dépasse [poidsMaxMiroir] ;
///   • n'importe quelle erreur du moteur graphique.
///
///  UNE IMAGE MANQUÉE N'EST PAS UN INCIDENT : la suivante arrive dans
///  deux secondes. Faire remonter ça comme une panne inquiéterait le
///  support pour rien, au pire moment — pendant qu'il a un client au
///  téléphone.
Future<ImageMiroir?> capturerMiroir(GlobalKey cle) async {
  try {
    final RenderObject? ro = cle.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) return null;
    if (ro.debugNeedsPaint) return null;
    final ui.Size taille = ro.size;
    if (!(taille.width > 0) || !(taille.height > 0)) return null;

    final ui.Image img = await ro.toImage(
      pixelRatio: ratioMiroir(taille.width),
    );
    try {
      final ByteData? d = await img.toByteData(format: ui.ImageByteFormat.png);
      if (d == null) return null;
      final Uint8List octets = d.buffer.asUint8List();
      if (octets.length > poidsMaxMiroir) return null;
      return ImageMiroir(
        octets: octets,
        largeur: img.width,
        hauteur: img.height,
      );
    } finally {
      // Sans ça, chaque capture laisse une image en mémoire graphique.
      // Toutes les deux secondes, sur une box à 1 Go, ça finit mal.
      img.dispose();
    }
  } catch (e) {
    if (kDebugMode) debugPrint('[Miroir] capture: $e');
    return null;
  }
}

/// Une image prête à partir.
@immutable
class ImageMiroir {
  const ImageMiroir({
    required this.octets,
    required this.largeur,
    required this.hauteur,
  });

  final Uint8List octets;
  final int largeur;
  final int hauteur;
}
