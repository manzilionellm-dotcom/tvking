// =========================================================
//  subscription_issue_test.dart — « Ton abonnement a expiré »
// =========================================================
//  TERRAIN 2026-08-01 : le client a cherché un bug dans l'app pendant des
//  heures alors que son compte Xtream était EXPIRÉ depuis 17 jours — le
//  panel répondait HTTP 404 sur CHAQUE chaîne. L'app le savait (journal
//  « Compte: Expired ») mais ne le disait nulle part à l'écran.
//
//  Contrat de la fonction pure explainSubscriptionIssue :
//    1. date d'expiration dépassée → phrase claire AVEC la date ;
//    2. statut « Expired »/« Banned »/inconnu → phrase adaptée ;
//    3. compte SAIN → null (on n'accuse pas l'abonnement à tort) ;
//    4. comparaison de dates par rapport à un « maintenant » INJECTÉ
//       (pas d'horloge réelle → test stable dans dix ans).
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/data/failure_explainer.dart';

void main() {
  final DateTime now = DateTime(2026, 8, 1, 14, 9);

  test('expiré : la phrase porte la DATE, en clair', () {
    final String? s = explainSubscriptionIssue(
      status: 'Expired',
      expDate: DateTime(2026, 7, 15, 16, 11),
      now: now,
    );
    expect(s, isNotNull);
    expect(s, contains('15/07/2026'));
    expect(s!.toLowerCase(), contains('expiré'));
    expect(s.toLowerCase(), contains('renouvelle'));
  });

  test('actif et valide → AUCUNE accusation (null)', () {
    expect(
      explainSubscriptionIssue(
        status: 'Active',
        expDate: DateTime(2027, 1, 1),
        now: now,
      ),
      isNull,
    );
  });

  test('actif mais date dépassée → l\'expiration l\'emporte', () {
    // Cas réel : certains panels laissent « Active » après l'échéance.
    final String? s = explainSubscriptionIssue(
      status: 'Active',
      expDate: DateTime(2026, 7, 15),
      now: now,
    );
    expect(s, isNotNull);
    expect(s, contains('15/07/2026'));
  });

  test('compte banni / désactivé → phrase dédiée', () {
    final String? s =
        explainSubscriptionIssue(status: 'Banned', expDate: null, now: now);
    expect(s, isNotNull);
    expect(s!.toLowerCase(), contains('désactivé'));
  });

  test('statut inconnu du panel → phrase générique AVEC l\'état brut', () {
    final String? s =
        explainSubscriptionIssue(status: 'Suspended', expDate: null, now: now);
    expect(s, contains('Suspended'));
  });

  test('aucune info (compte non encore vérifié) → null, pas de panique', () {
    expect(explainSubscriptionIssue(status: null, expDate: null, now: now),
        isNull);
    expect(
        explainSubscriptionIssue(status: '   ', expDate: null, now: now),
        isNull);
  });
}
