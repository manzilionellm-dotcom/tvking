// =========================================================
//  playback_lease.dart — un seul lecteur a le droit de parler
// =========================================================
//  La pub de démarrage et le film peuvent chacun avoir un lecteur
//  libmpv. Android ne coupe pas le premier tout seul. Ce bail est
//  la règle, testée sans flux : celui qui « prend » le son fait
//  taire les autres, et un jeton de session périmé ne compte plus.
// =========================================================

/// Compteur de session. Après [open], les jetons plus petits sont morts.
class PlaybackSession {
  int _generation = 0;

  int get generation => _generation;

  int open() {
    _generation += 1;
    return _generation;
  }

  bool isCurrent(int token) => token > 0 && token == _generation;
}

/// Registre : un identifiant = un lecteur, un seul propriétaire du son.
class ExclusiveAudio {
  ExclusiveAudio();

  /// Registre de l'application. Les tests construisent le leur.
  static final ExclusiveAudio shared = ExclusiveAudio();

  final Map<int, void Function()> _silence = <int, void Function()>{};
  int _next = 0;

  int? owner;

  int get registeredCount => _silence.length;

  int register(void Function() silence) {
    _next += 1;
    _silence[_next] = silence;
    return _next;
  }

  void unregister(int id) {
    _silence.remove(id);
    if (owner == id) owner = null;
  }

  /// [id] devient le seul audible. Les autres sont coupés tout de suite.
  void claim(int id) {
    owner = id;
    final List<int> ids = _silence.keys.toList(growable: false);
    for (final int other in ids) {
      if (other != id) {
        _silence[other]?.call();
      }
    }
  }

  void debugReset() {
    _silence.clear();
    owner = null;
    _next = 0;
  }
}
