// =========================================================
//  tv_ambience.dart — AMBIANCES INTELLIGENTES (immersion)
// =========================================================
//  L'app « sent » ce que le client regarde et change d'ATMOSPHÈRE toute
//  seule, en fondu lent (~1,6 s) : la lumière du fond « Maison Noir »
//  glisse vers la teinte de l'univers ouvert —
//
//    • MAISON   : or champagne (accueil, direct, réglages) — l'ADN.
//    • CINÉMA   : ambre de projecteur, plus rouge et plus profond.
//    • SÉRIES   : nuit indigo (marathon sous la couette).
//    • SPORT    : pelouse nocturne (vert stade très sombre).
//
//  RÈGLES D'OR :
//    - on ne touche QUE la lumière du fond (gradient TvShell). L'or des
//      accents/focus ne bouge JAMAIS → la marque reste la marque ;
//    - les teintes restent des NOIRS teintés (aucun flash, aucun
//      éblouissement — pensé pour le client fatigué du soir) ;
//    - zéro contact avec le lecteur vidéo (il vit hors TvShell).
// =========================================================
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Les univers d'ambiance. Volontairement PEU nombreux : une ambiance
/// se ressent, elle ne se remarque pas.
enum TvAmbienceKind { maison, cinema, serie, sport }

class TvAmbience extends ChangeNotifier {
  TvAmbience._();
  static final TvAmbience instance = TvAmbience._();

  TvAmbienceKind _kind = TvAmbienceKind.maison;
  TvAmbienceKind get kind => _kind;

  /// Change d'univers (no-op si identique — pas de rebuild inutile).
  void set(TvAmbienceKind k) {
    if (k == _kind) return;
    _kind = k;
    notifyListeners();
  }

  /// Couleur de la « lumière » du fond (arrêt 0 du dégradé radial).
  /// Toujours un noir teinté — jamais une couleur vive.
  Color get glow {
    switch (_kind) {
      case TvAmbienceKind.maison:
        return const Color(0xFF191510); // or champagne (ADN)
      case TvAmbienceKind.cinema:
        return const Color(0xFF1D120C); // ambre de projecteur
      case TvAmbienceKind.serie:
        return const Color(0xFF15101F); // nuit indigo
      case TvAmbienceKind.sport:
        return const Color(0xFF0E1912); // pelouse nocturne
    }
  }
}
