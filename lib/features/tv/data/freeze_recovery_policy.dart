// =========================================================
//  freeze_recovery_policy.dart — Machine à états anti-gel du lecteur TV
// =========================================================
//  Logique PURE (zéro Flutter, zéro Timer) extraite de tv_player_screen :
//  le watchdog du lecteur lui transmet des ÉVÉNEMENTS datés (ouverture,
//  progression, tick, erreur) et elle répond l'ACTION à faire. Ce découpage
//  la rend testable à la milliseconde près — le bug du « spinner infini »
//  (verrou _recovering jamais relâché, borne P1-6 inatteignable, corrigé le
//  2026-07-06) aurait été attrapé par un simple test de cette classe.
//
//  Contrat (identique au comportement du lecteur après correctif) :
//   • openChannel()  : nouvelle chaîne / « Réessayer » manuel → budget neuf.
//   • onProgress()   : la position avance → tout va bien, budget ré-armé.
//   • onTick(now)    : tick périodique du watchdog. Si AUCUNE progression
//     depuis [frozen], la tentative précédente (s'il y en avait une) est
//     considérée ÉCHOUÉE : on relance (reopen) jusqu'à [maxAttempts], puis
//     on passe en échec définitif (fatal) → écran d'erreur clair.
//   • onPlayerError(now) : erreur/fin remontée par le natif. Pendant une
//     tentative en cours on n'empile pas de relance (le tick s'en charge) ;
//     sinon on relance immédiatement (mêmes bornes).
// =========================================================

/// Action que le lecteur doit exécuter après un événement.
enum FreezeAction {
  /// Rien à faire (lecture saine, ou tentative déjà en cours).
  none,

  /// Ré-ouvrir l'URL courante (reconnexion automatique).
  reopen,

  /// Budget épuisé : afficher l'écran d'erreur (« Réessayer » manuel).
  fatal,
}

/// Machine à états de la reconnexion anti-gel. Une instance par écran
/// lecteur ; TOUTES les décisions passent par elle (aucun état dupliqué).
class FreezeRecoveryPolicy {
  FreezeRecoveryPolicy({
    this.frozen = const Duration(seconds: 15),
    this.maxAttempts = 5,
    required DateTime now,
  }) : _lastProgress = now;

  /// Durée sans progression au-delà de laquelle le flux est considéré gelé.
  final Duration frozen;

  /// Nombre de reconnexions automatiques avant l'échec définitif.
  final int maxAttempts;

  DateTime _lastProgress;
  bool _recovering = false;
  int _attempts = 0;
  bool _fatal = false;

  /// Tentatives consommées (diagnostic / tests).
  int get attempts => _attempts;

  /// True quand le budget est épuisé (l'écran d'erreur doit être affiché).
  bool get isFatal => _fatal;

  /// Nouvelle chaîne ou « Réessayer » manuel : budget entièrement neuf.
  void openChannel(DateTime now) {
    _lastProgress = now;
    _recovering = false;
    _attempts = 0;
    _fatal = false;
  }

  /// La position de lecture avance : flux sain → on ré-arme tout.
  void onProgress(DateTime now) {
    _lastProgress = now;
    _recovering = false;
    _attempts = 0;
    _fatal = false;
  }

  /// Tick périodique du watchdog.
  FreezeAction onTick(DateTime now) {
    if (_fatal) return FreezeAction.none;
    if (now.difference(_lastProgress) <= frozen) return FreezeAction.none;
    // Gelé un plein cycle [frozen] après la dernière tentative : elle a
    // échoué → on libère le verrou pour pouvoir en lancer une autre.
    // (C'était LE bug du spinner infini : sans cette libération, plus
    // aucune reconnexion ne partait et [maxAttempts] était inatteignable.)
    _recovering = false;
    return _attempt(now);
  }

  /// Erreur ou fin de flux remontée par le lecteur natif.
  FreezeAction onPlayerError(DateTime now) {
    if (_fatal || _recovering) return FreezeAction.none;
    return _attempt(now);
  }

  FreezeAction _attempt(DateTime now) {
    if (_attempts >= maxAttempts) {
      _fatal = true;
      return FreezeAction.fatal;
    }
    _attempts++;
    _recovering = true;
    _lastProgress = now; // la tentative a droit à un plein cycle [frozen]
    return FreezeAction.reopen;
  }
}
