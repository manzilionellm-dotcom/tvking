// =========================================================
//  subscription_state_strict_test.dart — anti-freeloader
// =========================================================
//  Verrouille les trous que Lionel a vus : grâce 30 j, bouclier
//  « serveur expiré = encore payé », essai local 7 j hors-ligne,
//  ban qui n'attend pas une semaine.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/subscription/data/subscription_backend.dart';
import 'package:tv_king/features/subscription/data/subscription_state.dart';

RemoteSubscriptionStatus _snap({
  bool exists = true,
  bool paid = false,
  bool expired = false,
  bool frozen = false,
  bool banned = false,
  bool loaned = false,
  String plan = 'trial',
  int paidUntil = 0,
  int daysLeft = 0,
  int trialUntil = 0,
  int graceHours = 0,
}) {
  return RemoteSubscriptionStatus(
    exists: exists,
    status: banned
        ? 'banned'
        : frozen
            ? 'frozen'
            : 'active',
    paid: paid,
    plan: plan,
    paidUntil: paidUntil,
    daysLeft: daysLeft,
    expired: expired,
    frozen: frozen,
    banned: banned,
    trialUntil: trialUntil,
    graceHours: graceHours,
    loaned: loaned,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final SubscriptionState sub = SubscriptionState.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await sub.resetForTesting();
  });

  test('grâce hors-ligne = heures, pas 30 jours', () {
    expect(kOfflineGraceHours, 6);
    expect(kOfflineGraceHoursMax, 12);
    expect(sub.graceWindowMs(), kOfflineGraceHours * 60 * 60 * 1000);
    expect(
      sub.graceWindowMs(_snap(graceHours: 48)),
      kOfflineGraceHoursMax * 60 * 60 * 1000,
    );
  });

  test('premier boot hors-ligne : grâce courte, pas essai 7 j', () async {
    await sub.initialize();
    expect(sub.everSynced, isFalse);
    expect(sub.status, SubscriptionStatus.trialActive);
    expect(sub.canStream, isTrue);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int old = DateTime.now().millisecondsSinceEpoch -
        (kOfflineGraceHours + 2) * 60 * 60 * 1000;
    await prefs.setInt('subscription.first_launch_ms', old);
    await sub.reloadForTesting();
    expect(sub.status, SubscriptionStatus.trialExpired);
    expect(sub.canStream, isFalse);
    expect(sub.shouldBlockUser, isTrue);
  });

  test('serveur expired PRIME sur le cache payant (plus de bouclier 30 j)',
      () async {
    await sub.initialize();
    final int far = DateTime.now().millisecondsSinceEpoch + 20 * 24 * 3600 * 1000;
    await sub.applyRemoteForTesting(_snap(
      paid: true,
      plan: 'paid',
      paidUntil: far,
      daysLeft: 20,
    ));
    expect(sub.status, SubscriptionStatus.paid);
    expect(sub.canStream, isTrue);

    await sub.applyRemoteForTesting(_snap(
      paid: false,
      expired: true,
      plan: 'expired',
      paidUntil: far,
    ));
    expect(sub.status, SubscriptionStatus.trialExpired);
    expect(sub.canStream, isFalse);
    expect(sub.shouldBlockUser, isTrue);
    expect(sub.paidUntil, isNull);
  });

  test('ban / gel coupent tout de suite, même hors-ligne ensuite', () async {
    await sub.initialize();
    await sub.applyRemoteForTesting(_snap(banned: true, plan: 'banned'));
    expect(sub.status, SubscriptionStatus.banned);
    expect(sub.canStream, isFalse);

    sub.simulateOfflineForTesting();
    expect(sub.status, SubscriptionStatus.banned);
    expect(sub.shouldBlockUser, isTrue);

    await sub.applyRemoteForTesting(_snap(frozen: true, plan: 'frozen'));
    expect(sub.status, SubscriptionStatus.frozen);
    sub.simulateOfflineForTesting();
    expect(sub.status, SubscriptionStatus.frozen);
  });

  test('prêt d’abonnement (loaned) = plus de TV', () async {
    await sub.initialize();
    await sub.applyRemoteForTesting(_snap(loaned: true, plan: 'loaned'));
    expect(sub.canStream, isFalse);
    expect(sub.shouldBlockUser, isTrue);
  });

  test('abo payé + offline : grâce courte encore jouable', () async {
    await sub.initialize();
    final int far = DateTime.now().millisecondsSinceEpoch + 90 * 24 * 3600 * 1000;
    await sub.applyRemoteForTesting(_snap(
      paid: true,
      plan: 'paid',
      paidUntil: far,
      daysLeft: 90,
    ));
    expect(sub.status, SubscriptionStatus.paid);

    sub.simulateOfflineForTesting();
    expect(sub.status, SubscriptionStatus.paid);
    expect(sub.canStream, isTrue);
    // Hors-ligne : paidUntil retombe sur le cache de GRÂCE (heures),
    // pas sur les 90 j serveur (sinon mode avion = TV gratuite).
    final DateTime? cached = sub.paidUntil;
    expect(cached, isNotNull);
    final int left = cached!.difference(DateTime.now()).inHours;
    expect(left, lessThanOrEqualTo(kOfflineGraceHoursMax));
    expect(left, greaterThanOrEqualTo(1));
  });

  test('device-source blocked → markBlockedFromSource coupe le player',
      () async {
    await sub.initialize();
    await sub.applyRemoteForTesting(_snap(
      paid: true,
      plan: 'paid',
      paidUntil: DateTime.now().millisecondsSinceEpoch + 86400000,
    ));
    expect(sub.canStream, isTrue);

    await sub.markBlockedFromSource('expired');
    expect(sub.canStream, isFalse);
    expect(sub.status, SubscriptionStatus.trialExpired);

    await sub.markBlockedFromSource('banned');
    expect(sub.status, SubscriptionStatus.banned);
  });

  test('essai serveur déjà vu : réinstall locale n’invente pas 7 j', () async {
    await sub.initialize();
    final int past = DateTime.now().millisecondsSinceEpoch - 1000;
    await sub.applyRemoteForTesting(_snap(
      expired: true,
      plan: 'expired',
      trialUntil: past,
    ));
    expect(sub.everSynced, isTrue);
    expect(sub.status, SubscriptionStatus.trialExpired);

    sub.simulateOfflineForTesting();
    expect(sub.status, SubscriptionStatus.trialExpired);
    expect(sub.canStream, isFalse);
  });

  test('RemoteSubscriptionStatus.fromJson lit grace_hours + loaned', () {
    final RemoteSubscriptionStatus s = RemoteSubscriptionStatus.fromJson(
      <String, dynamic>{
        'exists': true,
        'status': 'active',
        'paid': false,
        'plan': 'loaned',
        'loaned': true,
        'grace_hours': 6,
        'expired': false,
      },
    );
    expect(s.loaned, isTrue);
    expect(s.graceHours, 6);
    expect(s.canUse, isFalse);
    expect(s.shouldBlock, isTrue);
  });
}
