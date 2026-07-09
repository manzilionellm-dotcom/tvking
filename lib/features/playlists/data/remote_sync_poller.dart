// =========================================================
//  remote_sync_poller.dart — Livraison INSTANTANÉE des actions panel
// =========================================================
//  Avant : une source poussée par le panel n'était visible qu'au
//  prochain cycle (5 min), et une activation / un gel qu'au prochain
//  heartbeat (jusqu'à 6 h sur TV). Pas « instantané ».
//
//  Maintenant : le Worker tient une RÉVISION de synchro par MAC
//  (table device_sync, bumpée à chaque action panel : activation,
//  source poussée/retirée, gel/ban, transfert, publication…). L'app
//  poll `GET /api/sync/:mac` — une réponse JSON minuscule — toutes
//  les ~20 s (délai piloté par le serveur via `next`). Si la révision
//  a bougé, on déclenche IMMÉDIATEMENT la vraie re-synchro (sources +
//  statut d'abonnement) au lieu d'attendre les anciens cycles.
//
//  Robustesse :
//   • ne throw jamais ; réseau KO → simple re-tentative plus tard ;
//   • Worker pas encore déployé (404/erreur) → REPLI sur l'ancien
//     comportement : re-synchro des sources toutes les 5 min ;
//   • une seule re-synchro à la fois (_busy) — un bump pendant une
//     synchro en cours est rattrapé au tick suivant (la révision
//     mémorisée n'avance qu'après le déclenchement).
// =========================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../device/data/device_identity.dart';
import '../../subscription/data/subscription_backend.dart'
    show kSubscriptionBaseUrl;

class RemoteSyncPoller {
  RemoteSyncPoller._();

  static final RemoteSyncPoller instance = RemoteSyncPoller._();

  /// Cadence nominale du poll (le serveur peut l'ajuster via `next`).
  static const Duration _kDefaultInterval = Duration(seconds: 20);

  /// Cadence de repli quand le endpoint est indisponible (comportement
  /// historique : re-synchro périodique lente).
  static const Duration _kFallbackInterval = Duration(minutes: 5);

  Timer? _timer;
  int? _lastRev;
  bool _busy = false;

  Future<void> Function()? _onChange;
  Future<void> Function()? _onFallback;

  /// Démarre le poll. [onChange] est appelé quand la révision serveur a
  /// bougé (action panel → re-synchro complète). [onFallback] est appelé
  /// à cadence lente si le endpoint de synchro n'est pas disponible
  /// (équivalent de l'ancien Timer 5 min). Idempotent : un `start`
  /// remplace le précédent.
  void start({
    required Future<void> Function() onChange,
    Future<void> Function()? onFallback,
  }) {
    _onChange = onChange;
    _onFallback = onFallback;
    _timer?.cancel();
    _schedule(_kDefaultInterval);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _schedule(Duration d) {
    _timer = Timer(d, _tick);
  }

  Future<void> _tick() async {
    Duration next = _kDefaultInterval;
    try {
      final String mac = await DeviceIdentity.instance.mac;
      if (!mac.startsWith('MK:')) {
        _schedule(_kFallbackInterval);
        return;
      }
      final http.Response resp = await http
          .get(
            Uri.parse('$kSubscriptionBaseUrl/api/sync/$mac'),
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final Map<String, dynamic> body =
            jsonDecode(resp.body) as Map<String, dynamic>;
        final int rev = (body['rev'] as num?)?.toInt() ?? 0;
        final int? serverNext = (body['next'] as num?)?.toInt();
        if (serverNext != null && serverNext >= 5 && serverNext <= 600) {
          next = Duration(seconds: serverNext);
        }
        final bool changed = _lastRev != null && rev != _lastRev;
        if (changed && !_busy) {
          _busy = true;
          if (kDebugMode) {
            debugPrint('[RemoteSync] révision $rev (était $_lastRev) '
                '→ re-synchro immédiate');
          }
          try {
            await _onChange?.call();
            _lastRev = rev; // n'avance qu'après un déclenchement réussi
          } finally {
            _busy = false;
          }
        } else if (!changed) {
          _lastRev = rev;
        }
      } else {
        // Worker sans /api/sync (pas encore déployé) → ancien cycle 5 min.
        next = _kFallbackInterval;
        if (!_busy) {
          _busy = true;
          try {
            await _onFallback?.call();
          } finally {
            _busy = false;
          }
        }
      }
    } catch (e) {
      // Réseau KO / réponse inattendue : on retentera — jamais d'exception.
      if (kDebugMode) debugPrint('[RemoteSync] poll KO: $e');
      next = _kFallbackInterval;
    }
    _schedule(next);
  }
}
