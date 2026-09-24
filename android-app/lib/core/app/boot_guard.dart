// =========================================================
//  boot_guard.dart — Anti « l'app redémarre en boucle »
// =========================================================
//  PROBLÈME visé : sur certaines box TV bas de gamme, l'app peut se
//  fermer et se relancer toute seule, en BOUCLE. La cause est presque
//  toujours un CRASH NATIF (mémoire insuffisante en ré-important une
//  grosse source poussée par le panel, lecteur MediaCodec, lib mpv…).
//  Ces crashes natifs NE PEUVENT PAS être rattrapés en Dart : quand ils
//  arrivent, Android tue le process et le relance → si le démarrage
//  refait AUSSITÔT l'action qui a planté (re-import de la source), on
//  repart pour un tour → boucle infinie.
//
//  SOLUTION (le « disjoncteur ») : à chaque démarrage on compte les
//  lancements RAPPROCHÉS. Au-delà d'un seuil, on conclut « boucle de
//  crash » et on passe en MODE SANS ÉCHEC : on démarre en SAUTANT les
//  étapes risquées (ré-import de la source distante, restauration, etc.).
//  L'app s'ouvre alors sur ce qu'elle a déjà en cache (ou l'écran
//  d'activation) → la boucle est CASSÉE et l'utilisateur reprend la main.
//
//  Quand l'app tourne stablement quelques secondes, on remet le compteur
//  à zéro → un usage normal (ouvrir/fermer) ne déclenche jamais à tort
//  le mode sans échec.
// =========================================================
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BootGuard {
  BootGuard._();
  static final BootGuard instance = BootGuard._();

  // Clés de persistance (SharedPreferences).
  static const String _kAttempts = 'bootguard.attempts';
  static const String _kLastBootMs = 'bootguard.last_boot_ms';

  /// Deux démarrages séparés de moins de [_kWindowMs] sont « rapprochés ».
  static const int _kWindowMs = 20000; // 20 s
  /// Au-delà de ce nombre de démarrages rapprochés → boucle suspectée.
  static const int _kThreshold = 3;
  /// Durée de fonctionnement au-delà de laquelle on considère l'app « stable ».
  static const int _kStableAfterMs = 8000; // 8 s

  bool _safeMode = false;

  /// `true` si on soupçonne une boucle de redémarrage → sauter le risqué.
  bool get safeMode => _safeMode;

  /// À appeler TOUT AU DÉBUT du démarrage, avant les étapes risquées.
  /// Best-effort : en cas de souci on n'active PAS le mode sans échec
  /// (on ne veut jamais brider un démarrage sain).
  Future<void> beginBoot() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int now = DateTime.now().millisecondsSinceEpoch;
      final int last = prefs.getInt(_kLastBootMs) ?? 0;
      int attempts = prefs.getInt(_kAttempts) ?? 0;

      if (now - last < _kWindowMs) {
        attempts += 1; // démarrage rapproché du précédent
      } else {
        attempts = 1; // démarrage isolé → on repart proprement
      }

      await prefs.setInt(_kAttempts, attempts);
      await prefs.setInt(_kLastBootMs, now);

      _safeMode = attempts >= _kThreshold;
      if (_safeMode) {
        debugPrint('[BootGuard] BOUCLE de redémarrage détectée '
            '($attempts lancements rapprochés) → MODE SANS ÉCHEC.');
      }
    } catch (e) {
      _safeMode = false;
      debugPrint('[BootGuard] beginBoot ignoré ($e).');
    }
  }

  /// À appeler une fois l'app lancée (après runApp) : planifie une remise à
  /// zéro du compteur si l'app tient [_kStableAfterMs] sans crasher. Ainsi un
  /// démarrage réussi « efface » l'historique de boucle.
  void scheduleStableReset() {
    Future<void>.delayed(const Duration(milliseconds: _kStableAfterMs), () async {
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_kAttempts, 0);
        debugPrint('[BootGuard] app stable → compteur de boucle remis à zéro.');
      } catch (_) {
        // Sans gravité : au pire le prochain démarrage isolé réinitialisera.
      }
    });
  }
}
