// =========================================================
//  boot_guard.dart — Anti « l'app redémarre en boucle »
// =========================================================
//  PROBLÈME : sur certaines box TV bas de gamme, l'app se ferme et se relance
//  toute seule, en BOUCLE. La cause est presque toujours un CRASH NATIF
//  (mémoire insuffisante en ré-important une grosse source, lecteur
//  MediaCodec…). Ces crashes natifs NE PEUVENT PAS être rattrapés en Dart :
//  Android tue le process et le relance → si le démarrage refait AUSSITÔT
//  l'action qui a planté (re-import), on repart pour un tour → boucle infinie.
//
//  ─────────────────────────────────────────────────────────────────────────
//  ANCIENNE DÉTECTION (DÉFAILLANTE, corrigée ici) :
//  on remettait le compteur à 0 après un TIMER FIXE de 8 s
//  (`scheduleStableReset`). Or le crash d'import d'une grosse playlist survient
//  APRÈS (souvent > 15 s, parfois 60 s sur box lente). Le compteur était donc
//  remis à 0 AVANT le crash → le seuil n'était JAMAIS atteint → le mode sans
//  échec ne s'activait JAMAIS. C'est ça qui laissait la boucle « ouvre/ferme ».
//
//  NOUVELLE DÉTECTION (jalon + phase) :
//   • Chaque démarrage INCRÉMENTE un compteur PERSISTÉ (sur disque) AVANT toute
//     opération risquée.
//   • Le SEUL reset autorisé est `markBootSucceeded()`, appelé quand la home
//     est interactive ET l'import terminé (pas un timer).
//   • Donc N crashes consécutifs SANS boot réussi entre eux = boucle, quel que
//     soit le timing (8 s, 15 s ou 60 s).
//   • On suit aussi la PHASE atteinte (`BootPhase`) → au boot suivant en mode
//     sans échec, on sait OÙ ça a planté et on propose une récupération CIBLÉE.
//
//  COMPAT : `safeMode` et `scheduleStableReset()` sont CONSERVÉS (dépréciés)
//  pour que les points d'entrée mobile/Privé (`main.dart`) compilent et gardent
//  leur comportement actuel sans modification. La TV, elle, utilise la nouvelle
//  API (`isInSafeMode`, `markPhase`, `markBootSucceeded`).
// =========================================================
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Étapes franchies pendant un démarrage. Persistée à chaque jalon : au boot
/// suivant, `BootGuard.lastFailedPhase` renvoie la dernière phase atteinte au
/// démarrage PRÉCÉDENT → on cible la récupération (rendu vs mémoire/import).
enum BootPhase {
  /// Aucun jalon encore franchi (valeur par défaut / base neuve).
  none,

  /// Moteur Flutter initialisé, AVANT le 1er frame et l'import.
  flutterUp,

  /// Premier frame rendu (l'UI s'est affichée au moins une fois).
  firstFrame,

  /// On COMMENCE l'import distant (étape la plus gourmande, suspect OOM n°1).
  importStart,

  /// Import distant TERMINÉ (succès ou rien à importer).
  importDone,

  /// Home interactive ET import fini → boot réussi (seul état « stable »).
  homeReady,
}

class BootGuard {
  BootGuard._();
  static final BootGuard instance = BootGuard._();

  // --- Clés de persistance (SharedPreferences) ---
  static const String _kFailCount = 'bootguard.fail_count';
  static const String _kLastPhase = 'bootguard.last_phase';
  static const String _kLastBootTs = 'bootguard.last_boot_ts';
  // Récupération choisie par l'utilisateur dans l'écran « mode sans échec ».
  static const String _kSkipAutoImport = 'bootguard.skip_auto_import';
  static const String _kCompatMode = 'bootguard.compat_mode';

  /// Au-delà de ce nombre de démarrages NON réussis d'affilée → boucle.
  static const int _kThreshold = 3;

  /// Délai de l'ancien reset-par-timer — CONSERVÉ uniquement pour le shim de
  /// compatibilité `scheduleStableReset()` (mobile/Privé). La TV ne l'utilise
  /// plus.
  static const int _kStableAfterMs = 8000;

  /// Garde anti-FAUX-POSITIF : si le démarrage précédent date de PLUS que ça,
  /// on considère un éventuel compteur résiduel comme « périmé » et on repart
  /// de zéro AVANT d'incrémenter. JUSTIFICATION : une vraie boucle de crash
  /// enchaîne les démarrages en quelques secondes à ~1–2 min (même un import
  /// lent qui meurt à 60 s reste bien en-dessous). Deux crashes espacés de
  /// plusieurs heures/jours ne sont PAS une boucle : les fusionner
  /// déclencherait le mode sans échec à tort. Ce garde NE court-circuite PAS la
  /// détection d'une vraie boucle (rapide) — il ne fait qu'oublier l'histoire
  /// ancienne.
  static const int _kStaleResetMs = 30 * 60 * 1000; // 30 min

  bool _inSafeMode = false;
  BootPhase _lastFailedPhase = BootPhase.none;

  /// `true` si on soupçonne une boucle de redémarrage (compteur ≥ seuil).
  bool get isInSafeMode => _inSafeMode;

  /// Compat ascendante (mobile/Privé) : ancien nom de [isInSafeMode].
  bool get safeMode => _inSafeMode;

  /// Dernière phase atteinte au démarrage PRÉCÉDENT (pour cibler la récup.).
  BootPhase get lastFailedPhase => _lastFailedPhase;

