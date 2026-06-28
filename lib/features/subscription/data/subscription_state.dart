// =========================================================
//  subscription_state.dart — État de l'essai/abonnement
// =========================================================
//  Modèle commercial The Few (demande user) :
//    - 7 jours d'essai gratuit dès le 1er lancement
//    - Ensuite 5 €/an ou 9,90 € à vie, paiement sur
//      https://7themotion.com (PAS d'in-app purchase Google Play →
//      on évite la commission 30%)
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

  // ----- Durcissement sécurité (anti-fraude essai) -----
  //  _kBlockKey       : dernier verdict de BLOCAGE admin reçu du serveur
  //                     ('banned' / 'frozen' / ''). Mémorisé pour qu'un
  //                     compte banni/gelé NE PUISSE PAS esquiver en passant
  //                     hors-ligne (mode avion) — sans ce cache, le repli
  //                     local ignorait le bannissement.
  //  _kTrialUntilKey  : échéance ABSOLUE de l'essai (ms epoch) émise par le
  //                     serveur. Insensible à une remise à zéro du compteur
  //                     local, contrairement au simple « écoulé depuis
  //                     firstLaunch ».
  //  _kHwmKey         : « high-water mark » = plus grand timestamp jamais
  //                     observé. Anti-recul d'horloge : reculer la date du
  //                     téléphone ne rallonge plus l'essai.
  static const String _kBlockKey = 'subscription.block';
  static const String _kTrialUntilKey = 'subscription.trial_until_ms';
  static const String _kHwmKey = 'subscription.hwm_ms';

  /// Millisecondes dans un jour (évite un magic number répété).
  static const int _kDayMs = 24 * 60 * 60 * 1000;

  DateTime? _firstLaunchAt;
  DateTime? _paidUntil;
  bool _loaded = false;

  /// Cache local des garde-fous serveur (cf. clés ci-dessus).
  String _blockCache = '';
  int _trialUntilCache = 0;
  int _hwmMs = 0;

  /// « Maintenant » anti-recul : on ne fait jamais confiance à une horloge
  /// revenue en arrière par rapport au plus grand instant déjà observé.
  /// Empêche le contournement « je recule la date du téléphone ».
  int get _effectiveNowMs {
    final int n = DateTime.now().millisecondsSinceEpoch;
    return n > _hwmMs ? n : _hwmMs;
  }

  /// Snapshot du serveur (heartbeat + status). Reste `unknown` tant
  /// que la première sync n'a pas eu lieu OU si le serveur est
  /// inaccessible (mode dégradé : on retombe sur le trial local).
  RemoteSubscriptionStatus _remote = RemoteSubscriptionStatus.unknown;

  bool get isLoaded => _loaded;
  DateTime? get firstLaunchAt => _firstLaunchAt;
  RemoteSubscriptionStatus get remote => _remote;

  /// `true` si l'abonnement est À VIE (priorité au serveur). Permet à
  /// la carte d'afficher « Abonnement à vie » plutôt qu'une date.
  bool get isLifetime {
    if (_remote.exists && _remote.paid) return _remote.plan == 'lifetime';
    return false; // fallback local : pas d'info de plan
  }

  /// Date de fin de l'abonnement payant, ou `null` si à vie (ou pas
  /// d'info). PRIORITÉ au serveur (`paid_until`), repli sur le cache
  /// local. Utilisée par la carte pour afficher « expire le … ».
  DateTime? get paidUntil {
    if (_remote.exists && _remote.paid) {
      if (_remote.plan == 'lifetime') return null; // à vie → pas de date
      if (_remote.paidUntil > 0) {
        return DateTime.fromMillisecondsSinceEpoch(_remote.paidUntil);
      }
    }
    return _paidUntil;
  }

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
    final int nowMs = _effectiveNowMs;

    // 1) Blocage admin mis en cache : un compte banni/gelé ne doit PAS
    //    pouvoir esquiver le blocage simplement en passant hors-ligne.
    if (_blockCache == 'banned') return SubscriptionStatus.banned;
    if (_blockCache == 'frozen') return SubscriptionStatus.frozen;

    // 2) Abonnement payant connu (cache local, tolérance hors-ligne).
    if (_paidUntil != null &&
        _paidUntil!.millisecondsSinceEpoch > nowMs) {
      return SubscriptionStatus.paid;
    }

    if (_firstLaunchAt == null) return SubscriptionStatus.unknown;

    // 3) Essai : on privilégie l'échéance ABSOLUE émise par le serveur
    //    (insensible à une remise à zéro du compteur local) ; à défaut,
    //    repli sur « firstLaunch + durée d'essai ».
    final int deadline = _trialUntilCache > 0
        ? _trialUntilCache
        : _firstLaunchAt!.millisecondsSinceEpoch +
            kTrialDurationDays * _kDayMs;
    return nowMs < deadline
        ? SubscriptionStatus.trialActive
        : SubscriptionStatus.trialExpired;
  }

  /// Jours restants d'essai. Priorité serveur, fallback local.
  int get trialDaysRemaining {
    if (_remote.exists) return _remote.daysLeft;
    if (_firstLaunchAt == null) return kTrialDurationDays;
    final int nowMs = _effectiveNowMs;
    final int deadline = _trialUntilCache > 0
        ? _trialUntilCache
        : _firstLaunchAt!.millisecondsSinceEpoch +
            kTrialDurationDays * _kDayMs;
    final int remaining = ((deadline - nowMs) / _kDayMs).ceil();
    return remaining > 0 ? remaining : 0;
  }

  /// Seuil d'alerte d'expiration : on prévient le client quand il reste ≤ ce
  /// nombre de jours (abonnement payant OU essai).
  static const int kExpiryWarnDays = 5;

  /// Jours restants avant expiration (abo payant OU essai). `null` si à vie /
  /// inconnu / déjà expiré. LECTURE SEULE — n'altère JAMAIS la logique de
  /// blocage (alerte purement informative, cf. bandeau d'expiration).
  int? get daysUntilExpiry {
    if (isLifetime) return null;
    final SubscriptionStatus s = status;
    if (s == SubscriptionStatus.paid) {
      final DateTime? until = paidUntil;
      if (until == null) return null; // payant sans date / à vie
      final int ms = until.millisecondsSinceEpoch - _effectiveNowMs;
      return ms <= 0 ? 0 : (ms / _kDayMs).ceil();
    }
    if (s == SubscriptionStatus.trialActive) {
      return trialDaysRemaining;
    }
    return null; // expiré/banni/gelé/inconnu → pas une simple « alerte »
  }

  /// True si l'abonnement (payant ou essai) expire dans ≤ [kExpiryWarnDays]
  /// jours. Sert à afficher le bandeau d'alerte « pense à renouveler ».
  bool get isExpiringSoon {
    final int? d = daysUntilExpiry;
    return d != null && d >= 0 && d <= kExpiryWarnDays;
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
      // Garde-fous serveur mis en cache au boot précédent.
      _blockCache = prefs.getString(_kBlockKey) ?? '';
      _trialUntilCache = prefs.getInt(_kTrialUntilKey) ?? 0;
      _hwmMs = prefs.getInt(_kHwmKey) ?? 0;
      // Avance le high-water mark si l'horloge a légitimement progressé.
      final int nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs > _hwmMs) {
        _hwmMs = nowMs;
        await prefs.setInt(_kHwmKey, nowMs);
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
      // Mémorise les garde-fous serveur pour le mode hors-ligne :
      //  - le verdict de blocage (banni/gelé) → ne pourra plus être esquivé
      //    en passant en mode avion ;
      //  - l'échéance absolue de l'essai → insensible à un effacement du
      //    compteur local ;
      //  - avance le high-water mark anti-recul d'horloge.
      if (snap.exists) {
        final SharedPreferences prefs =
            await SharedPreferences.getInstance();
        _blockCache =
            snap.banned ? 'banned' : (snap.frozen ? 'frozen' : '');
        await prefs.setString(_kBlockKey, _blockCache);
        if (snap.trialUntil > 0) {
          _trialUntilCache = snap.trialUntil;
          await prefs.setInt(_kTrialUntilKey, snap.trialUntil);
        }
        final int nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs > _hwmMs) {
          _hwmMs = nowMs;
          await prefs.setInt(_kHwmKey, nowMs);
        }
      }
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
