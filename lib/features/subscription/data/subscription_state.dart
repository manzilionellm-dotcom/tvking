// =========================================================
//  subscription_state.dart — État de l'essai/abonnement
// =========================================================
//  Modèle commercial BLACK7 ROYAL (demande user) :
//    - 7 jours d'essai gratuit dès le 1er lancement
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

import '../../device/data/device_identity.dart';
import 'subscription_backend.dart';

/// Durée de l'essai gratuit en jours.
const int kTrialDurationDays = 7;

/// URL du site marchand (paiement externe, modèle TiViMate).
const String kPurchaseUrl = 'https://7themotion.com';

enum SubscriptionStatus {
  /// L'user n'a jamais lancé l'app — premier boot.
  unknown,

  /// Essai en cours, il reste des jours.
  trialActive,

  /// Essai épuisé, achat requis.
  trialExpired,

  /// User a payé son abonnement (validé côté serveur).
  paid,

  /// L'admin a gelé ce client — l'app ne doit plus fonctionner.
  frozen,

  /// L'admin a banni ce client — fiche conservée mais bloquée.
  banned,
}

class SubscriptionState extends ChangeNotifier {
  SubscriptionState._();
  static final SubscriptionState instance = SubscriptionState._();

  static const String _kFirstLaunchKey = 'subscription.first_launch_ms';
  static const String _kPaidUntilKey = 'subscription.paid_until_ms';

  DateTime? _firstLaunchAt;
  DateTime? _paidUntil;
  bool _loaded = false;

  /// Snapshot du serveur (heartbeat + status). Reste `unknown` tant
  /// que la première sync n'a pas eu lieu OU si le serveur est
  /// inaccessible (mode dégradé : on retombe sur le trial local).
  RemoteSubscriptionStatus _remote = RemoteSubscriptionStatus.unknown;

  bool get isLoaded => _loaded;
  DateTime? get firstLaunchAt => _firstLaunchAt;
  DateTime? get paidUntil => _paidUntil;
  RemoteSubscriptionStatus get remote => _remote;

  /// Status calculé. PRIORITÉ AU SERVEUR si on a reçu une réponse
  /// fraîche du backend ; sinon on retombe sur le calcul local.
  ///
  ///  remote.banned   → status = banned
  ///  remote.frozen   → status = frozen
  ///  remote.paid     → status = paid
  ///  remote.expired  → status = trialExpired
  ///  remote.exists   → status = trialActive (jours restants côté serveur)
  ///  (sinon)         → calcul local sur firstLaunchAt
  SubscriptionStatus get status {
    if (!_loaded) return SubscriptionStatus.unknown;

    // ----- Source de vérité côté serveur (si dispo) -----
    if (_remote.exists) {
      if (_remote.banned) return SubscriptionStatus.banned;
      if (_remote.frozen) return SubscriptionStatus.frozen;
      if (_remote.paid) return SubscriptionStatus.paid;
      if (_remote.expired) return SubscriptionStatus.trialExpired;
      return SubscriptionStatus.trialActive;
    }

    // ----- Fallback local (offline ou 1er boot avant heartbeat) -----
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

  /// Jours restants d'essai. Priorité serveur, fallback local.
  int get trialDaysRemaining {
    if (_remote.exists) return _remote.daysLeft;
    if (_firstLaunchAt == null) return kTrialDurationDays;
    final int daysSince =
        DateTime.now().difference(_firstLaunchAt!).inDays;
    final int remaining = kTrialDurationDays - daysSince;
    return remaining > 0 ? remaining : 0;
  }

  /// True si l'app doit afficher un écran bloquant (gelé, banni,
  /// ou essai expiré non payé). Utilisé par `_AppEntry` au boot.
  bool get shouldBlockUser {
    final SubscriptionStatus s = status;
    return s == SubscriptionStatus.frozen ||
        s == SubscriptionStatus.banned ||
        s == SubscriptionStatus.trialExpired;
  }

  /// Charge l'état depuis SharedPreferences. Si c'est le 1er
  /// lancement absolu, on écrit `firstLaunchAt = now()` pour
  /// démarrer le compte à rebours de l'essai (kTrialDurationDays).
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

  /// Synchronise avec le backend Cloudflare.
  ///
  /// Étapes :
  ///   1. POST /api/heartbeat — déclare au serveur "je suis là".
  ///      Si nouveau, le serveur crée la fiche avec trial 10 j.
  ///      Sinon il met juste à jour last_seen_at.
  ///   2. Le résultat du heartbeat contient déjà le statut courant,
  ///      pas besoin d'un GET séparé.
  ///   3. On stocke en `_remote` et on notifie pour rebuild les UI.
  ///
  /// À appeler au boot (depuis `_AppEntry`) après l'init du
  /// DeviceIdentity. Si le réseau est down, `_remote` reste
  /// `unknown` et le calcul retombe sur le trial local — l'app
  /// reste utilisable hors-ligne.
  Future<void> syncWithBackend() async {
    try {
      final String mac = await DeviceIdentity.instance.mac;
      final RemoteSubscriptionStatus snap =
          await SubscriptionBackend.heartbeat(mac);
      _remote = snap;
      // Si le serveur dit 'paid', on persiste un fallback local
      // pour 7 jours (au cas où l'app passe offline ensuite, on
      // ne bloquera pas le user qui a déjà payé).
      if (snap.paid) {
        final DateTime fallback =
            DateTime.now().add(const Duration(days: 7));
        if (_paidUntil == null || fallback.isAfter(_paidUntil!)) {
          await markPaidUntil(fallback);
        }
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('[Subscription] syncWithBackend error: $e');
    }
  }

  /// Force un re-fetch du statut serveur sans toucher au heartbeat
  /// (le `last_seen_at` ne bouge pas). Utilisé par le pull-to-refresh.
  Future<void> refreshRemote() async {
    try {
      final String mac = await DeviceIdentity.instance.mac;
      _remote = await SubscriptionBackend.getStatus(mac);
      notifyListeners();
    } catch (_) {}
  }
}