  /// À appeler TOUT AU DÉBUT du démarrage, AVANT les étapes risquées.
  /// INCRÉMENTE et PERSISTE le compteur (await = écrit sur disque avant
  /// l'import) puis calcule le mode sans échec. Best-effort : en cas de souci
  /// on n'active PAS le mode sans échec (on ne bride jamais un démarrage sain).
  Future<void> beginBoot() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int now = DateTime.now().millisecondsSinceEpoch;
      final int last = prefs.getInt(_kLastBootTs) ?? 0;

      // 1) On MÉMORISE la phase atteinte au boot précédent AVANT de l'écraser
      //    → c'est elle qui cible la récupération.
      _lastFailedPhase = _phaseFromInt(prefs.getInt(_kLastPhase));

      // 2) Garde anti-faux-positif : compteur périmé (boot ancien) → on oublie.
      int failCount = prefs.getInt(_kFailCount) ?? 0;
      if (last != 0 && (now - last) > _kStaleResetMs) {
        failCount = 0;
      }

      // 3) Ce démarrage compte TOUJOURS (+1), persisté AVANT tout import.
      failCount += 1;
      await prefs.setInt(_kFailCount, failCount);
      await prefs.setInt(_kLastBootTs, now);
      await prefs.setInt(_kLastPhase, BootPhase.flutterUp.index);

      _inSafeMode = failCount >= _kThreshold;
      if (_inSafeMode) {
        debugPrint('[BootGuard] BOUCLE détectée ($failCount démarrages non '
            'réussis d\'affilée, dernière phase=$_lastFailedPhase) '
            '→ MODE SANS ÉCHEC.');
      }
    } catch (e) {
      _inSafeMode = false;
      _lastFailedPhase = BootPhase.none;
      debugPrint('[BootGuard] beginBoot ignoré ($e).');
    }
  }

  /// Persiste la phase courante (jalon). Renvoie un Future pour permettre à
  /// l'appelant d'`await` quand la durabilité compte (ex. avant l'import :
  /// `importStart`). Best-effort : une erreur de persistance n'est jamais
  /// fatale (au pire la récupération ciblée retombe sur la phase par défaut).
  Future<void> markPhase(BootPhase phase) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLastPhase, phase.index);
    } catch (_) {
      // sans gravité
    }
  }

  /// SEUL point de reset autorisé : le boot a réussi (home interactive ET
  /// import terminé). Remet le compteur à 0 et marque la phase `homeReady`.
  Future<void> markBootSucceeded() async {
    _inSafeMode = false;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kFailCount, 0);
      await prefs.setInt(_kLastPhase, BootPhase.homeReady.index);
      debugPrint('[BootGuard] boot RÉUSSI → compteur remis à zéro.');
    } catch (_) {
      // sans gravité : un prochain boot ancien (stale) réinitialisera.
    }
  }

  /// Réinitialise le compteur d'échecs SANS marquer un boot réussi. Utilisé par
  /// l'écran de récupération (mode sans échec) après l'action de l'utilisateur,
  /// pour sortir de la boucle au prochain démarrage.
  Future<void> clearFailures() async {
    _inSafeMode = false;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kFailCount, 0);
    } catch (_) {}
  }

  // --- Drapeaux de récupération (posés par l'écran mode sans échec) ---

  /// Demande de SAUTER l'auto-import au prochain démarrage (one-shot). Évite de
  /// retomber direct sur l'étape qui plante tant que l'utilisateur n'a pas agi.
  Future<void> setSkipAutoImportOnce(bool value) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSkipAutoImport, value);
    } catch (_) {}
  }

  /// Lit ET efface le drapeau « sauter l'auto-import » (consommation one-shot).
  Future<bool> consumeSkipAutoImport() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool v = prefs.getBool(_kSkipAutoImport) ?? false;
      if (v) await prefs.remove(_kSkipAutoImport);
      return v;
    } catch (_) {
      return false;
    }
  }

  /// Mode compatibilité de rendu demandé (ex. Impeller OFF). Le toggle effectif
  /// du moteur se fait côté manifest/CI ; ici on PERSISTE le souhait pour que
  /// l'utilisateur ne reste pas bloqué et qu'on puisse l'exploiter au boot.
  Future<void> setCompatMode(bool value) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kCompatMode, value);
    } catch (_) {}
  }

  /// `true` si le mode compatibilité de rendu a été demandé.
  Future<bool> compatModeRequested() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kCompatMode) ?? false;
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  //  COMPAT ASCENDANTE (mobile/Privé) — NE PAS utiliser sur la TV
  // ============================================================

  /// @deprecated Conservé pour `main.dart` (mobile/Privé) afin de ne pas casser
  /// leur build ni changer leur comportement. La TV utilise `markBootSucceeded`
  /// (jalon) au lieu de ce reset par timer. Reproduit l'ancien comportement :
  /// si l'app tient [_kStableAfterMs], on considère le boot stable et on reset.
  @Deprecated('TV: utiliser markBootSucceeded(). Conservé pour mobile/Privé.')
  void scheduleStableReset() {
    Future<void>.delayed(
        const Duration(milliseconds: _kStableAfterMs), markBootSucceeded);
  }

  static BootPhase _phaseFromInt(int? i) {
    if (i == null || i < 0 || i >= BootPhase.values.length) {
      return BootPhase.none;
    }
    return BootPhase.values[i];
  }
}
