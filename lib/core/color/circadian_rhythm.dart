// =========================================================
//  circadian_rhythm.dart — Le vecteur circadien (Dart pur)
// =========================================================
//  La « température » de l'interface suit la journée : bleu d'acier à
//  l'aube, quasi neutre au pic d'attention de l'après-midi, doré le soir,
//  ambre profond la nuit (protection de la mélatonine — et c'est le soir
//  que l'écran devient la source de lumière dominante de la pièce, donc
//  que l'aura se voit).
//
//  PAS un `if (heure > 18)` : une table d'ANCRES interpolées en continu.
//  L'interpolation se fait en CARTÉSIEN OKLab (a/b) — jamais sur l'angle
//  de teinte : entre le bleu (250°) et l'ambre (75°), interpoler l'angle
//  balaierait le vert ; en cartésien, la trajectoire plonge doucement
//  vers le neutre puis remonte. Le test « aucun vert saturé sur 24 h »
//  verrouille exactement cette propriété.
//
//  Fonction PURE du temps → testable minute par minute sans horloge.
// =========================================================
import 'dart:math' as math;

import 'oklab.dart';

/// État ambiant à un instant : teinte (°), chroma ambiante, intensité
/// de l'aura (0–0.25, consommée par l'ambiance de fond).
class CircadianState {
  const CircadianState({
    required this.hueDeg,
    required this.chroma,
    required this.glow,
  });
  final double hueDeg;
  final double chroma;
  final double glow;
}

class _Anchor {
  const _Anchor(this.hour, this.hueDeg, this.chroma, this.glow);
  final double hour; // heure décimale, domaine [6, 30) — la nuit boucle
  final double hueDeg;
  final double chroma;
  final double glow;
}

/// Les ancres de la journée. Chroma minimale à 15 h : le pic d'attention
/// diurne demande la neutralité ; la couleur revient avec le soir.
const List<_Anchor> _anchors = <_Anchor>[
  _Anchor(6.0, 232, 0.060, 0.10), //  aube : bleu d'acier
  _Anchor(10.0, 243, 0.050, 0.07), // matin : bleu clair, sobre
  _Anchor(15.0, 250, 0.040, 0.06), // après-midi : le plus neutre
  _Anchor(19.0, 75, 0.075, 0.14), //  soir : doré
  _Anchor(22.5, 55, 0.070, 0.18), //  nuit : ambre profond
  _Anchor(30.0, 232, 0.060, 0.10), // = 6 h le lendemain (bouclage propre)
];

/// Lissage C¹ (dérivée continue) : aucune cassure de vitesse au passage
/// d'une ancre — la transition reste imperceptible même observée longtemps.
double _smoothstep(double x) => x * x * (3 - 2 * x);

/// État circadien pour une heure décimale locale [0, 24).
CircadianState circadianStateAt(double hourOfDay) {
  final double t = hourOfDay < 6 ? hourOfDay + 24 : hourOfDay;
  int i = 0;
  while (_anchors[i + 1].hour <= t) {
    i++;
  }
  final _Anchor a = _anchors[i], b = _anchors[i + 1];
  final double k = _smoothstep((t - a.hour) / (b.hour - a.hour));
  // teinte/chroma → cartésien, lerp, retour polaire (pas de balayage vert).
  double rad(double d) => d * math.pi / 180;
  final double ax = a.chroma * math.cos(rad(a.hueDeg));
  final double ay = a.chroma * math.sin(rad(a.hueDeg));
  final double bx = b.chroma * math.cos(rad(b.hueDeg));
  final double by = b.chroma * math.sin(rad(b.hueDeg));
  final double x = ax + (bx - ax) * k;
  final double y = ay + (by - ay) * k;
  return CircadianState(
    hueDeg: (math.atan2(y, x) * 180 / math.pi + 360) % 360,
    chroma: math.sqrt(x * x + y * y),
    glow: a.glow + (b.glow - a.glow) * k,
  );
}

/// Tempère une teinte de CONTENU par l'heure : mix cartésien 75 % contenu /
/// 25 % circadien. Le contenu commande, l'heure infléchit — jamais l'inverse.
Oklch temperByCircadian(Oklch content, CircadianState circadian) {
  final Oklab c = content.toOklab();
  final Oklab t = Oklch(content.l, circadian.chroma, circadian.hueDeg)
      .toOklab();
  return Oklab.lerp(c, t, 0.25).toOklch();
}
