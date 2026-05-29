// =========================================================
//  app_pin_settings.dart — Code à 4 chiffres in-app
// =========================================================
//  Pourquoi un PIN in-app en plus de la biometrie ?
//
//  Le retour de l'utilisateur montre que `local_auth` peut
//  laisser l'app inaccessible quand :
//    - le capteur biometrique est dans l'ecran et ne registre pas
//      le doigt correctement,
//    - aucun verrouillage d'ecran systeme (PIN/schema) n'est
//      configure, donc Android n'offre pas de fallback,
//    - le dialog systeme ne s'affiche pas pour une raison X.
//
//  Solution : un PIN à 4 chiffres GERE PAR L'APP elle-meme,
//  totalement independant de l'OS. Code par defaut = "0000".
//  L'utilisateur peut le changer dans Reglages > Securite. Il
//  est stocke dans SharedPreferences (cle
//  `security.app_pin_value`).
//
//  Note securite : on ne hashe PAS ce PIN. Le modele de menace
//  pour un PIN local de 4 chiffres :
//    - Attaquant avec acces UI → doit deviner (10 000 combinaisons
//      max, mais le rate-limit cote app est facile a ajouter).
//    - Attaquant avec acces fichier (root) → de toute facon l'app
//      est compromise, hash ou pas.
//  Le hash n'apporterait rien et compliquerait le code.
// =========================================================

import 'package:shared_preferences/shared_preferences.dart';

class AppPinSettings {
  AppPinSettings._();
  static final AppPinSettings instance = AppPinSettings._();

  static const String _kPinValue = 'security.app_pin_value';

  /// PIN par defaut sur une install fraiche ou apres reset.
  /// Documente explicitement pour que l'utilisateur sache quoi
  /// taper a la premiere ouverture.
  static const String defaultPin = '0000';

  /// `true` tant que l'utilisateur n'a pas defini son propre PIN.
  /// Utile pour afficher un warning "tu utilises encore le code
  /// par defaut, change-le" dans les reglages.
  Future<bool> isUsingDefault() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return !prefs.containsKey(_kPinValue);
  }

  /// Verifie que [pin] correspond au PIN actuel.
  /// Si aucun PIN n'a jamais ete defini, accepte [defaultPin].
  Future<bool> verify(String pin) async {
    if (pin.isEmpty) return false;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? stored = prefs.getString(_kPinValue);
    final String expected = stored ?? defaultPin;
    return pin == expected;
  }

  /// Change le PIN. [newPin] doit faire entre 4 et 8 chiffres.
  /// Throw [ArgumentError] sinon — c'est l'UI qui doit valider
  /// avant d'appeler cette methode.
  Future<void> setPin(String newPin) async {
    if (newPin.length < 4 || newPin.length > 8) {
      throw ArgumentError('Le PIN doit faire entre 4 et 8 chiffres.');
    }
    if (!RegExp(r'^\d+$').hasMatch(newPin)) {
      throw ArgumentError('Le PIN ne peut contenir que des chiffres.');
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPinValue, newPin);
  }

  /// Remet le PIN au defaut (0000). Utilise par "reinitialiser"
  /// dans les reglages (pour un user qui aurait oublie son code
  /// custom).
  Future<void> resetToDefault() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPinValue);
  }
}
