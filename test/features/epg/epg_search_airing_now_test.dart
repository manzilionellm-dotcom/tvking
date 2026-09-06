// =========================================================
//  epg_search_airing_now_test.dart — Chercher une ÉMISSION, trouver
//  la chaîne qui la passe EN CE MOMENT
// =========================================================
//  Demande du propriétaire (05/09/2026) : « je ne sais pas le nom de la
//  chaîne, mais je sais l'émission qui est en train de passer. »
//
//  Ce test tourne sur une VRAIE base SQLite (en mémoire, via sqflite
//  ffi) avec le schéma exact de `epg_programs`. On ne simule pas la
//  requête : on l'exécute. Une faute dans le WHERE — un `<` à la place
//  d'un `<=`, un LIKE sans jokers — se verrait ici, pas chez un client.
//
//  Ce qu'on prouve :
//    1. une émission À L'ANTENNE est trouvée par un morceau de son titre ;
//    2. la même émission PAS ENCORE commencée, ou DÉJÀ finie, n'est PAS
//       rendue — c'est tout le sens de « en ce moment » ;
//    3. la recherche ignore la casse ;
//    4. deux chaînes qui passent la même émission donnent DEUX
//       résultats (l'utilisateur choisit laquelle ouvrir) ;
//    5. une chaîne n'est jamais rendue deux fois, même si le guide
//       contient deux entrées qui se chevauchent pour elle ;
//    6. une requête vide ne rend rien (pas de « tout le guide »).
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/features/epg/data/epg_repository.dart';
import 'package:tv_king/features/epg/domain/epg_program.dart';

void main() {
  sqfliteFfiInit();

  /// Le schéma EXACT de production (copié de EpgRepository.initialize),
  /// index compris : c'est lui qui rend la requête rapide, et un test qui
  /// l'omettrait ne dirait rien de la vraie base.
  Future<Database> baseGuide() async {
    final Database db =
        await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE epg_programs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        channel_id TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        stop_time INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        category TEXT,
        icon_url TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_epg_start_time ON epg_programs(start_time)');
    return db;
  }

  // Un « maintenant » fixe : le test ne dépend pas de l'heure réelle.
  const int now = 1800000000000;
  const int h = 3600000; // une heure en millisecondes

  Future<void> programme(Database db, String chaine, String titre,
      {required int debut, required int fin}) {
    return db.insert('epg_programs', <String, Object?>{
      'channel_id': chaine,
      'start_time': debut,
      'stop_time': fin,
      'title': titre,
    });
  }

  test("une émission à l'antenne est trouvée par un morceau de son titre",
      () async {
    final Database db = await baseGuide();
    await programme(db, 'france24.fr', 'Info 24 — le journal',
        debut: now - h, fin: now + h);
    await programme(db, 'tf1.fr', 'Le film du soir',
        debut: now - h, fin: now + h);

    final List<EpgProgram> r =
        await EpgRepository.searchAiringNowIn(db, 'info 24', now: now);

    expect(r, hasLength(1));
    expect(r.single.channelId, 'france24.fr');
    expect(r.single.title, 'Info 24 — le journal');
    await db.close();
  });

  test("pas encore commencée ou déjà finie → PAS rendue", () async {
    final Database db = await baseGuide();
    // Commence dans une heure.
    await programme(db, 'a.fr', 'Info 24 — plus tard',
        debut: now + h, fin: now + 2 * h);
    // Finie il y a une heure.
    await programme(db, 'b.fr', 'Info 24 — déjà passé',
        debut: now - 3 * h, fin: now - h);
    // Se termine EXACTEMENT maintenant : `stop_time > now` est faux, donc
    // elle n'est plus à l'antenne. Le cas limite est ici pour qu'on ne
    // le « corrige » pas un jour dans le mauvais sens.
    await programme(db, 'c.fr', 'Info 24 — vient de finir',
        debut: now - h, fin: now);

    final List<EpgProgram> r =
        await EpgRepository.searchAiringNowIn(db, 'Info 24', now: now);

    expect(r, isEmpty,
        reason: 'seule une émission EN COURS a le droit de sortir ici');
    await db.close();
  });

  test('la casse ne compte pas', () async {
    final Database db = await baseGuide();
    await programme(db, 'x.fr', 'INFO 24', debut: now - h, fin: now + h);

    expect(await EpgRepository.searchAiringNowIn(db, 'info 24', now: now),
        hasLength(1));
    expect(await EpgRepository.searchAiringNowIn(db, 'iNfO', now: now),
        hasLength(1));
    await db.close();
  });

  test('deux chaînes qui passent la même émission → deux résultats',
      () async {
    final Database db = await baseGuide();
    await programme(db, 'bfm.fr', 'Le match', debut: now - h, fin: now + h);
    await programme(db, 'bfm-hd.fr', 'Le match',
        debut: now - h, fin: now + h);

    final List<EpgProgram> r =
        await EpgRepository.searchAiringNowIn(db, 'match', now: now);

    expect(r.map((EpgProgram p) => p.channelId).toSet(),
        <String>{'bfm.fr', 'bfm-hd.fr'});
    await db.close();
  });

  test("une chaîne n'est jamais rendue deux fois", () async {
    final Database db = await baseGuide();
    // Données fournisseur imparfaites : deux entrées qui se chevauchent
    // pour la MÊME chaîne. On n'affiche la chaîne qu'une fois.
    await programme(db, 'tf1.fr', 'Journal', debut: now - h, fin: now + h);
    await programme(db, 'tf1.fr', 'Journal (suite)',
        debut: now - h ~/ 2, fin: now + h);

    final List<EpgProgram> r =
        await EpgRepository.searchAiringNowIn(db, 'journal', now: now);

    expect(r, hasLength(1));
    expect(r.single.channelId, 'tf1.fr');
    await db.close();
  });

  test('requête vide → rien (jamais « tout le guide »)', () async {
    final Database db = await baseGuide();
    await programme(db, 'a.fr', 'Quelque chose', debut: now - h, fin: now + h);

    expect(await EpgRepository.searchAiringNowIn(db, '', now: now), isEmpty);
    expect(await EpgRepository.searchAiringNowIn(db, '   ', now: now), isEmpty);
    await db.close();
  });

  test('la limite est respectée', () async {
    final Database db = await baseGuide();
    for (int i = 0; i < 50; i++) {
      await programme(db, 'ch$i.fr', 'Info $i', debut: now - h, fin: now + h);
    }
    final List<EpgProgram> r =
        await EpgRepository.searchAiringNowIn(db, 'Info', now: now, limit: 10);
    expect(r, hasLength(10));
    await db.close();
  });
}
