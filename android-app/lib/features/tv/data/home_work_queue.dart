import 'dart:async';

/// Regroupe le travail de l'accueil pendant les imports et la lecture vidéo.
/// Une tâche par nom, une seule exécution en vol : les notifications suivantes
/// remplacent l'attente, sans démarrer dix recherches ou lectures du guide.
/// Mettre en pause conserve la dernière demande pour le retour à l'accueil.
class HomeWorkQueue {
  HomeWorkQueue({this.onError});

  final void Function(Object error, StackTrace stack)? onError;
  final Map<String, _HomeWork> _pending = <String, _HomeWork>{};
  final Set<String> _running = <String>{};
  bool _paused = false;
  bool _disposed = false;

  bool get paused => _paused;

  set paused(bool value) {
    if (_disposed || value == _paused) return;
    _paused = value;
    for (final String key in _pending.keys.toList()) {
      final _HomeWork job = _pending[key]!;
      job.timer?.cancel();
      job.timer = null;
      if (!value) _arm(key, job);
    }
  }

  void schedule(
    String key,
    FutureOr<void> Function() action, {
    Duration delay = Duration.zero,
  }) {
    if (_disposed) return;
    _pending[key]?.timer?.cancel();
    final _HomeWork job = _HomeWork(action, delay);
    _pending[key] = job;
    _arm(key, job);
  }

  void _arm(String key, _HomeWork job) {
    if (_disposed || _paused || _running.contains(key)) return;
    job.timer = Timer(job.delay, () async {
      if (_disposed || _paused || !identical(_pending[key], job)) return;
      _pending.remove(key);
      _running.add(key);
      try {
        await job.action();
      } catch (error, stack) {
        if (!_disposed) onError?.call(error, stack);
      } finally {
        _running.remove(key);
        final _HomeWork? next = _pending[key];
        if (next != null) _arm(key, next);
      }
    });
  }

  void dispose() {
    _disposed = true;
    for (final _HomeWork job in _pending.values) {
      job.timer?.cancel();
    }
    _pending.clear();
  }
}

class _HomeWork {
  _HomeWork(this.action, this.delay);
  final FutureOr<void> Function() action;
  final Duration delay;
  Timer? timer;
}
