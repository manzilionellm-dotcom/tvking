import 'dart:async';

/// Un seul fichier en cours, même si deux versions sont demandées ensemble.
/// Les appels du même manifeste rejoignent le même travail ; une erreur ne
/// bloque pas la version suivante et une fin ancienne ne vide pas sa tâche.
class UpdateDownloadQueue<T> {
  Future<void> _tail = Future<void>.value();
  final Map<String, Future<T>> _pending = <String, Future<T>>{};

  Future<T> run(String key, Future<T> Function() download) {
    final Future<T>? pending = _pending[key];
    if (pending != null) return pending;
    final Future<T> work = _tail.then((_) => download());
    _pending[key] = work;
    _tail = work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    unawaited(_tail.then((_) {
      if (identical(_pending[key], work)) _pending.remove(key);
    }));
    return work;
  }
}
