// =========================================================
//  onboarding_state.dart — Flag "premier lancement"
// =========================================================
//  Stocke un booléen dans SharedPreferences pour savoir si
//  l'utilisateur a déjà vu l'onboarding. Évite de le réafficher
//  à chaque ouverture de l'app.
// =========================================================

import 'package:shared_preferences/shared_preferences.dart';

class OnboardingState {
  OnboardingState._();
  static final OnboardingState instance = OnboardingState._();

  static const String _kKey = 'onboarding.completed.v1';

  Future<bool> hasCompleted() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kKey) ?? false;
  }

  Future<void> markCompleted() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKey, true);
  }

  Future<void> reset() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }
}
