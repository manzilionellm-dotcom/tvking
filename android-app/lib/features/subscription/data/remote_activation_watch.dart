// =========================================================
//  remote_activation_watch.dart — Veille unique panel → box
// =========================================================
//  Avant : l'écran d'activation envoyait un HEARTBEAT (écriture en
//  base : présence, inventaire, historique) toutes les 5 secondes,
//  et l'accueil relisait les codes IPTV toutes les 20 secondes même
//  quand rien n'avait changé.
//
//  Maintenant, UNE horloge pour toute l'app TV :
//    • lecture légère GET /api/status (pas d'écriture) ;
//    • 3 s tant qu'on attend l'activation ou la première source ;
//    • 4 s une fois les chaînes là ;
//    • les codes IPTV ne sont téléchargés que si `source_rev` change ;
//    • le heartbeat (le panel voit la box en ligne) part au plus
//      une fois par minute, et seulement pendant l'attente ;
//    • réseau coupé → on ralentit (jusqu'à 45 s) et on GARDE le
//      dernier statut. Aucune chaîne en cours n'est coupée.
// =========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/remote_source_repository.dart';
import '../../tv/core/tv_activity.dart';
import '../domain/activation_pace.dart';
import 'subscription_backend.dart';
import 'subscription_state.dart';

class RemoteActivationWatch {
  RemoteActivationWatch._();
  static final RemoteActivationWatch instance = RemoteActivationWatch._();

  Timer? _timer;
  bool _run = false;
  bool _tickBusy = false;
  bool _nudge = false;
  bool _allowSourceImport = true;
  int _failures = 0;
  int? _lastSourceRev;
  DateTime _lastHeartbeat = DateTime.fromMillisecondsSinceEpoch(0);

  /// Présence panel pendant l'attente. Assez lent pour ne pas écrire
  /// en base à chaque lecture de statut.
  static const Duration _heartbeatWhileWaiting = Duration(seconds: 60);

  /// À appeler une fois le boot lancé. [allowSourceImport] est faux
  /// en mode sans échec : on lit quand même la licence (la box peut
  /// s'ouvrir), mais on ne retélécharge pas une grosse liste.
  void start({bool allowSourceImport = true}) {
    _allowSourceImport = allowSourceImport;
    if (_run) return;
    _run = true;
    // Le démarrage vient de faire un heartbeat. On ne le double pas.
    _lastHeartbeat = DateTime.now();
    _arm(ActivationPace.fast);
  }

  /// « J'ai payé — Vérifier », ou juste après un changement de
  /// licence : on regarde tout de suite, sans attendre le délai.
  void nudge() {
    _nudge = true;
    if (_tickBusy) return;
    _timer?.cancel();
    _arm(Duration.zero);
  }

  @visibleForTesting
  void stopForTesting() {
    _run = false;
    _timer?.cancel();
    _timer = null;
    _tickBusy = false;
    _nudge = false;
    _failures = 0;
    _lastSourceRev = null;
  }

  void _arm(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () async {
      await _tick();
      if (!_run) return;
      if (_nudge) {
        _nudge = false;
        _arm(Duration.zero);
        return;
      }
      _arm(ActivationPace.next(waiting: _isWaiting, failures: _failures));
    });
  }

  /// Vrai tant que l'accueil ne peut pas s'ouvrir, ou qu'il s'ouvre
  /// mais qu'aucune chaîne n'est encore en cache.
  bool get _isWaiting {
    final SubscriptionStatus s = SubscriptionState.instance.status;
    final bool open = s == SubscriptionStatus.paid ||
        s == SubscriptionStatus.trialActive;
    final bool has = PlaylistRepository.instance.currentChannels.isNotEmpty;
    return !open || !has;
  }

  Future<void> _tick() async {
    if (_tickBusy) return;
    _tickBusy = true;
    try {
      final bool waiting = _isWaiting;
      final bool heartbeatDue = waiting &&
          DateTime.now().difference(_lastHeartbeat) >= _heartbeatWhileWaiting;
      final RemoteSyncOutcome outcome = heartbeatDue
          ? await SubscriptionState.instance.syncWithBackend()
          : await SubscriptionState.instance.refreshRemote();
      if (outcome == RemoteSyncOutcome.busy) return;
      if (heartbeatDue && outcome == RemoteSyncOutcome.applied) {
        _lastHeartbeat = DateTime.now();
      }
      if (outcome != RemoteSyncOutcome.applied) {
        _failures++;
        return;
      }
      _failures = 0;
      // Tombstones du statut : on efface même si le lecteur est
      // ouvert (on n'importe pas une grosse liste à ce moment-là).
      if (snapOf().revoked.isNotEmpty) {
        await RemoteSourceRepository.applyRevocations(snapOf().revoked);
      }
      await _maybeImportSource();
    } finally {
      _tickBusy = false;
    }
  }

  RemoteSubscriptionStatus snapOf() => SubscriptionState.instance.remote;

  /// Télécharge la source si la décision pure dit oui. Un échec
  /// réseau ne mémorise pas le numéro : on réessaiera au prochain
  /// tour, sans couper ce qui joue déjà.
  Future<void> _maybeImportSource() async {
    if (!_allowSourceImport) return;
    final RemoteSubscriptionStatus snap = SubscriptionState.instance.remote;
    final bool has = PlaylistRepository.instance.currentChannels.isNotEmpty;
    final bool fetch = SourceFetchDecision.shouldFetch(
      networkOk: true,
      playbackBusy: TvActivity.isBusy,
      sourceRevKnown: snap.sourceRev != null,
      sourceRev: snap.sourceRev,
      lastFetchedRev: _lastSourceRev,
      hasChannels: has,
    );
    if (!fetch) return;
    final RemoteSyncResult result = await RemoteSourceRepository.sync();
    if (result == RemoteSyncResult.networkError) return;
    if (snap.sourceRev != null) _lastSourceRev = snap.sourceRev;
  }
}
