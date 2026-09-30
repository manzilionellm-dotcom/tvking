// =========================================================
//  tv_zap.dart — Prochain index de chaîne (Haut / Bas)
// =========================================================
//  Pur calcul, sans lecteur : testable, et le même pour un appui
//  simple ou une touche maintenue. Le modulo de Dart, quand le
//  diviseur est positif, reste dans [0, length) — y compris si
//  on part de 0 et qu'on recule (0 + -1 → dernière chaîne).
// =========================================================

/// Index après un déplacement de [delta] chaînes (−1 = précédente).
/// Liste vide ou d'une seule chaîne : on ne bouge pas.
int tvNextZapIndex(int index, int delta, int length) {
  if (length <= 1) return index;
  return (index + delta) % length;
}
