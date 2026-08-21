// =========================================================
//  tv_ambience.dart — AMBIANCES INTELLIGENTES (le Caméléon, organe 1)
// =========================================================
//  L'app « sent » ce que le client regarde et change d'ATMOSPHÈRE toute
//  seule, en fondu lent : la lumière du fond « Verre Noir » glisse vers
//  la teinte de l'univers ouvert — et, depuis le blueprint Caméléon du
//  20/08, vers la couleur RÉELLE du contenu (extraite de l'affiche par
//  chameleon_extractor) tempérée par l'heure (circadian_rhythm).
//
//    • MAISON   : clair de lune (accueil, direct, réglages) — l'ADN verre.
//    • CINÉMA   : braise de projecteur… ou la couleur de l'affiche ouverte.
//    • SÉRIES   : nuit indigo (marathon sous la couette).
//    • SPORT    : pelouse nocturne (vert stade très sombre).
//
//  RÈGLES D'OR (inchangées) :
//    - on ne touche QUE la lumière du fond (gradient TvShell). L'accent
//      des focus ne bouge JAMAIS → la marque reste la marque ;
//    - les teintes restent des NOIRS teintés — le Gouverneur borne tout
//      (aucun flash, aucun éblouissement, pensé pour le soir) ;
//    - zéro contact avec le lecteur vidéo (il vit hors TvShell) ;
//    - tout se calcule en OKLab (jamais de « zone morte » grise).
// =========================================================
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../core/color/chameleon_extractor.dart';
import '../../../core/color/circadian_rhythm.dart';
import '../../../core/color/oklab.dart';

/// Les univers d'ambiance. Volontairement PEU nombreux : une ambiance
/// se ressent, elle ne se remarque pas.
enum TvAmbienceKind { maison, cinema, serie, sport }

class TvAmbience extends ChangeNotifier {
  TvAmbience._();
  static final TvAmbience instance = TvAmbience._();

  // PAS d'horloge interne (Timer.periodic) : le vecteur circadien est
  // évalué PARESSEUSEMENT à chaque lecture de [glow] — chaque rebuild
  // naturel (navigation, changement d'univers, fiche ouverte) applique
  // donc la température du moment, et la dérive d'une heure entière est
  // de toute façon imperceptible entre deux interactions. Un timer
  // singleton aurait en prime fait échouer chaque test widget qui monte
  // l'app (« A Timer is still pending » à la fin du test).

  TvAmbienceKind _kind = TvAmbienceKind.maison;
  TvAmbienceKind get kind => _kind;

  /// Couleur GOUVERNÉE du contenu regardé (affiche du film ouvert), posée
  /// par l'écran de fiche via [feedContentAccent]. null = pas de contenu
  /// mis en avant → ambiance de l'univers.
  Oklch? _contentAccent;
  Oklch? get contentAccent => _contentAccent;

  /// Change d'univers (no-op si identique — pas de rebuild inutile).
  void set(TvAmbienceKind k) {
    if (k == _kind) return;
    _kind = k;
    notifyListeners();
  }

  /// Nourrit l'ambiance avec la couleur GOUVERNÉE d'un contenu (résultat
  /// de chameleon_extractor). null = le contenu quitte l'écran.
  /// Seuil anti-scintillement : une couleur quasi identique à l'actuelle
  /// (ΔE < stabilityDeltaE) est ignorée — zéro mutation d'interface.
  void feedContentAccent(Oklch? accent) {
    final Oklch? current = _contentAccent;
    if (accent == null && current == null) return;
    if (accent != null &&
        current != null &&
        accent.toOklab().deltaE(current.toOklab()) <
            ChameleonGovernor.stabilityDeltaE) {
      return;
    }
    _contentAccent = accent;
    notifyListeners();
  }

  /// Lumière de base de chaque univers, EN OKLCH (des noirs teintés —
  /// la clarté finale est modulée par l'intensité circadienne).
  Oklch get _baseGlow {
    switch (_kind) {
      case TvAmbienceKind.maison:
        return const Oklch(0.20, 0.030, 250); // clair de lune (ADN verre)
      case TvAmbienceKind.cinema:
        return const Oklch(0.19, 0.035, 35); // braise de projecteur
      case TvAmbienceKind.serie:
        return const Oklch(0.19, 0.035, 290); // nuit indigo
      case TvAmbienceKind.sport:
        return const Oklch(0.19, 0.030, 155); // pelouse nocturne
    }
  }

  /// Couleur de la « lumière » du fond (arrêt 0 du dégradé radial TvShell).
  /// Chaîne complète du Caméléon : contenu (s'il y en a un) → noir teinté →
  /// tempérage circadien → intensité du soir → écrêtage de gamut → sRGB.
  Color get glow {
    final DateTime now = DateTime.now();
    final CircadianState circadian =
        circadianStateAt(now.hour + now.minute / 60);
    final Oklch? accent = _contentAccent;
    Oklch g;
    if (accent != null) {
      // Le CONTENU commande : sa teinte, ramenée à un NOIR teinté (le fond
      // n'est jamais une couleur vive — règle d'or) ; l'heure infléchit 25 %.
      g = temperByCircadian(
        Oklch(0.19, (accent.c * 0.45).clamp(0.0, 0.05).toDouble(), accent.h),
        circadian,
      );
    } else if (_kind == TvAmbienceKind.maison) {
      // MAISON sans contenu : c'est L'HEURE qui commande (retour client du
      // 21/08 : « la nuit, le jour, c'est le même thème » — le tempérage à
      // 25 % était imperceptible). L'accueil suit franchement la journée :
      // bleu d'acier à l'aube, neutre l'après-midi, doré le soir, ambre la
      // nuit. Toujours un noir teinté : le Gouverneur borne juste après.
      g = Oklch(0.20, circadian.chroma, circadian.hueDeg);
    } else {
      // Univers thématiques (Cinéma, Séries, Sport) : leur identité prime,
      // l'heure infléchit (25 %).
      g = temperByCircadian(_baseGlow, circadian);
    }
    // Le soir, l'aura s'intensifie (glow 0.06 → 0.18 sur la journée).
    final double l = (g.l + circadian.glow * 0.22).clamp(0.12, 0.26).toDouble();
    return Color(oklabToSrgb(clampChroma(Oklch(l, g.c, g.h)).toOklab()).argb);
  }
}
