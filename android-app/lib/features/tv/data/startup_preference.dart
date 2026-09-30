// =========================================================
//  startup_preference.dart — « Au démarrage » de la box
// =========================================================
//  Deux choix, et rien d'autre :
//    • Accueil (DÉFAUT) — on arrive sur les tuiles et les rangées.
//    • Dernière chaîne — on reprend tout de suite ce qui passait.
//
//  Le défaut est l'accueil. On ne force JAMAIS la lecture : la personne
//  doit activer l'option dans Réglages, et Retour la ramène à l'accueil.
//  Elle peut revenir en arrière à tout moment, au même endroit.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Décision PURE (testable sans disque).
///
/// On n'ouvre la dernière chaîne que si TOUT est vrai :
///   • la personne a demandé cette option ;
///   • on ne l'a pas déjà fait pendant cette visite de l'accueil
///     (sinon Retour relancerait la chaîne en boucle — un piège) ;
///   • on a vraiment une chaîne à reprendre ;
///   • on n'est pas en mode sans échec (la box a déjà planté en boucle :
///     on ne relance pas un lecteur tout seul).
bool shouldResumeLastChannel({
  required bool enabled,
  required bool alreadyResumedThisVisit,
  required bool hasChannel,
  required bool safeMode,
}) =>
    enabled && !alreadyResumedThisVisit && hasChannel && !safeMode;

class StartupPreference extends ChangeNotifier {
  StartupPreference._();
  static final StartupPreference instance = StartupPreference._();

  static const String _kOpenLast = 'tv.startup.open_last_channel';

  bool _openLast = false;
  bool _loaded = false;

  /// Faux tant que la personne n'a pas choisi autrement.
  bool get openLastChannel => _openLast;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _openLast = prefs.getBool(_kOpenLast) ?? false;
    } catch (e) {
      if (kDebugMode) debugPrint('[Démarrage] lecture: $e');
      _openLast = false;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setOpenLastChannel(bool value) async {
    _openLast = value;
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kOpenLast, value);
    } catch (e) {
      if (kDebugMode) debugPrint('[Démarrage] écriture: $e');
    }
  }
}
