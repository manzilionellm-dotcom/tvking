// =========================================================
//  playback_lease.dart — un seul lecteur a le droit de parler
// =========================================================
//  Deux ExoPlayer (aperçu + plein écran, ou un zap trop rapide qui
//  n'a pas encore libéré l'ancien) jouent chacun dans leur AudioTrack.
//  Android ne les coupe pas tout seul si le focus audio est désactivé.
//  Ce bail est la règle, testée sans flux : celui qui « prend » le son
//  fait taire tous les autres, et un jeton de génération périmé ne
//  compte plus.
// =========================================================

/// Compteur de session. Après [open], les jetons plus petits sont morts.
class PlaybackSession {
  int _generation = 0;

  /// Dernier jeton délivré. 0 = aucune session.
  int get generation => _generation;

  /// Nouvelle session. L'ancienne est invalide tout de suite.
  int open() {
    _generation += 1;
    return _generation;
  }

  /// Vrai seulement pour le dernier [open].
  bool isCurrent(int token) => token > 0 && token == _generation;
}

/// Registre : un identifiant = un lecteur, un seul propriétaire du son.
class ExclusiveAudio {
  final Map<int, void Function()> _silence = <int, void Function()>{};
  int _next = 0;

  /// Lecteur qui a le droit de sortir du son. null = personne.
  int? owner;

  int get registeredCount => _silence.length;

  /// Inscrit [silence]. L'appel ne joue rien : il coupe CE lecteur
  /// quand un AUTRE prend la place. On ne rappelle pas [claim] dedans,
  /// sinon les lecteurs se couperaient en boucle.
  int register(void Function() silence) {
    _next += 1;
    _silence[_next] = silence;
    return _next;
  }

  void unregister(int id) {
    _silence.remove(id);
    if (owner == id) owner = null;
  }

  /// [id] devient le seul audible. Tous les autres inscrits sont coupés
  /// tout de suite, dans l'ordre d'inscription.
  void claim(int id) {
    owner = id;
    final List<int> ids = _silence.keys.toList(growable: false);
    for (final int other in ids) {
      if (other != id) {
        _silence[other]?.call();
      }
    }
  }

  /// Remet le registre à zéro. Réservé aux tests.
  void debugReset() {
    _silence.clear();
    owner = null;
    _next = 0;
  }
}

/// Verrou « un plein écran est ouvert ». L'aperçu ne doit pas créer
/// un second lecteur pendant ce temps (il repart quand le compteur
/// retombe à zéro).
class ForegroundPlayback {
  static int _locks = 0;

  static bool get locked => _locks > 0;

  static void lock() {
    _locks += 1;
  }

  static void unlock() {
    if (_locks > 0) _locks -= 1;
  }

  static void debugReset() {
    _locks = 0;
  }
}
