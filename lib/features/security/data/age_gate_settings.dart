// =========================================================
//  age_gate_settings.dart — Confirmation 18+ (Red Room only)
// =========================================================
//  Le flavor Red Room exige une confirmation d'âge AU PREMIER
//  lancement. La déclaration sur l'honneur est le strict
//  minimum légal pour la plupart des juridictions ; certaines
//  (UK Online Safety Act, France ARCOM) exigent davantage —
//  c'est documenté côté STATUS.md, pas dans le code.
//
//  Une fois acceptée, la confirmation est persistée dans
//  SharedPreferences sous `security.age_gate_confirmed_at`.
//  On stocke l'epoch (et pas juste un bool) pour pouvoir
//  réinitialiser périodiquement si la loi l'exige plus tard.
// =========================================================

import 'package:shared_preferences/shared_preferences.dart';

class AgeGateSettings {
  AgeGateSettings._();
  static final AgeGateSettings instance = AgeGateSettings._();

  static const String _kConfirmedAt = 'security.age_gate_confirmed_at';

  /// `true` si l'utilisateur a déjà confirmé avoir 18 ans ou plus.
  Future<bool> isConfirmed() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_kConfirmedAt);
  }

  /// Mémorise la confirmation. Stocke l'epoch ms pour pouvoir, plus
  /// tard, forcer une re-confirmation tous les N mois si la loi
  /// devient plus stricte.
  Future<void> markConfirmed() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kConfirmedAt, DateTime.now().millisecondsSinceEpoch);
  }

  /// Annule la confirmation. Utilisé si l'utilisateur clique "Non,
  /// je n'ai pas 18 ans" sur le modal (et qu'on doit le sortir de
  /// l'app proprement).
  Future<void> clear() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kConfirmedAt);
  }
}
