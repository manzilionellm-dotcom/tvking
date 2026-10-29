/// Sérialise les ouvertures/fermetures libmpv. Une ouverture déjà commencée
/// finit avant Stop ; celles qui attendent sont invalidées par un zap/Stop.
class DesktopPlaybackQueue {
  Future<void> _tail = Future<void>.value();
  int _revision = 0;
  bool _closed = false;

  Future<void> _enqueue(Future<void> Function() action) {
    final Future<void> operation = _tail.then((_) => action());
    // Une erreur reste visible au demandeur, sans empoisonner la file suivante.
    _tail = operation.catchError((Object _, StackTrace __) {});
    return operation;
  }
  Future<void> replace(Future<void> Function() action) {
    final int ticket = ++_revision;
    return _enqueue(() async { if (!_closed && ticket == _revision) await action(); });
  }
  Future<void> stop(Future<void> Function() action) {
    ++_revision;
    return _enqueue(() async { if (!_closed) await action(); });
  }
  Future<void> close(Future<void> Function() action) {
    _closed = true; ++_revision;
    return _enqueue(action);
  }
}
