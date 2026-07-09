// =========================================================
//  xtream_url_format_store_test.dart — Persistance du format gagnant
// =========================================================
//  Vérifie, sur une vraie base SQLite (FFI en mémoire, même moteur
//  que le desktop) : sauvegarde par (source, type de contenu),
//  relecture À FROID (cache vidé = simulation d'un redémarrage de
//  l'app), oubli (re-validation), isolation entre sources, et
//  fail-open quand la base est indisponible.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/features/player/data/xtream_url_variants.dart';
import 'package:tv_king/features/playlists/data/xtream_url_format_store.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  final XtreamUrlFormatStore store = XtreamUrlFormatStore.instance;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    // Schéma minimal : uniquement ce que le store touche.
    await db.execute('''
      CREATE TABLE playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        url_formats TEXT
      )
    ''');
    await db.insert('playlists', <String, Object?>{'id': 1, 'name': 'A'});
    await db.insert('playlists', <String, Object?>{'id': 2, 'name': 'B'});
    store
      ..databaseProvider = (() async => db)
      ..resetCache();
  });

  tearDown(() async {
    await db.close();
  });

  test('sauvegarde puis relecture À FROID (cache vidé = redémarrage)',
      () async {
    await store.saveWinningFormat(1, XtreamContentType.live, 'live:m3u8');
    store.resetCache(); // simule un redémarrage de l'app
    expect(
      await store.winningFormat(1, XtreamContentType.live),
      'live:m3u8',
    );
  });

  test('les types de contenu sont indépendants pour une même source',
      () async {
    await store.saveWinningFormat(1, XtreamContentType.live, 'live:ts');
    await store.saveWinningFormat(1, XtreamContentType.movie, 'none:');
    store.resetCache();
    expect(await store.winningFormat(1, XtreamContentType.live), 'live:ts');
    expect(await store.winningFormat(1, XtreamContentType.movie), 'none:');
    expect(await store.winningFormat(1, XtreamContentType.series), isNull);
  });

  test('les sources sont isolées entre elles', () async {
    await store.saveWinningFormat(1, XtreamContentType.live, 'live:m3u8');
    store.resetCache();
    expect(await store.winningFormat(2, XtreamContentType.live), isNull);
  });

  test('clearWinningFormat oublie le format (re-validation) et persiste',
      () async {
    await store.saveWinningFormat(1, XtreamContentType.live, 'live:m3u8');
    expect(
      await store.clearWinningFormat(1, XtreamContentType.live),
      isTrue,
    );
    // Plus rien à oublier au 2e appel.
    expect(
      await store.clearWinningFormat(1, XtreamContentType.live),
      isFalse,
    );
    store.resetCache();
    expect(await store.winningFormat(1, XtreamContentType.live), isNull);
  });

  test('mise à JOUR du format mémorisé (panel qui change)', () async {
    await store.saveWinningFormat(1, XtreamContentType.live, 'live:m3u8');
    await store.saveWinningFormat(1, XtreamContentType.live, 'none:m3u8');
    store.resetCache();
    expect(
      await store.winningFormat(1, XtreamContentType.live),
      'none:m3u8',
    );
  });

  test('source inconnue en base → null, sans exception', () async {
    expect(await store.winningFormat(999, XtreamContentType.live), isNull);
  });

  test('fail-open : base indisponible → null, jamais d\'exception',
      () async {
    store
      ..databaseProvider = (() async => throw StateError('base morte'))
      ..resetCache();
    expect(await store.winningFormat(1, XtreamContentType.live), isNull);
    // save/clear ne lancent pas non plus.
    await store.saveWinningFormat(1, XtreamContentType.live, 'live:ts');
    // Le cache mémoire, lui, continue de servir la session courante.
    expect(await store.winningFormat(1, XtreamContentType.live), 'live:ts');
  });
}
