// =========================================================
//  lock_settings.dart — Préférences du verrouillage à l'ouverture
// =========================================================
//  Le user peut activer un lock biométrique à l'ouverture de l'app.
//  Le réglage est stocké dans SharedPreferences (clé
//  `security.lock_on_open`). Default = OFF (pas de friction par
//  défaut, opt-in seulement).
//
//  Le lock se déclenche UNIQUEMENT au démarrage à froid de l'app.
//  Pas de re-lock quand on revient du background (choix UX du
//  user, cf. question /AskUserQuestion).
// =========================================================

import 'package:shared_preferences/shared_preferences.dart';

class LockSettings {
  LockSettings._();
  static final LockSettings instance = LockSettings._();

  static const String _kLockOnOpen = 'security.lock_on_open';

  /// Le verrouillage biométrique à l'ouverture est-il activé ?
  Future<bool> isLockEnabled() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kLockOnOpen) ?? false;
  }

  Future<void> setLockEnabled(bool enabled) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLockOnOpen, enabled);
  }
}
