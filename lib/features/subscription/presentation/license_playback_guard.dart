// =========================================================
//  license_playback_guard.dart — Coupe le player si plus d'abo
// =========================================================
//  Un freeloader qui a ouvert le lecteur PENDANT un essai (ou un
//  abo encore valide) ne doit pas continuer à streamer après un
//  gel / ban / expiration. Le heartbeat de présence (3 min) et le
//  sync au résumé mettent à jour SubscriptionState ; ce garde
//  ÉCOUTE et arrête tout de suite.
//
//  Léger : un listener, zéro timer, zéro requête réseau.
// =========================================================

import 'package:flutter/widgets.dart';

import '../data/subscription_state.dart';

/// Écoute [SubscriptionState] et appelle [onRevoked] une seule fois
/// dès que [canStream] devient faux (expiré / gelé / banni / prêt).
class LicensePlaybackGuard {
  LicensePlaybackGuard({required this.onRevoked}) {
    SubscriptionState.instance.addListener(_tick);
    // Si on arrive déjà sans droit (course au boot), on coupe maintenant.
    _tick();
  }

  final VoidCallback onRevoked;
  bool _fired = false;

  void _tick() {
    if (_fired) return;
    if (!SubscriptionState.instance.isLoaded) return;
    if (SubscriptionState.instance.canStream) return;
    _fired = true;
    onRevoked();
  }

  void dispose() {
    SubscriptionState.instance.removeListener(_tick);
  }
}
