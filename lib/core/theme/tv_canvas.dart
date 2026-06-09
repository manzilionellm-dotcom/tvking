// =========================================================
//  tv_canvas.dart — Canevas de mise à l'échelle pour la TÉLÉVISION
// =========================================================
//  POURQUOI ce fichier existe ?
//  ----------------------------------------------------------
//  Toute l'UI TV de l'app est dessinée avec des tailles FIXES en dp
//  (ex. `fontSize: 44`, `maxWidth: 860`, des `SizedBox(height: 46)`…).
//  Ces valeurs ont été calibrées pour une « 10-foot UI » Android TV
//  classique, dont la largeur logique de référence est ~960 dp
//  (1920 px ÷ densité 2.0).
//
//  PROBLÈME : selon le boîtier (SHIELD, Fire TV, box Android chinoise,
//  Google TV…), Android annonce une LARGEUR LOGIQUE très différente :
//  certains rapportent 960 dp, d'autres 1280, d'autres carrément
//  1920 dp (densité 1.0). Résultat : un contenu plafonné à 860 dp
//  n'occupe qu'~45 % d'un écran qui se croit large de 1920 dp →
//  l'interface paraît minuscule et tassée au centre, avec du vide
//  partout. C'est exactement ce que l'utilisateur a constaté sur sa
//  grande TV.
//
//  SOLUTION : un « canevas de design » à largeur CONSTANTE. On déclare
//  que, peu importe ce que le boîtier annonce, l'app est dessinée sur
//  une toile de [kDesignWidth] dp de large (même ratio d'écran que le
//  réel), puis on met cette toile à l'échelle pour REMPLIR l'écran
//  physique. Conséquences :
//    - Les proportions sont IDENTIQUES sur toutes les TV (12″ → 100″).
//    - Plus aucun écran ne paraît « perdu » au centre : tout grandit
//      proportionnellement à la taille réelle de l'écran.
//    - Aucun refactor écran par écran : on monte ce canevas UNE fois,
//      à la racine, et toute l'app en hérite.
//
//  C'est la technique classique des apps TV (équivalent maison de
//  `flutter_screenutil`, mais sans ajouter de dépendance — cf.
//  AGENTS.md « pas de magie noire »).
//
//  PÉRIMÈTRE : réservé au build TV (`main_tv.dart`, mode forcé TV). Le
//  téléphone garde son rendu natif 1:1 (il n'a pas ce problème — sa
//  densité d'écran est correctement rapportée par Android). Le montage
//  est donc gardé par `DeviceClassRepository.isForcedTv` côté appelant.
// =========================================================

import 'package:flutter/widgets.dart';

/// Enveloppe la totalité de l'app TV dans un canevas à largeur de
/// référence constante, mis à l'échelle pour remplir l'écran réel.
///
/// À insérer dans le `builder:` de `MaterialApp` (donc AU-DESSUS du
/// Navigator → tous les écrans, dialogs et SnackBars en héritent).
class TvCanvas extends StatelessWidget {
  const TvCanvas({
    super.key,
    required this.mediaQuery,
    required this.child,
  });

  /// Le [MediaQueryData] déjà préparé par l'appelant (typiquement avec
  /// le `textScaler` clampé). On le réutilise tel quel, en ne modifiant
  /// que la `size` pour refléter le canevas.
  final MediaQueryData mediaQuery;

  /// L'arbre de l'app (le Navigator de MaterialApp).
  final Widget child;

  /// Largeur de référence du canevas 10-foot, en dp de design.
  ///
  /// 960 dp = la mesure canonique d'une interface Android TV (1080p
  /// rendu à densité 2.0). Toutes les tailles en dur de l'UI TV ont
  /// été pensées pour cette largeur ; on la fige donc ici comme
  /// référence absolue, puis on met à l'échelle vers l'écran réel.
  static const double kDesignWidth = 960.0;

  @override
  Widget build(BuildContext context) {
    final Size real = mediaQuery.size;

    // Garde-fou : si la taille n'est pas encore connue (premier frame,
    // mesure dégénérée), on ne tente aucune mise à l'échelle et on rend
    // l'app telle quelle. Évite une division par zéro / un NaN.
    if (real.width <= 0 || real.height <= 0) {
      return MediaQuery(data: mediaQuery, child: child);
    }

    // Facteur d'échelle : combien de pixels RÉELS pour 1 unité de
    // DESIGN. Ex. écran réel de 1920 dp → scale = 2.0 → tout l'UI est
    // peint 2× plus grand. Écran réel de 960 dp → scale = 1.0 → rendu
    // inchangé (cas « TV déjà bien calibrée »).
    final double scale = real.width / kDesignWidth;

    // Taille du canevas en unités de DESIGN. On garde EXACTEMENT le même
    // ratio que l'écran réel (on divise les deux dimensions par le même
    // `scale`), donc aucune déformation : la hauteur s'ajuste au format
    // de la TV (16:9, 18:9, ultrawide…).
    final Size design = Size(real.width / scale, real.height / scale);

    return MediaQuery(
      // Les descendants « voient » la taille du CANEVAS (960 dp de
      // large), pas celle de l'écran réel. Ainsi tous les calculs
      // responsives internes (nombre de colonnes d'une grille, etc.)
      // partent d'une base STABLE et identique sur toutes les TV.
      data: mediaQuery.copyWith(size: design),
      child: FittedBox(
        // `BoxFit.fill` étire le canevas pour remplir les contraintes
        // réelles. Comme `design` a le même ratio que l'écran réel,
        // « fill » revient ici à un agrandissement UNIFORME (pas de
        // distorsion) : le facteur horizontal == le facteur vertical.
        fit: BoxFit.fill,
        child: SizedBox(
          width: design.width,
          height: design.height,
          child: child,
        ),
      ),
    );
  }
}
