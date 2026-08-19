// =========================================================
//  vod_pause_release_policy.dart — « Pause longue = connexion rendue »
// =========================================================
//  DEMANDE EXPLOITANT (19/08, ligne Xtream à 1 connexion) : un FILM est
//  seekable — quand le client le met en pause et part faire autre chose,
//  rien ne justifie de garder la connexion du panel ouverte pendant toute
//  la pause. Au bout de [threshold] de pause continue, le lecteur DOIT
//  arrêter le flux (stop, socket fermée) en mémorisant la position ; à la
//  reprise, il ré-ouvre et seek — invisible pour le client, ligne libérée
//  pour le fournisseur.
//
//  JAMAIS pour le direct : rien à reprendre (et la pause d'un direct est
//  déjà traitée à part par le lecteur). Jamais pour un fichier local : il
//  ne consomme aucune connexion.
//
//  Cette classe ne décide QUE du « quand » (machine à états pure, pilotée
//  par le tick périodique du lecteur) — le « comment » (stop, mémoriser,
//  ré-ouvrir, seek) reste dans l'écran. C'est ce qui la rend testable sans
//  lecteur natif.
// =========================================================

/// Décide du moment où une pause VOD a assez duré pour rendre la connexion.
class VodPauseReleasePolicy {
  VodPauseReleasePolicy({this.threshold = defaultThreshold});

  /// ~20 s : assez long pour ignorer les pauses « je lis le résumé »,
  /// assez court pour qu'un « je vais ouvrir la porte » libère déjà la
  /// ligne (un autre écran du foyer peut regarder pendant ce temps).
  static const Duration defaultThreshold = Duration(seconds: 20);

  final Duration threshold;

  DateTime? _pausedSince;
  bool _released = false;

  /// `true` tant que la connexion a été rendue et que la lecture n'a pas
  /// repris : l'écran doit RÉ-OUVRIR (setUrl + seek), pas juste play().
  bool get released => _released;

  /// À appeler à chaque tick du lecteur.
  ///
  /// [pausedOnNetwork] : la lecture est un flux RÉSEAU volontairement en
  /// pause (pas un fichier local, pas un buffering, pas une erreur).
  /// Renvoie `true` UNE seule fois par pause : l'instant où il faut rendre
  /// la connexion (stop + mémoriser la position).
  bool onTick({
    required DateTime now,
    required bool isVod,
    required bool pausedOnNetwork,
  }) {
    if (!isVod || !pausedOnNetwork) {
      // Lecture en cours (ou contenu non concerné) : tout se ré-arme.
      _pausedSince = null;
      _released = false;
      return false;
    }
    if (_released) return false; // déjà rendue, on attend la reprise
    _pausedSince ??= now;
    if (now.difference(_pausedSince!) < threshold) return false;
    _released = true;
    return true;
  }

  /// Changement de contenu (zap, épisode suivant) : état neuf.
  void reset() {
    _pausedSince = null;
    _released = false;
  }
}
