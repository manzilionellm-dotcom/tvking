// =========================================================
//  followed_matches_test.dart — « choisir les matchs à suivre »
// =========================================================
//  Demande client (23/08) : « quelqu'un peut choisir les matchs où il
//  veut suivre ». Ce test verrouille les promesses que ce choix porte :
//
//   1. le choix SURVIT au redémarrage de l'app — sinon le client
//      re-sélectionne ses matchs à chaque ouverture, ce qui rendrait la
//      fonction inutilisable ;
//   2. un match choisi porte son RÉSUMÉ (noms, date, sport), pas juste
//      un identifiant : l'écran « mes matchs » doit s'afficher même
//      sans réseau ;
//   3. le MÉNAGE automatique retire les rencontres passées, faute de
//      quoi la liste enfle indéfiniment ;
//   4. le rafraîchissement des scores n'AJOUTE jamais un match que le
//      client n'a pas choisi.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/sports/data/followed_matches_service.dart';
import 'package:tv_king/features/sports/domain/sport_models.dart';

/// Un match daté par rapport à maintenant, pour écrire des scénarios
/// lisibles (« dans 3 h », « il y a 5 jours ») plutôt que des dates en dur.
SportEvent _match(
  String id, {
  required Duration fromNow,
  String home = 'Real Madrid',
  String away = 'Chelsea',
  String sport = 'Soccer',
  String? homeScore,
  String? awayScore,
}) {
  final DateTime when = DateTime.now().toUtc().add(fromNow);
  return SportEvent(
    id: id,
    home: home,
    away: away,
    sport: sport,
    homeScore: homeScore,
    awayScore: awayScore,
    timestamp: when.toIso8601String(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final FollowedMatchesService svc = FollowedMatchesService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await svc.clear();
  });

  test('suivre puis ne plus suivre : la bascule renvoie l\'état réel',
      () async {
    final SportEvent m = _match('1', fromNow: const Duration(hours: 3));
    expect(svc.isFollowed('1'), isFalse);

    expect(await svc.toggle(m), isTrue, reason: 'le 1er appui fait suivre');
    expect(svc.isFollowed('1'), isTrue);
    expect(svc.count, 1);

    expect(await svc.toggle(m), isFalse, reason: 'le 2e appui retire');
    expect(svc.isFollowed('1'), isFalse);
    expect(svc.count, 0);
  });

  test('le choix SURVIT au redémarrage, avec le résumé du match', () async {
    await svc.toggle(_match('2052478',
        fromNow: const Duration(hours: 5),
        home: 'Lakers',
        away: 'Celtics',
        sport: 'Basketball'));

    // On relit ce que l'app aurait écrit sur le disque, comme au
    // redémarrage — les préférences simulées jouent le rôle du disque.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString('sports.followed_matches.v1');
    expect(raw, isNotNull, reason: 'le choix doit être écrit, pas gardé en RAM');
    expect(raw, contains('Lakers'));
    expect(raw, contains('Basketball'),
        reason: 'la discipline aussi : la liste doit être lisible hors ligne');

    // Le résumé mémorisé suffit à afficher la ligne, sans réseau.
    final SportEvent kept = svc.all.single;
    expect(kept.home, 'Lakers');
    expect(kept.away, 'Celtics');
    expect(kept.sport, 'Basketball');
    expect(kept.startsAt, isNotNull);
  });

  test('les matchs sont rangés du plus proche au plus lointain', () async {
    await svc.toggle(_match('loin', fromNow: const Duration(days: 1)));
    await svc.toggle(_match('proche', fromNow: const Duration(hours: 2)));
    await svc.toggle(_match('milieu', fromNow: const Duration(hours: 10)));
    expect(svc.all.map((SportEvent e) => e.id).toList(),
        <String>['proche', 'milieu', 'loin']);
  });

  test('MÉNAGE : un match vieux de plus de 2 jours est oublié', () async {
    await svc.toggle(_match('vieux', fromNow: const Duration(days: -5)));
    await svc.toggle(_match('hier', fromNow: const Duration(days: -1)));
    // La purge tourne à chaque bascule : « vieux » a déjà dû disparaître.
    expect(svc.isFollowed('vieux'), isFalse,
        reason: 'sans purge, la liste enflerait indéfiniment');
    expect(svc.isFollowed('hier'), isTrue,
        reason: 'un match d\'hier a encore un score à montrer');
  });

  test('un match sans date connue est GARDÉ (jamais de disparition muette)',
      () async {
    const SportEvent sansDate =
        SportEvent(id: 'x', home: 'A', away: 'B');
    await svc.toggle(sansDate);
    expect(svc.isFollowed('x'), isTrue);
  });

  test('le rafraîchissement met à jour le score SANS rien ajouter', () async {
    await svc.toggle(_match('m1', fromNow: const Duration(hours: -1)));

    await svc.refreshKnown(<SportEvent>[
      // Le match suivi, désormais avec son score.
      _match('m1',
          fromNow: const Duration(hours: -1), homeScore: '2', awayScore: '1'),
      // Un match que le client n'a PAS choisi : il ne doit pas s'inviter.
      _match('intrus', fromNow: const Duration(hours: 2)),
    ]);

    expect(svc.count, 1, reason: 'la liste ne contient que des choix du client');
    expect(svc.isFollowed('intrus'), isFalse);
    final SportEvent m = svc.all.single;
    expect(m.hasScore, isTrue);
    expect(m.homeScore, '2');
    expect(m.awayScore, '1');
  });

  test('vider efface tout, y compris sur le disque', () async {
    await svc.toggle(_match('a', fromNow: const Duration(hours: 1)));
    await svc.toggle(_match('b', fromNow: const Duration(hours: 2)));
    expect(svc.count, 2);
    await svc.clear();
    expect(svc.count, 0);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sports.followed_matches.v1'), '[]');
  });

  test('un match sans identifiant est refusé, sans planter', () async {
    const SportEvent anonyme = SportEvent(id: '', home: 'A', away: 'B');
    expect(await svc.toggle(anonyme), isFalse);
    expect(svc.count, 0);
  });
}
