import 'dart:async';

/// Réserve les téléchargements au profit des lecteurs visibles. Chaque
/// route garde son propre jeton : la sortie tardive de A ne libère jamais
/// la réservation de B. Le moteur réel est injecté pour tester ces courses
/// sans base de données ni connexion à un fournisseur.
final class PlaybackDownloadPause {
  PlaybackDownloadPause({
    required Iterable<String> Function() activeIds,
    required Future<void> Function(String id) pause,
    required Future<void> Function(String id) resume,
  })  : _activeIds = activeIds,
        _pause = pause,
        _resume = resume;

  final Iterable<String> Function() _activeIds;
  final Future<void> Function(String id) _pause;
  final Future<void> Function(String id) _resume;
  final Object _legacyOwner = Object();
  final Set<Object> _owners = Set<Object>.identity();
  final Set<String> _pending = <String>{};
  Future<void> _serial = Future<void>.value();

  bool get hasOwners => _owners.isNotEmpty;
  int get pendingCount => _pending.length;
  bool holds(String id) => _pending.contains(id);

  /// La réservation est SYNCHRONE, avant la lecture des téléchargements
  /// et avant le moindre await. Réserver deux fois avec le même jeton est
  /// idempotent, mais relit les actifs pour fermer un téléchargement récent.
  Future<void> reserve({Object? owner}) {
    _owners.add(owner ?? _legacyOwner);
    return _enqueue(_pauseActive);
  }

  /// Retire uniquement ce propriétaire. La file de reprise recontrôle les
  /// propriétaires après chaque await : une nouvelle route est prioritaire.
  Future<void> release({Object? owner}) {
    _owners.remove(owner ?? _legacyOwner);
    return _enqueue(_resumeWaiting);
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final Future<void> result = _serial.then((_) => operation());
    // L'appelant voit l'erreur ; elle ne bloque pas les réservations futures.
    _serial = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _pauseActive() async {
    if (!hasOwners) return;
    final List<String> active = _activeIds().toList();
    // Marquer d'abord TOUS les IDs : les notifications « paused » du moteur
    // ne doivent pas être interprétées comme un abandon de la file de saison.
    _pending.addAll(active);
    Object? firstError;
    StackTrace? firstStack;
    for (final String id in active) {
      if (!hasOwners) break;
      try {
        await _pause(id);
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }

  Future<void> _resumeWaiting() async {
    if (hasOwners) return;
    Object? firstError;
    StackTrace? firstStack;
    for (final String id in _pending.toList()) {
      if (hasOwners) break;
      bool resumed = false;
      try {
        await _resume(id);
        resumed = true;
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
      if (hasOwners) {
        // Une reprise avait déjà commencé quand B est arrivé. Refermer son
        // réseau AVANT de terminer la réservation de B ; conserver cet ID et
        // ceux qui n'ont pas été traités pour la sortie du dernier lecteur.
        try {
          await _pause(id);
        } catch (error, stack) {
          firstError ??= error;
          firstStack ??= stack;
        }
        break;
      }
      if (resumed) _pending.remove(id);
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }
}
