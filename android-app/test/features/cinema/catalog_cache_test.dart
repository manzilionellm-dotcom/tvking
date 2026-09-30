// =========================================================
//  catalog_cache_test.dart — Cache du catalogue films / séries
// =========================================================
//  Prouve, SANS réseau et SANS box :
//    • un catalogue vide ou en erreur ne remplace pas l'ancien ;
//    • une liste partielle n'est pas publiée ;
//    • le remplacement est atomique (coupure entre les deux renommages) ;
//    • la reprise reprend les morceaux déjà écrits ;
//    • le délai entre essais double, avec jitter ;
//    • on n'écrit rien dans les favoris, l'historique, les profils ;
//    • le fichier ne contient ni mot de passe ni URL de lecture.
// =========================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tv_king/features/cinema/data/catalog_cache_policy.dart';
import 'package:tv_king/features/cinema/data/catalog_disk.dart';
import 'package:tv_king/features/cinema/data/catalog_refresh.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';

void main() {
  group('Règles (sans disque)', () {
    test('délai : double à chaque essai, plafond, jitter', () {
      expect(
        catalogBackoff(attempt: 1, jitterPermille: 0),
        const Duration(milliseconds: 1500),
      );
      expect(
        catalogBackoff(attempt: 2, jitterPermille: 0),
        const Duration(milliseconds: 3000),
      );
      expect(
        catalogBackoff(attempt: 3, jitterPermille: 0),
        const Duration(milliseconds: 6000),
      );
      expect(
        catalogBackoff(attempt: 8, jitterPermille: 0),
        const Duration(milliseconds: kCatalogBackoffCapMs),
      );
      expect(
        catalogBackoff(attempt: 12, jitterPermille: 0),
        const Duration(milliseconds: kCatalogBackoffCapMs),
      );
      // 30 % de 1500 = 450.
      expect(
        catalogBackoff(attempt: 1, jitterPermille: 1000),
        const Duration(milliseconds: 1950),
      );
      expect(
        () => catalogBackoff(attempt: 0, jitterPermille: 0),
        throwsArgumentError,
      );
    });

    test('âge affiché', () {
      final DateTime now = DateTime.utc(2026, 9, 30, 12);
      expect(
        catalogAge(now.subtract(const Duration(seconds: 20)), now).unit,
        CatalogAgeUnit.justNow,
      );
      final CatalogAge minutes =
          catalogAge(now.subtract(const Duration(minutes: 12)), now);
      expect(minutes.unit, CatalogAgeUnit.minutes);
      expect(minutes.amount, 12);
      final CatalogAge hours =
          catalogAge(now.subtract(const Duration(hours: 5)), now);
      expect(hours.unit, CatalogAgeUnit.hours);
      expect(hours.amount, 5);
      final CatalogAge days =
          catalogAge(now.subtract(const Duration(days: 3)), now);
      expect(days.unit, CatalogAgeUnit.days);
      expect(days.amount, 3);
    });

    test('on ne publie pas une liste vide, partielle ou illisible', () {
      expect(
        shouldPublishCatalog(
          version: kCatalogFormatVersion,
          complete: true,
          categoryCount: 2,
          coveredCategories: 2,
          titleCount: 10,
        ),
        isTrue,
      );
      expect(
        shouldPublishCatalog(
          version: kCatalogFormatVersion,
          complete: true,
          categoryCount: 2,
          coveredCategories: 2,
          titleCount: 0,
        ),
        isFalse,
        reason: 'réponse vide',
      );
      expect(
        shouldPublishCatalog(
          version: kCatalogFormatVersion,
          complete: false,
          categoryCount: 2,
          coveredCategories: 1,
          titleCount: 10,
        ),
        isFalse,
        reason: 'pas fini',
      );
      expect(
        shouldPublishCatalog(
          version: kCatalogFormatVersion,
          complete: true,
          categoryCount: 2,
          coveredCategories: 1,
          titleCount: 10,
        ),
        isFalse,
        reason: 'catégorie manquante',
      );
      expect(
        shouldPublishCatalog(
          version: 99,
          complete: true,
          categoryCount: 1,
          coveredCategories: 1,
          titleCount: 4,
        ),
        isFalse,
      );
    });

    test('une erreur ne devient pas « catégorie vide » en mémoire', () {
      expect(
          rememberCategoryList(count: 3, anySuccess: true, anyFailure: false),
          isTrue);
      expect(
          rememberCategoryList(count: 0, anySuccess: true, anyFailure: false),
          isTrue);
      expect(
          rememberCategoryList(count: 0, anySuccess: false, anyFailure: true),
          isFalse);
      expect(rememberCategoryList(count: 0, anySuccess: true, anyFailure: true),
          isFalse);
      expect(shouldCacheTitlePage(fetchFailed: true), isFalse);
      expect(shouldCacheTitlePage(fetchFailed: false), isTrue);
    });

    test('réponse vide ou erreur : on garde la liste d’avant, puis le disque',
        () {
      const List<String> previous = <String>['ancien'];
      const List<String> disk = <String>['disque'];
      expect(
        keepPreviousWhenEmpty<String>(
          incoming: const <String>[],
          previous: previous,
          disk: disk,
        ),
        previous,
      );
      expect(
        keepPreviousWhenEmpty<String>(
          incoming: null,
          previous: previous,
          disk: disk,
        ),
        previous,
      );
      expect(
        keepPreviousWhenEmpty<String>(
          incoming: null,
          previous: const <String>[],
          disk: disk,
        ),
        disk,
      );
      expect(
        keepPreviousWhenEmpty<String>(
          incoming: const <String>['neuf'],
          previous: previous,
          disk: disk,
        ),
        const <String>['neuf'],
      );
    });
  });

  group('Disque', () {
    late Directory sandbox;
    late Directory root;
    late CatalogDisk disk;
    late String signature;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('zuno-catalog-');
      root = Directory(p.join(sandbox.path, 'zuno_catalog'));
      await root.create();
      disk = CatalogDisk(root);
      signature = catalogFolderName('serveur|alice');
    });

    tearDown(() async {
      if (await sandbox.exists()) {
        await sandbox.delete(recursive: true);
      }
    });

    CatalogCategoryRecord cat(String key, String id) => CatalogCategoryRecord(
          key: key,
          name: key,
          fileId: '',
          parts: <CatalogPartRecord>[CatalogPartRecord('p1', id)],
        );

    CatalogTitleRecord film(String id, String categoryKey) =>
        CatalogTitleRecord(
          id: 'p1:m:$id',
          kind: CinemaKind.movie,
          sourceKey: 'p1',
          remoteId: id,
          name: 'Film $id',
          categoryKey: categoryKey,
          searchKey: 'film $id',
          addedAt: 100,
          containerExt: 'mkv',
          posterUrl: 'http://images.example/$id.jpg',
        );

    Future<void> publishTwo() async {
      final List<CatalogCategoryRecord> stored = await disk.beginStaging(
        signature,
        CinemaKind.movie,
        <CatalogCategoryRecord>[cat('action', '1'), cat('drame', '2')],
      );
      expect(stored, hasLength(2));
      expect(
        await disk.addChunk(
          signature,
          CinemaKind.movie,
          'action',
          <CatalogTitleRecord>[film('1', 'action')],
        ),
        isTrue,
      );
      expect(await disk.readHeader(signature, CinemaKind.movie), isNull);
      expect(
        await disk.commit(
          signature: signature,
          kind: CinemaKind.movie,
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
        isFalse,
        reason: 'un seul morceau sur deux',
      );
      expect(await disk.readHeader(signature, CinemaKind.movie), isNull);
      expect(
        await disk.addChunk(
          signature,
          CinemaKind.movie,
          'drame',
          <CatalogTitleRecord>[film('2', 'drame')],
        ),
        isTrue,
      );
      expect(
        await disk.commit(
          signature: signature,
          kind: CinemaKind.movie,
          updatedAt: DateTime.utc(2026, 9, 1, 12),
        ),
        isTrue,
      );
    }

    test(
        'remplacement atomique : rien n’est visible tant que ce n’est pas fini',
        () async {
      await publishTwo();
      final CatalogHeader? header =
          await disk.readHeader(signature, CinemaKind.movie);
      expect(header, isNotNull);
      expect(header!.titleCount, 2);
      expect(header.complete, isTrue);
      final List<CatalogTitleRecord>? action =
          await disk.readTitles(signature, CinemaKind.movie, 'action');
      expect(action, isNotNull);
      expect(action!.single.name, 'Film 1');
    });

    test('réponse vide : l’ancien catalogue reste', () async {
      await publishTwo();
      await disk.beginStaging(
        signature,
        CinemaKind.movie,
        <CatalogCategoryRecord>[cat('action', '1')],
      );
      expect(
        await disk.addChunk(signature, CinemaKind.movie, 'action',
            const <CatalogTitleRecord>[]),
        isTrue,
      );
      expect(
        await disk.commit(
          signature: signature,
          kind: CinemaKind.movie,
          updatedAt: DateTime.utc(2026, 9, 2),
        ),
        isFalse,
      );
      final CatalogHeader? header =
          await disk.readHeader(signature, CinemaKind.movie);
      expect(header!.titleCount, 2);
      expect(header.updatedAt, DateTime.utc(2026, 9, 1, 12));
    });

    test('coupure entre les deux renommages : on retrouve l’ancien', () async {
      await publishTwo();
      final Directory kindDir =
          Directory(p.join(root.path, signature, 'movie'));
      final Directory live = Directory(p.join(kindDir.path, 'live'));
      final Directory bak = Directory(p.join(kindDir.path, 'bak'));
      await live.rename(bak.path);
      await Directory(p.join(kindDir.path, 'live')).create();
      await File(p.join(kindDir.path, 'live', 'header.json'))
          .writeAsString('{');
      final CatalogHeader? header =
          await disk.readHeader(signature, CinemaKind.movie);
      expect(header!.titleCount, 2);
      expect(File(p.join(kindDir.path, 'live', 'header.json')).existsSync(),
          isTrue);
      final String raw = await File(p.join(kindDir.path, 'live', 'header.json'))
          .readAsString();
      expect(raw.contains('"titleCount":2') || raw.contains('"titleCount": 2'),
          isTrue);
    });

    test('version inconnue : on n’efface pas le fichier', () async {
      final Directory live =
          Directory(p.join(root.path, signature, 'movie', 'live'));
      await live.create(recursive: true);
      final File header = File(p.join(live.path, 'header.json'));
      await header.writeAsString(
          '{"v":99,"complete":true,"titleCount":4,"categories":[]}');
      expect(await disk.readHeader(signature, CinemaKind.movie), isNull);
      expect(await header.readAsString(), contains('"v":99'));
    });

    test('le fichier ne contient ni mot de passe ni URL de lecture', () async {
      const CinemaSource source = CinemaSource(
        key: 'p1',
        playlistId: 7,
        server: 'http://portal.example',
        username: 'alice',
        password: 's3cret-password',
      );
      final CinemaTitle title = CinemaTitle(
        id: 'p1:m:9',
        kind: CinemaKind.movie,
        sourceKey: 'p1',
        remoteId: '9',
        name: 'Matrix',
        categoryKey: 'action',
        searchKey: 'matrix',
        containerExt: 'mp4',
        streamUrl: source.movieUrl('9', 'mp4'),
        plot: 'p' * 800,
        posterUrl: 'http://images.example/matrix.jpg',
      );
      final CatalogTitleRecord record =
          CatalogTitleRecord.fromCinemaTitle(title);
      final String encoded = record.toJson().toString();
      expect(encoded.contains('s3cret-password'), isFalse);
      expect(encoded.contains('alice'), isFalse);
      expect(encoded.contains('/movie/'), isFalse);
      expect(record.plot!.length, kCatalogPlotMax);
      final CinemaTitle restored = record.toCinemaTitle(source);
      expect(restored.streamUrl, contains('s3cret-password'));
      expect(catalogFolderName('http://portal.example|alice|s3cret-password'),
          isNot(contains('alice')));
      expect(catalogFolderName('http://portal.example|alice|s3cret-password'),
          isNot(contains('s3cret')));
    });

    test('migration : favoris, historique et profils ne bougent pas', () async {
      final File favorites = File(p.join(sandbox.path, 'favorites.json'));
      final File history = File(p.join(sandbox.path, 'history.json'));
      final File profiles = File(p.join(sandbox.path, 'profiles.json'));
      await favorites.writeAsString('favoris-intacts');
      await history.writeAsString('historique-intact');
      await profiles.writeAsString('profils-intacts');
      final File inside = File(p.join(root.path, 'profiles.json'));
      await inside.writeAsString('pas-un-catalogue');

      final Directory older = Directory(p.join(root.path, '11111111'));
      final Directory newer = Directory(p.join(root.path, '22222222'));
      await older.create();
      await newer.create();
      // `touch -d` : Directory n'a pas setLastModified dans ce SDK.
      // Le tri du ménage se fait sur la date du dossier.
      await Process.run('touch', <String>['-d', '2020-01-01 00:00:00', older.path]);
      await Process.run('touch', <String>['-d', '2024-06-01 00:00:00', newer.path]);
      await disk.pruneSignatures(signature, extras: 1);
      await publishTwo();

      expect(await favorites.readAsString(), 'favoris-intacts');
      expect(await history.readAsString(), 'historique-intact');
      expect(await profiles.readAsString(), 'profils-intacts');
      expect(await inside.readAsString(), 'pas-un-catalogue');
      expect(await older.exists(), isFalse);
      expect(await newer.exists(), isTrue);
      expect(await Directory(p.join(root.path, signature)).exists(), isTrue);
    });

    test('plafond de stockage : on n’écrit pas un morceau de trop', () async {
      final CatalogDisk small = CatalogDisk(root, maxBytes: 40);
      await small.beginStaging(
        signature,
        CinemaKind.movie,
        <CatalogCategoryRecord>[cat('action', '1')],
      );
      expect(
        await small.addChunk(
          signature,
          CinemaKind.movie,
          'action',
          <CatalogTitleRecord>[film('1', 'action')],
        ),
        isFalse,
      );
      expect(await small.readHeader(signature, CinemaKind.movie), isNull);
      final CatalogProgress? progress =
          await small.readProgress(signature, CinemaKind.movie);
      expect(progress!.budgetBlocked, isTrue);
    });
  });

  group('Téléchargement', () {
    late Directory sandbox;
    late CatalogDisk disk;
    late String signature;
    final DateTime clock = DateTime.utc(2026, 9, 30, 8);

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('zuno-refresh-');
      disk = CatalogDisk(Directory(p.join(sandbox.path, 'zuno_catalog')));
      signature = catalogFolderName('serveur|alice');
    });

    tearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });

    CatalogCategoryRecord cat(String key) => CatalogCategoryRecord(
          key: key,
          name: key,
          fileId: '',
          parts: const <CatalogPartRecord>[CatalogPartRecord('p1', '1')],
        );

    CatalogTitleRecord film(String id, String categoryKey) =>
        CatalogTitleRecord(
          id: 'p1:m:$id',
          kind: CinemaKind.movie,
          sourceKey: 'p1',
          remoteId: id,
          name: 'Film $id',
          categoryKey: categoryKey,
          searchKey: 'film $id',
          addedAt: 1,
          containerExt: 'mp4',
        );

    Future<CatalogRefreshResult> go({
      required CatalogRefresher refresher,
      required Future<CatalogFetchResult<List<CatalogCategoryRecord>>>
              Function()
          fetchCategories,
      required Future<CatalogFetchResult<List<CatalogTitleRecord>>> Function(
              CatalogCategoryRecord category)
          fetchTitles,
      bool Function()? playbackBusy,
      Future<void> Function(Duration delay)? sleep,
      int Function()? jitterPermille,
      bool Function()? cancelled,
    }) {
      return refresher.run(
        disk: disk,
        signature: signature,
        kind: CinemaKind.movie,
        fetchCategories: fetchCategories,
        fetchTitles: fetchTitles,
        playbackBusy: playbackBusy ?? () => false,
        sleep: sleep ?? (Duration _) async {},
        jitterPermille: jitterPermille ?? () => 0,
        clock: () => clock,
        cancelled: cancelled,
      );
    }

    test('reprise : le morceau déjà écrit n’est pas retéléchargé', () async {
      await disk.beginStaging(
        signature,
        CinemaKind.movie,
        <CatalogCategoryRecord>[cat('action'), cat('drame')],
      );
      await disk.addChunk(
        signature,
        CinemaKind.movie,
        'action',
        <CatalogTitleRecord>[film('1', 'action')],
      );
      var categoriesCalled = 0;
      final List<String> asked = <String>[];
      final CatalogRefreshResult result = await go(
        refresher: const CatalogRefresher(),
        fetchCategories: () async {
          categoriesCalled++;
          return const CatalogFetchResult<List<CatalogCategoryRecord>>.fail();
        },
        fetchTitles: (CatalogCategoryRecord category) async {
          asked.add(category.key);
          return CatalogFetchResult<List<CatalogTitleRecord>>.ok(
            <CatalogTitleRecord>[film('2', category.key)],
          );
        },
      );
      expect(categoriesCalled, 0);
      expect(asked, <String>['drame']);
      expect(result.status, CatalogRefreshStatus.published);
      expect(result.publishedTitles, 2);
      expect(
          (await disk.readHeader(signature, CinemaKind.movie))!.titleCount, 2);
    });

    test('backoff : deux échecs puis succès, avec le délai calculé', () async {
      final List<Duration> delays = <Duration>[];
      var fails = 0;
      final CatalogRefreshResult result = await go(
        refresher: const CatalogRefresher(gap: Duration.zero),
        fetchCategories: () async =>
            CatalogFetchResult<List<CatalogCategoryRecord>>.ok(
          <CatalogCategoryRecord>[cat('action')],
        ),
        fetchTitles: (CatalogCategoryRecord category) async {
          if (fails < 2) {
            fails++;
            return const CatalogFetchResult<List<CatalogTitleRecord>>.fail();
          }
          return CatalogFetchResult<List<CatalogTitleRecord>>.ok(
            <CatalogTitleRecord>[film('1', category.key)],
          );
        },
        sleep: (Duration delay) async {
          delays.add(delay);
        },
        jitterPermille: () => 1000,
      );
      expect(result.status, CatalogRefreshStatus.published);
      expect(delays, <Duration>[
        catalogBackoff(attempt: 1, jitterPermille: 1000),
        catalogBackoff(attempt: 2, jitterPermille: 1000),
      ]);
    });

    test('limite de débit : une pause entre deux catégories', () async {
      final List<Duration> delays = <Duration>[];
      final CatalogRefreshResult result = await go(
        refresher: const CatalogRefresher(gap: kCatalogChunkGap),
        fetchCategories: () async =>
            CatalogFetchResult<List<CatalogCategoryRecord>>.ok(
          <CatalogCategoryRecord>[cat('action'), cat('drame')],
        ),
        fetchTitles: (CatalogCategoryRecord category) async {
          return CatalogFetchResult<List<CatalogTitleRecord>>.ok(
            <CatalogTitleRecord>[film(category.key, category.key)],
          );
        },
        sleep: (Duration delay) async {
          delays.add(delay);
        },
      );
      expect(result.status, CatalogRefreshStatus.published);
      expect(delays, <Duration>[kCatalogChunkGap]);
    });

    test('lecture en cours : on n’appelle pas le serveur tant que c’est occupé',
        () async {
      final List<String> events = <String>[];
      var busy = true;
      final CatalogRefreshResult result = await go(
        refresher: const CatalogRefresher(
          gap: Duration.zero,
          busyPoll: Duration(seconds: 5),
        ),
        playbackBusy: () => busy,
        fetchCategories: () async {
          events.add('categories');
          return CatalogFetchResult<List<CatalogCategoryRecord>>.ok(
            <CatalogCategoryRecord>[cat('action')],
          );
        },
        fetchTitles: (CatalogCategoryRecord category) async {
          events.add('titres');
          return CatalogFetchResult<List<CatalogTitleRecord>>.ok(
            <CatalogTitleRecord>[film('1', category.key)],
          );
        },
        sleep: (Duration delay) async {
          events.add('attente');
          expect(delay, const Duration(seconds: 5));
          busy = false;
        },
      );
      expect(result.status, CatalogRefreshStatus.published);
      expect(events.first, 'attente');
      expect(events.contains('categories'), isTrue);
      expect(events.indexOf('attente'), lessThan(events.indexOf('categories')));
      expect(events.indexOf('categories'), lessThan(events.indexOf('titres')));
    });

    test('réponse vide et erreur : le catalogue publié ne bouge pas', () async {
      await disk.beginStaging(
        signature,
        CinemaKind.movie,
        <CatalogCategoryRecord>[cat('action')],
      );
      await disk.addChunk(
        signature,
        CinemaKind.movie,
        'action',
        <CatalogTitleRecord>[film('1', 'action')],
      );
      expect(
        await disk.commit(
          signature: signature,
          kind: CinemaKind.movie,
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
        isTrue,
      );

      final CatalogRefreshResult empty = await go(
        refresher: const CatalogRefresher(maxAttempts: 1),
        fetchCategories: () async =>
            const CatalogFetchResult<List<CatalogCategoryRecord>>.ok(
                <CatalogCategoryRecord>[]),
        fetchTitles: (CatalogCategoryRecord _) async {
          fail('pas de titres à télécharger si les catégories sont vides');
        },
      );
      expect(empty.status, CatalogRefreshStatus.keptPrevious);
      expect(
          (await disk.readHeader(signature, CinemaKind.movie))!.titleCount, 1);

      final List<Duration> delays = <Duration>[];
      final CatalogRefreshResult error = await go(
        refresher: const CatalogRefresher(maxAttempts: 2),
        fetchCategories: () async =>
            const CatalogFetchResult<List<CatalogCategoryRecord>>.fail(),
        fetchTitles: (CatalogCategoryRecord _) async {
          fail('pas de titres si les catégories échouent');
        },
        sleep: (Duration delay) async {
          delays.add(delay);
        },
      );
      expect(error.status, CatalogRefreshStatus.keptPrevious);
      expect(delays, <Duration>[catalogBackoff(attempt: 1, jitterPermille: 0)]);
      expect(
          (await disk.readHeader(signature, CinemaKind.movie))!.titleCount, 1);
      expect(
        (await disk.readHeader(signature, CinemaKind.movie))!.updatedAt,
        DateTime.utc(2026, 8, 1),
      );
    });

    test('catégories vides réussies : on ne publie pas, l’ancien reste',
        () async {
      await disk.beginStaging(
        signature,
        CinemaKind.movie,
        <CatalogCategoryRecord>[cat('action')],
      );
      await disk.addChunk(
        signature,
        CinemaKind.movie,
        'action',
        <CatalogTitleRecord>[film('9', 'action')],
      );
      await disk.commit(
        signature: signature,
        kind: CinemaKind.movie,
        updatedAt: DateTime.utc(2026, 7, 1),
      );
      final CatalogRefreshResult result = await go(
        refresher: const CatalogRefresher(),
        fetchCategories: () async =>
            CatalogFetchResult<List<CatalogCategoryRecord>>.ok(
          <CatalogCategoryRecord>[cat('vide')],
        ),
        fetchTitles: (CatalogCategoryRecord category) async {
          return const CatalogFetchResult<List<CatalogTitleRecord>>.ok(
            <CatalogTitleRecord>[],
          );
        },
      );
      expect(result.status, CatalogRefreshStatus.keptPrevious);
      expect(
          (await disk.readHeader(signature, CinemaKind.movie))!.titleCount, 1);
      expect(await disk.readProgress(signature, CinemaKind.movie), isNull);
    });

    test('plafond : un second passage n’insiste pas', () async {
      disk = CatalogDisk(Directory(p.join(sandbox.path, 'zuno_catalog')),
          maxBytes: 40);
      var titlesCalled = 0;
      final CatalogRefreshResult first = await go(
        refresher: const CatalogRefresher(maxAttempts: 1),
        fetchCategories: () async =>
            CatalogFetchResult<List<CatalogCategoryRecord>>.ok(
          <CatalogCategoryRecord>[cat('action')],
        ),
        fetchTitles: (CatalogCategoryRecord category) async {
          titlesCalled++;
          return CatalogFetchResult<List<CatalogTitleRecord>>.ok(
            <CatalogTitleRecord>[film('1', category.key)],
          );
        },
      );
      expect(first.status, CatalogRefreshStatus.keptPrevious);
      expect(titlesCalled, 1);
      final CatalogRefreshResult second = await go(
        refresher: const CatalogRefresher(maxAttempts: 1),
        fetchCategories: () async {
          fail('catégories : le plafond est déjà connu');
        },
        fetchTitles: (CatalogCategoryRecord _) async {
          titlesCalled++;
          return const CatalogFetchResult<List<CatalogTitleRecord>>.fail();
        },
      );
      expect(second.status, CatalogRefreshStatus.keptPrevious);
      expect(titlesCalled, 1);
      expect(await disk.readHeader(signature, CinemaKind.movie), isNull);
    });
  });
}
