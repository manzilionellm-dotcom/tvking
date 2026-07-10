// =========================================================
//  autoplay_policy.dart — Machine à états « À suivre » (autoplay épisode)
// =========================================================
//  Logique PURE (zéro Flutter, zéro Timer) : le lecteur TV lui transmet des
//  ÉVÉNEMENTS (fin de contenu, enchaînement auto, interaction télécommande,
//  annulation) et elle répond la DÉCISION à prendre. Même découpage que
//  FreezeRecoveryPolicy : toute la logique métier est testable sans widget
//  (cf. test/features/tv/data/autoplay_policy_test.dart).
//
//  Règles métier (pilier du binge, façon Netflix) :
//   • Ne se déclenche QUE pour un ÉPISODE de série (id `ep-…`) suivi d'un
//     autre épisode dans la liste du lecteur. Un FILM (id `vod-…`) ne
//     s'enchaîne JAMAIS sur un autre film ; le LIVE n'a pas de fin.
//   • Après [maxAutoChains] enchaînements automatiques SANS interaction
//     télécommande, le compte à rebours ne lance plus tout seul : la carte
//     s'affiche mais ATTEND un OK explicite (garde-fou anti-binge-infini,
//     même esprit que le « Tu regardes encore ? » après 4 h d'inactivité —
//     personne ne devrait « regarder » 4 épisodes en dormant).
//   • Toute interaction télécommande remet le compteur à zéro : quelqu'un
//     tient la télécommande, l'autoplay reste fluide.
//   • Une annulation (« Annuler » ou Retour) est mémorisée pour CE contenu :
//     le natif ré-émet `isEnded` à chaque notification tant qu'on reste sur
//     l'écran de fin — sans cette mémoire, la carte réapparaîtrait
//     immédiatement après chaque annulation.
// =========================================================

/// Décision à la fin d'un contenu VOD.
enum UpNextDecision {
  /// Rien à proposer (film, dernier épisode, live, ou déjà annulé ici).
  none,

  /// Afficher la carte « À suivre » AVEC compte à rebours : à zéro, on
  /// enchaîne automatiquement sur l'épisode suivant.
  autoCountdown,

  /// Garde-fou atteint : afficher la carte, mais SANS lancer tout seul —
  /// on attend un OK explicite de l'utilisateur.
  waitForConfirm,
}

/// Machine à états de l'autoplay « épisode suivant ». Une instance par écran
/// lecteur ; TOUTES les décisions passent par elle (aucun état dupliqué).
class AutoplayPolicy {
  AutoplayPolicy({
    this.maxAutoChains = 3,
    this.countdownSeconds = 10,
  });

  /// Nombre d'enchaînements AUTOMATIQUES consécutifs autorisés sans la
  /// moindre interaction télécommande, avant de demander un OK explicite.
  final int maxAutoChains;

  /// Durée du compte à rebours affiché sur la carte (secondes).
  final int countdownSeconds;

  int _autoChains = 0;
  String? _dismissedForId;

  /// Enchaînements automatiques consécutifs déjà consommés (diagnostic/tests).
  int get autoChains => _autoChains;

  /// Un id de la liste du lecteur est un ÉPISODE de série ssi il est préfixé
  /// `ep-` (convention posée par la fiche série / PlaybackPositionRepository :
  /// `vod-<streamId>` = film, `ep-<id>` = épisode).
  static bool isEpisodeId(String id) => id.startsWith('ep-');

  /// Y a-t-il quelque chose à proposer à la fin de [currentId] ?
  /// PUR et sans effet de bord : épisode courant + épisode suivant existant.
  /// [nextId] = id de l'élément suivant dans la liste du lecteur (null = fin
  /// de liste, donc fin de saison → écran de fin classique).
  bool canPropose({
    required bool isLive,
    required String currentId,
    String? nextId,
  }) =>
      !isLive &&
      isEpisodeId(currentId) &&
      nextId != null &&
      isEpisodeId(nextId);

  /// Fin réelle d'un contenu : que faire ? (cf. [UpNextDecision])
  UpNextDecision onEnded({
    required bool isLive,
    required String currentId,
    String? nextId,
  }) {
    if (!canPropose(isLive: isLive, currentId: currentId, nextId: nextId)) {
      return UpNextDecision.none;
    }
    // Déjà annulé pour CE contenu → on respecte le choix (écran de fin
    // stable, la carte ne « re-pop » pas à la notification suivante).
    if (_dismissedForId == currentId) return UpNextDecision.none;
    return _autoChains >= maxAutoChains
        ? UpNextDecision.waitForConfirm
        : UpNextDecision.autoCountdown;
  }

  /// Le compte à rebours est arrivé à zéro et le lecteur enchaîne tout seul.
  void onAutoAdvance() => _autoChains++;

  /// N'importe quelle touche télécommande : quelqu'un est devant l'écran →
  /// le garde-fou repart de zéro.
  void onUserInteraction() => _autoChains = 0;

  /// « Annuler » (ou Retour) sur la carte : on mémorise le refus pour CE
  /// contenu — et c'est évidemment une interaction (compteur remis à zéro).
  void onCancel(String currentId) {
    _dismissedForId = currentId;
    _autoChains = 0;
  }
}
