/// Sérialise les ouvertures/fermetures libmpv. Une ouverture déjà commencée
/// finit avant Stop ; celles qui attendent sont invalidées par un zap/Stop.
/// Les préparatifs asynchrones ne comptent pas encore comme une ouverture :
/// on vérifie à nouveau le ticket avant de donner une URL au lecteur.
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

  Future<void> replace(
    Future<void> Function() action, {
    Future<void> Function()? prepare,
  }) {
    final int ticket = ++_revision;
    return _enqueue(() async {
      if (_closed || ticket != _revision) return;
      if (prepare != null) {
        try {
          await prepare();
        } catch (_) {
          // Un ancien zap ne doit pas afficher une erreur sur la nouvelle
          // chaîne, ni sur un lecteur déjà fermé ou passé en Cast.
          if (_closed || ticket != _revision) return;
          rethrow;
        }
      }
      if (!_closed && ticket == _revision) await action();
    });
  }

  /// Un réglage s'applique entre deux ouvertures sans annuler la suivante.
  /// C'est aussi la barrière d'initialisation libmpv avant la première URL.
  Future<void> configure(Future<void> Function() action) {
    return _enqueue(() async {
      if (!_closed) await action();
    });
  }

  Future<void> stop(Future<void> Function() action) {
    ++_revision;
    return _enqueue(() async {
      if (!_closed) await action();
    });
  }

  Future<void> close(Future<void> Function() action) {
    _closed = true;
    ++_revision;
    return _enqueue(action);
  }
}
