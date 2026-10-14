import 'dart:async';

/// Sérialise les commandes natives. Une ouverture remplacée pendant un
/// await ne doit plus lancer une ancienne chaîne ni rallumer un lecteur
/// qu'un autre écran vient de faire taire.
class PlaybackQueue {
  PlaybackQueue({required this.onError});
  final void Function(Object error, StackTrace stack) onError;
  Future<void> _tail = Future<void>.value();
  int _generation = 0;
  bool _closed = false;

  int replace() => ++_generation;
  bool isCurrent(int generation) => !_closed && generation == _generation;

  void enqueue(Future<void> Function() action, {int? generation}) {
    if (_closed) return;
    _tail = _tail.then((_) async {
      if (_closed || (generation != null && !isCurrent(generation))) return;
      try {
        await action();
      } catch (error, stack) {
        if (!_closed && (generation == null || isCurrent(generation))) {
          onError(error, stack);
        }
      }
    });
  }

  /// Termine l'appel natif en vol puis détruit le moteur UNE fois.
  Future<void> close(Future<void> Function() release) async {
    if (_closed) return;
    _closed = true;
    _generation++;
    await _tail;
    await release();
  }
}
