// =========================================================
//  subscription_state.dart — État de l'essai/abonnement
// =========================================================
//  Source de vérité = Worker Cloudflare (D1 : licences + block_status).
//  Le cache local ne sert QUE de grâce HORS-LIGNE courte : quelques
//  heures, pas des jours. Sinon « mode avion = TV gratuite ».
//
//  Règle métier (alignée Worker) : on peut streamer SSI
//    - licence D1 active non expirée, OU essai serveur non expiré,
//    - ET pas gelé / banni / prêt (loaned).
//  Un verdict serveur expired/frozen/banned/loaned PRIME immédiatement
//  sur le cache payant (plus de bouclier « le serveur se trompe »).
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/observability/structured_logger.dart';
import '../../device/data/device_identity.dart';
import 'subscription_backend.dart';

/// Durée d'essai affichée (l'autorité reste le Worker / panel Tarifs).
const int kTrialDurationDays = 7;

/// Grâce HORS-LIGNE par défaut (heures). Documentée : assez pour un
/// creux Wi-Fi Firestick, trop courte pour vivre sans abo.
const int kOfflineGraceHours = 6;

/// Plafond dur : même si le Worker envoie une fenêtre plus large,
/// on n'offre JAMAIS plus de 12 h hors-ligne (anti-freeloader).
const int kOfflineGraceHoursMax = 12;

/// Ancien nom (30 j) — conservé pour les commentaires historiques.
/// Ne plus l'utiliser comme durée réelle.
const int kOfflineGraceDays = 0;

/// Intervalle mini entre deux heartbeats (Firestick ~1 Go : pas de spam).
const Duration kLicenseMinSyncInterval = Duration(minutes: 8);

