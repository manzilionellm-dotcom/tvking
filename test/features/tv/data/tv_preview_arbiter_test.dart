// =========================================================
//  tv_preview_arbiter_test.dart — Un seul aperçu vivant
// =========================================================
//  DEMANDE CLIENT : passer du template A au B doit TOUT arrêter côté A
//  avant que B ouvre — « comme des états indépendants ». Sinon deux
//  décodeurs et deux connexions coexistent (comptes « 1 connexion » du
//  fournisseur → la seconde est refusée) et la vidéo traîne à venir.
//
//  Contrat vérifié :
//    1. personne ne joue → prise du créneau SANS délai (instantané) ;
//    2. quelqu'un joue → délai de passation + l'ancien est prévenu ;
//    3. reprendre son propre créneau ne coûte rien et ne notifie pas ;
//    4. un écran qui meurt ne peut PAS couper celui qui vient de naître.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/data/tv_preview_arbiter.dart';

void main() {
  late TvPreviewArbiter arbiter;
  final Object ecranA = Object();
  final Object ecranB = Object();

  setUp(() => arbiter = TvPreviewArbiter.forTest());

  test('personne ne joue → ouverture INSTANTANÉE (aucun délai)', () {
    expect(arbiter.acquire(ecranA), Duration.zero);
    expect(arbiter.holds(ecranA), isTrue);
  });

  test('un autre joue → délai de passation, et l\'ancien est prévenu', () {
    arbiter.acquire(ecranA);
    int notifications = 0;
    arbiter.addListener(() => notifications++);

    final Duration attente = arbiter.acquire(ecranB);

    expect(attente, TvPreviewArbiter.handover);
    expect(notifications, 1, reason: 'l\'écran A doit être prévenu pour '
        'libérer son décodeur');
    expect(arbiter.holds(ecranB), isTrue);
    expect(arbiter.holds(ecranA), isFalse,
        reason: 'A ne possède plus rien → il se libère de lui-même');
  });

  test('reprendre son propre créneau : gratuit et silencieux', () {
    arbiter.acquire(ecranA);
    int notifications = 0;
    arbiter.addListener(() => notifications++);

    expect(arbiter.acquire(ecranA), Duration.zero);
    expect(notifications, 0, reason: 'aucun changement → aucune libération');
  });

  test('un écran qui meurt ne coupe pas celui qui vient de naître', () {
    arbiter.acquire(ecranA);
    arbiter.acquire(ecranB); // B prend la main (changement de template)
    arbiter.release(ecranA); // …puis A finit de se démonter, en retard

    expect(arbiter.holds(ecranB), isTrue,
        reason: 'la libération tardive de A ne doit pas voler le créneau de B');
  });

  test('libération → le suivant repart INSTANTANÉMENT', () {
    arbiter.acquire(ecranA);
    arbiter.release(ecranA);
    expect(arbiter.owner, isNull);
    expect(arbiter.acquire(ecranB), Duration.zero,
        reason: 'plus personne ne décode → aucune raison d\'attendre');
  });
}
