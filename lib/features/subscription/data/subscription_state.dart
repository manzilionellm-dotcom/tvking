// =========================================================
//  subscription_state.dart — État de l'essai/abonnement
// =========================================================
//  Modèle commercial 7 MOTION (demande user) :
//    - 10 jours d'essai gratuit dès le 1er lancement
//    - Ensuite 13 €/an, paiement sur https://7themotion.com
//      (PAS d'in-app purchase Google Play → bypass de la
//       commission 30%)
//
//  Cette classe persiste UNIQUEMENT le timestamp du 1er lancement
//  via SharedPreferences. Tout le calcul (jours restants, etc.)
//  est dérivé localement — pas de backend pour V1.
//
//  Pour la V2 (gestion centralisée), on branchera DeviceIdentity
//  + un endpoint 7themotion.com qui retourne `{trialDays, paid, expiresAt}`
//  pour permettre la révocation et la prolongation à distance.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Durée de l'essai gratuit en jours.
const int kTrialDurationDays = 10;

/// URL du site marchand (paiement externe, modèle TiViMate).
const String kPurchaseUrl = 'https://7themotion.com';

enum SubscriptionStatus {
  /// L'user n'a jamais lancé l'app — premier boot.
  unknown,

  /// Essai en cours, il reste des jours.
  trialActive,

  /// Essai épuisé, achat requis.
  trialExpired,

  /// User a payé son abonnement (pour la V2, pas encore branché).
  paid,
}

class SubscriptionState extends ChangeNotifier {
  SubscriptionState._();
  static final SubscriptionState instance = SubscriptionState._();

  static const String _kFirstLaunchKey = 'subscription.first_launch_ms';
  static const String _kPaidUntilKey = 'subscription.paid_until_ms';

  DateTime? _firstLaunchAt;
  DateTime? _paidUntil;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  DateTime? get firstLaunchAt => _firstLaunchAt;
  DateTime? get paidUntil => _paidUntil;

  /// Status calculé live à partir des dates persistées.
  SubscriptionStatus get status {
    if (!_loaded) return SubscriptionStatus.unknown;
    final DateTime now = DateTime.now();
    if (_paidUntil != null && _paidUntil!.isAfter(now)) {
      return SubscriptionStatus.paid;
    }
    if (_firstLaunchAt == null) return SubscriptionStatus.unknown;
    final int daysSince = now.difference(_firstLaunchAt!).inDays;
    if (daysSince < kTrialDurationDays) {
      return SubscriptionStatus.trialActive;
    }
    return SubscriptionStatus.trialExpired;
  }

  /// Jours restants d'essai (0 si épuisé ou inconnu).
  int get trialDaysRemaining {
    if (_firstLaunchAt == null) return kTrialDurationDays;
    final int daysSince =
        DateTime.now().difference(_firstLaunchAt!).inDays;
    final int remaining = kTrialDurationDays - daysSince;
    return remaining > 0 ? remaining : 0;
  }

  /// Charge l'état depuis SharedPreferences. Si c'est le 1er
  /// lancement absolu, on écrit `firstLaunchAt = now()` pour
  /// démarrer le compte à rebours des 10 jours.
  Future<void> initialize() async {
    if (_loaded) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int? firstMs = prefs.getInt(_kFirstLaunchKey);
      if (firstMs == null) {
        // Tout premier boot → on enregistre maintenant.
        final int nowMs = DateTime.now().millisecondsSinceEpoch;
        await prefs.setInt(_kFirstLaunchKey, nowMs);
        _firstLaunchAt = DateTime.fromMillisecondsSinceEpoch(nowMs);
      } else {
        _firstLaunchAt = DateTime.fromMillisecondsSinceEpoch(firstMs);
      }
      final int? paidMs = prefs.getInt(_kPaidUntilKey);
      if (paidMs != null) {
        _paidUntil = DateTime.fromMillisecondsSinceEpoch(paidMs);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Subscription] init failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  /// Marque l'abonnement comme payé jusqu'à `until`. Appelé par
  /// la V2 quand on validera la licence côté serveur 7themotion.com.
  /// Pour V1, exposé pour les tests dev uniquement.
  Future<void> markPaidUntil(DateTime until) async {
    _paidUntil = until;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPaidUntilKey, until.millisecondsSinceEpoch);
    notifyListeners();
  }

  /// Reset pour debug (ne pas appeler en prod).
  @visibleForTesting
  Future<void> resetForTesting() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kFirstLaunchKey);
    await prefs.remove(_kPaidUntilKey);
    _firstLaunchAt = null;
    _paidUntil = null;
    _loaded = false;
    notifyListeners();
  }
}
