// =========================================================
//  consent_state.dart — Acceptation des conditions (CGU)
// =========================================================
//  Porte bloquante du premier lancement : l'app ne s'utilise
//  qu'après acceptation des conditions (le lecteur ne fournit
//  aucun contenu ; les liens appartiennent à l'utilisateur).
//
//  On stocke la VERSION des conditions acceptée (int) et non un
//  simple booléen : bumper `termsVersion` force chaque client à
//  ré-accepter les nouvelles conditions au prochain lancement,
//  sans toucher aux autres préférences.
// =========================================================

import 'package:shared_preferences/shared_preferences.dart';

class ConsentState {
  ConsentState._();
  static final ConsentState instance = ConsentState._();

  static const String _kKey = 'legal.consent.v1';

  /// Version courante des conditions. À incrémenter si le texte
  /// change de façon substantielle (chacun devra ré-accepter).
  static const int termsVersion = 1;

  /// `true` si l'utilisateur a accepté une version >= [termsVersion].
  /// Une valeur corrompue/absente vaut « pas accepté » — la porte
  /// se réaffiche, jamais d'exception.
  Future<bool> hasAccepted() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_kKey) ?? 0) >= termsVersion;
  }

  Future<void> markAccepted() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kKey, termsVersion);
  }

  Future<void> reset() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }
}
