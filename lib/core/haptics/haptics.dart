// =========================================================
//  haptics.dart — Retour tactile centralisé
// =========================================================
//  Un seul point d'entrée pour toute l'app → cohérence du ressenti et
//  possibilité de tout couper d'un flag (accessibilité / futur réglage).
//  Enrobe `HapticFeedback` du SDK Flutter : AUCUNE dépendance ajoutée,
//  et no-op silencieux sur les appareils sans vibreur (Android TV / Fire
//  TV) — donc sans risque quel que soit le support.
//
//  Le « premium » d'une app se joue beaucoup dans ces micro-sensations :
//  un léger clic à chaque tap ancre l'habitude (boucle Hook — sensation).
// =========================================================

import 'package:flutter/services.dart';

class Haptics {
  Haptics._();

  /// Interrupteur global (pourra être piloté par un réglage plus tard).
  static bool enabled = true;

  /// Sélection : le plus léger. Pour chaque tap d'élément (défaut).
  static void selection() {
    if (enabled) HapticFeedback.selectionClick();
  }

  /// Impact léger : favori, toggle, ajout à une liste.
  static void light() {
    if (enabled) HapticFeedback.lightImpact();
  }

  /// Impact moyen : action confirmée (envoi, CTA important).
  static void medium() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  /// Succès : palier atteint, célébration.
  static void success() {
    if (enabled) HapticFeedback.mediumImpact();
  }
}