/// Revalidation périodique tant que l'app tourne (ban/gel = prochaine
/// fenêtre, pas « dans 7 jours »).
const Duration kLicensePeriodicSync = Duration(minutes: 45);

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
  //                     hors-ligne (mode avion).
  //  _kTrialUntilKey  : échéance ABSOLUE de l'essai (ms epoch) émise par le
  //                     serveur. Insensible à une réinstall locale.
  //  _kHwmKey         : « high-water mark » = plus grand timestamp jamais
  //                     observé. Anti-recul d'horloge.
  //  _kSyncedKey      : on a DÉJÀ parlé au Worker. Sans ça, chaque
  //                     réinstall retombait sur un essai local de 7 j.
  static const String _kBlockKey = 'subscription.block';
  static const String _kTrialUntilKey = 'subscription.trial_until_ms';
  static const String _kHwmKey = 'subscription.hwm_ms';
  static const String _kSyncedKey = 'subscription.ever_synced';

  /// Millisecondes dans une heure / un jour.
  static const int _kHourMs = 60 * 60 * 1000;
  static const int _kDayMs = 24 * _kHourMs;

  DateTime? _firstLaunchAt;
  DateTime? _paidUntil;
  bool _loaded = false;

  /// Cache local des garde-fous serveur (cf. clés ci-dessus).
  String _blockCache = '';
  int _trialUntilCache = 0;
  int _hwmMs = 0;
  bool _everSynced = false;
  DateTime? _lastSyncAttempt;

  /// « Maintenant » anti-recul : on ne fait jamais confiance à une horloge
  /// revenue en arrière par rapport au plus grand instant déjà observé.
  int get _effectiveNowMs {
    final int n = DateTime.now().millisecondsSinceEpoch;
    return n > _hwmMs ? n : _hwmMs;
  }

  /// Snapshot du serveur (heartbeat + status). Reste `unknown` tant
  /// que la première sync n'a pas eu lieu OU si le serveur est
  /// inaccessible (mode dégradé : grâce courte, pas essai 7 j).
  RemoteSubscriptionStatus _remote = RemoteSubscriptionStatus.unknown;

  bool get isLoaded => _loaded;
  DateTime? get firstLaunchAt => _firstLaunchAt;
  RemoteSubscriptionStatus get remote => _remote;
  bool get everSynced => _everSynced;

  /// Fenêtre de grâce effective (ms), plafonnée.
  int graceWindowMs([RemoteSubscriptionStatus? snap]) {
    final RemoteSubscriptionStatus s = snap ?? _remote;
    int hours = kOfflineGraceHours;
    if (s.graceHours >= 1) {
      hours = s.graceHours;
    }
    if (hours < 1) hours = kOfflineGraceHours;
    if (hours > kOfflineGraceHoursMax) hours = kOfflineGraceHoursMax;
    return hours * _kHourMs;
  }

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
  /// fraîche ; sinon repli local STRICT (grâce courte + caches).
  SubscriptionStatus get status {
    if (!_loaded) return SubscriptionStatus.unknown;

    // ----- Source de vérité côté serveur (si dispo) -----
    if (_remote.exists) {
      if (_remote.banned) return SubscriptionStatus.banned;
      if (_remote.frozen) return SubscriptionStatus.frozen;
      // Prêt d'abo : le proprio a cédé sa ligne — plus de TV ici.
      if (_remote.loaned) return SubscriptionStatus.trialExpired;
      if (_remote.paid) return SubscriptionStatus.paid;
      // STRICT : expired serveur = expired. Plus de bouclier qui
      // réécrit « payé » à partir du cache (c'était le trou 30 j).
      if (_remote.expired) return SubscriptionStatus.trialExpired;
      return SubscriptionStatus.trialActive;
    }

    // ----- Fallback local (offline ou 1er boot avant heartbeat) -----
    final int nowMs = _effectiveNowMs;

    // 1) Blocage admin mis en cache : un compte banni/gelé ne doit PAS
    //    pouvoir esquiver le blocage simplement en passant hors-ligne.
    if (_blockCache == 'banned') return SubscriptionStatus.banned;
    if (_blockCache == 'frozen') return SubscriptionStatus.frozen;

    // 2) Abonnement payant connu (cache local = grâce glissante COURTE).
    if (_paidUntil != null &&
        _paidUntil!.millisecondsSinceEpoch > nowMs) {
      return SubscriptionStatus.paid;
    }

    // 3) Essai serveur déjà vu : on honore SON échéance, pas firstLaunch.
    if (_trialUntilCache > 0) {
      return nowMs < _trialUntilCache
          ? SubscriptionStatus.trialActive
          : SubscriptionStatus.trialExpired;
    }

    if (_firstLaunchAt == null) return SubscriptionStatus.unknown;

    // 4) Jamais parlé au Worker : grâce courte UNIQUEMENT (le temps
    //    que le 1er heartbeat aboutisse). Pas 7 jours offline = free TV.
    if (!_everSynced) {
      final int bootGrace =
          _firstLaunchAt!.millisecondsSinceEpoch + graceWindowMs();
      return nowMs < bootGrace
          ? SubscriptionStatus.trialActive
          : SubscriptionStatus.trialExpired;
    }

    // 5) Déjà synchronisé un jour, plus de cache jouable → bloqué.
    return SubscriptionStatus.trialExpired;
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

  /// Jours affichés pour un abonnement « À VIE » : ~100 ans.
  static const int kLifetimeDisplayDays = 36500;

  /// Jours restants À AFFICHER (essai OU payant OU à vie).
  int? get subscriptionDaysLeft {
    if (isLifetime) return kLifetimeDisplayDays;
    final SubscriptionStatus s = status;
    if (s == SubscriptionStatus.paid) {
      final DateTime? until = paidUntil;
      if (until == null) return kLifetimeDisplayDays;
      final int ms = until.millisecondsSinceEpoch - _effectiveNowMs;
      return ms <= 0 ? 0 : (ms / _kDayMs).ceil();
    }
    if (s == SubscriptionStatus.trialActive) return trialDaysRemaining;
    return null;
  }

  // ----- Notification d'activation (félicitations, une seule fois) -----
  static const String _kActivatedAckKey = 'subscription.activated_ack';
  bool _activatedAck = false;
  bool _justActivated = false;

  bool get justActivated => _justActivated;

  void acknowledgeActivation() {
    if (!_justActivated) return;
    _justActivated = false;
    SharedPreferences.getInstance()
        .then((SharedPreferences p) => p.setBool(_kActivatedAckKey, true))
        .catchError((Object _) => false);
  }

  static const int kExpiryWarnDays = 5;

  int? get daysUntilExpiry {
    if (isLifetime) return null;
    final SubscriptionStatus s = status;
    if (s == SubscriptionStatus.paid) {
      final DateTime? until = paidUntil;
      if (until == null) return null;
      final int ms = until.millisecondsSinceEpoch - _effectiveNowMs;
      return ms <= 0 ? 0 : (ms / _kDayMs).ceil();
    }
    if (s == SubscriptionStatus.trialActive) {
      return trialDaysRemaining;
    }
    return null;
  }

  bool get isExpiringSoon {
    final int? d = daysUntilExpiry;
    return d != null && d >= 0 && d <= kExpiryWarnDays;
  }

  /// True si l'app doit afficher un écran bloquant.
  bool get shouldBlockUser {
    if (!_loaded) return false;
    if (_remote.exists && _remote.loaned) return true;
    final SubscriptionStatus s = status;
    return s == SubscriptionStatus.frozen ||
        s == SubscriptionStatus.banned ||
        s == SubscriptionStatus.trialExpired;
  }

  /// True SSI on a le droit de charger des chaînes / lancer le player.
  bool get canStream {
    if (!_loaded) return false;
    if (shouldBlockUser) return false;
    final SubscriptionStatus s = status;
    return s == SubscriptionStatus.paid ||
        s == SubscriptionStatus.trialActive;
  }

  /// Charge l'état depuis SharedPreferences. Si c'est le 1er
  /// lancement absolu, on écrit `firstLaunchAt = now` (horloge locale
  /// + grâce courte, PAS un essai 7 j autonome).
  Future<void> initialize() async {
    if (_loaded) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int? firstMs = prefs.getInt(_kFirstLaunchKey);
      if (firstMs == null) {
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
      _blockCache = prefs.getString(_kBlockKey) ?? '';
      _trialUntilCache = prefs.getInt(_kTrialUntilKey) ?? 0;
      _hwmMs = prefs.getInt(_kHwmKey) ?? 0;
      _activatedAck = prefs.getBool(_kActivatedAckKey) ?? false;
      _everSynced = prefs.getBool(_kSyncedKey) ?? false;
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

  Future<void> markPaidUntil(DateTime until) async {
    _paidUntil = until;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPaidUntilKey, until.millisecondsSinceEpoch);
    notifyListeners();
  }

  @visibleForTesting
  Future<void> resetForTesting() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kFirstLaunchKey);
    await prefs.remove(_kPaidUntilKey);
    await prefs.remove(_kBlockKey);
    await prefs.remove(_kTrialUntilKey);
    await prefs.remove(_kHwmKey);
    await prefs.remove(_kActivatedAckKey);
    await prefs.remove(_kSyncedKey);
    _firstLaunchAt = null;
    _paidUntil = null;
    _loaded = false;
    _remote = RemoteSubscriptionStatus.unknown;
    _blockCache = '';
    _trialUntilCache = 0;
    _hwmMs = 0;
    _everSynced = false;
    _lastSyncAttempt = null;
    _activatedAck = false;
    _justActivated = false;
    notifyListeners();
  }

  /// Recharge depuis les prefs (tests : poser une horloge puis relire).
  @visibleForTesting
  Future<void> reloadForTesting() async {
    _loaded = false;
    await initialize();
  }

  /// Applique un snapshot comme si le Worker avait répondu (tests).
  @visibleForTesting
  Future<void> applyRemoteForTesting(RemoteSubscriptionStatus snap) async {
    await _applyRemoteSnapshot(snap);
  }

  /// Coupe le cache « en ligne » pour tester le repli hors-ligne.
  @visibleForTesting
  void simulateOfflineForTesting() {
    _remote = RemoteSubscriptionStatus.unknown;
    notifyListeners();
  }

  /// Verdict `blocked` de GET /api/device-source — coupe AVANT le
  /// prochain heartbeat (sondage sources = 60 s sur la box).
  Future<void> markBlockedFromSource(String reason) async {
    final String r = reason.trim().toLowerCase();
    if (r.isEmpty) return;
    final bool banned = r == 'banned';
    final bool frozen = r == 'frozen';
    final bool loaned = r == 'loaned';
    await _applyRemoteSnapshot(RemoteSubscriptionStatus(
      exists: true,
      status: banned
          ? 'banned'
          : frozen
              ? 'frozen'
              : 'active',
      paid: false,
      plan: banned
          ? 'banned'
          : frozen
              ? 'frozen'
              : loaned
                  ? 'loaned'
                  : 'expired',
      paidUntil: 0,
      daysLeft: 0,
      expired: !banned && !frozen,
      frozen: frozen,
      banned: banned,
      trialUntil: _effectiveNowMs,
      loaned: loaned,
    ));
  }

  /// Heartbeat dédoublonné : skip si un sync a déjà tourné récemment.
  /// Cold start / ban mid-session : passer [force] = true.
  Future<void> syncIfStale({
    Duration minInterval = kLicenseMinSyncInterval,
    bool force = false,
  }) async {
    final DateTime now = DateTime.now();
    if (!force &&
        _lastSyncAttempt != null &&
        now.difference(_lastSyncAttempt!) < minInterval) {
      return;
    }
    _lastSyncAttempt = now;
    await syncWithBackend();
  }

  /// Synchronise avec le backend Cloudflare.
  Future<void> syncWithBackend() async {
    _lastSyncAttempt = DateTime.now();
    try {
      final String mac = await DeviceIdentity.instance.mac;
      final RemoteSubscriptionStatus snap =
          await SubscriptionBackend.heartbeat(mac);
      if (!snap.exists) {
        // Réseau KO / Worker muet : on GARDE le cache (grâce courte).
        //
        //  ON ÉCRIT MAINTENANT LAQUELLE DES DEUX (terrain 18/09/2026).
        //  Cette ligne tombait toutes les 45 minutes, huit fois dans une
        //  nuit, toujours avec le même `remote_unknown` — alors qu'elle
        //  recouvrait trois causes sans rapport : aucun hôte joignable
        //  (la ligne du client), un hôte qui répond en erreur (NOTRE
        //  Worker), ou une casse avant l'envoi (l'appareil). Impossible
        //  de savoir qui réveiller. `heartbeat` porte désormais la
        //  raison ; on la recopie telle quelle.
        StructuredLogger.instance.warn(
          domain: 'sub',
          event: 'sync.empty',
          ctx: <String, Object?>{
            'reason': snap.raisonEchec ?? 'remote_unknown',
          },
        );
        notifyListeners();
        return;
      }
      await _applyRemoteSnapshot(snap);
    } catch (e) {
      if (kDebugMode) debugPrint('[Subscription] syncWithBackend error: $e');
      StructuredLogger.instance.warn(
        domain: 'sub',
        event: 'sync.fail',
        ctx: <String, Object?>{'error': e.toString()},
      );
    }
  }

  Future<void> _applyRemoteSnapshot(RemoteSubscriptionStatus snap) async {
    _remote = snap;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _everSynced = true;
      await prefs.setBool(_kSyncedKey, true);

      if (snap.banned) {
        _blockCache = 'banned';
      } else if (snap.frozen) {
        _blockCache = 'frozen';
      } else {
        _blockCache = '';
      }
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

      // Payé → grâce COURTE (heures), jamais au-delà de la vraie fin.
      if (snap.paid) {
        final int graceCapMs = nowMs + graceWindowMs(snap);
        final int targetMs =
            (!snap.isLifetime && snap.paidUntil > 0 && snap.paidUntil < graceCapMs)
                ? snap.paidUntil
                : graceCapMs;
        _paidUntil = DateTime.fromMillisecondsSinceEpoch(targetMs);
        await prefs.setInt(_kPaidUntilKey, targetMs);
      } else if (snap.expired || snap.frozen || snap.banned || snap.loaned) {
        // STRICT : verdict négatif → on EFFACE le cache payant.
        _paidUntil = null;
        await prefs.remove(_kPaidUntilKey);
      }

      if (snap.paid) {
        if (!_activatedAck) {
          _activatedAck = true;
          _justActivated = true;
          await prefs.setBool(_kActivatedAckKey, true);
        }
      } else if (_activatedAck) {
        _activatedAck = false;
        await prefs.setBool(_kActivatedAckKey, false);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Subscription] applyRemote failed: $e');
    }
    notifyListeners();
  }

  /// Force un re-fetch du statut serveur sans toucher au heartbeat.
  Future<void> refreshRemote() async {
    try {
      final String mac = await DeviceIdentity.instance.mac;
      final RemoteSubscriptionStatus snap =
          await SubscriptionBackend.getStatus(mac);
      if (snap.exists) {
        await _applyRemoteSnapshot(snap);
      }
    } catch (e) {
      StructuredLogger.instance.warn(
        domain: 'sub',
        event: 'status.refresh_fail',
        ctx: <String, Object?>{'error': e.toString()},
      );
    }
  }
}
