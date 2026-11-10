// La classification adulte doit survivre à Reprendre et aux conversions
// du lecteur ; l'absence de métadonnée historique n'est pas un « false ».
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cinema/data/cinema_repository.dart';
import 'package:tv_king/features/cinema/data/watch_progress.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_common.dart';
import 'package:tv_king/features/tv/presentation/tv_vod_player_screen.dart';

const _normal = WatchEntry(
  id: 'p123:m:101',
  isEpisode: false,
  title: 'Programme du soir',
  streamUrl: 'http://fixture.test/movie/101.mp4',
  sourceKey: 'p123',
  remoteId: '101',
  posMs: 60000,
  durMs: 600000,
  updatedAt: 1,
);

const _film = CinemaTitle(
  id: 'p123:m:101',
  kind: CinemaKind.movie,
  sourceKey: 'p123',
  remoteId: '101',
  name: 'Programme du soir',
  categoryKey: 'categorie-neutre',
  searchKey: 'programme du soir',
  streamUrl: 'http://fixture.test/movie/101.mp4',
);

const _series = CinemaTitle(
  id: 'p123:s:301',
  kind: CinemaKind.series,
  sourceKey: 'p123',
  remoteId: '301',
  name: 'Les rendez-vous',
  categoryKey: 'categorie-neutre',
  searchKey: 'les rendez-vous',
);

const _episode = CinemaEpisode(
  id: 'p123:e:401',
  remoteId: '401',
  seriesId: 'p123:s:301',
  season: 2,
  number: 3,
  title: 'La rencontre',
  streamUrl: 'http://fixture.test/series/401.mkv',
  containerExt: 'mkv',
);

WatchEntry _roundTrip(WatchEntry entry) =>
    WatchEntry.fromJson(jsonDecode(jsonEncode(entry.toJson())))!;

WatchEntry _legacy() {
  final Map<String, Object?> json = _normal.toJson()..remove('adult');
  return WatchEntry.fromJson(json)!;
}

class _PushObserver extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final CinemaRepository cinema = CinemaRepository.instance;

  setUp(() {
    ActiveProfile.instance.set('adult_metadata_fixture', playlistIds: <int>[123]);
    cinema.clear();
  });
  tearDown(cinema.clear);

  test('nouvelle reprise normale écrit explicitement adult:false', () {
    expect(_normal.toJson().containsKey('adult'), isTrue);
    expect(_normal.toJson()['adult'], isFalse);
    final WatchEntry restored = _roundTrip(_normal);
    expect(restored.isAdult, isFalse);
    expect(restored.adultClassificationKnown, isTrue);
    expect(restored.posMs, 60000);
    expect(restored.streamUrl, _normal.streamUrl);
  });

  test('ancienne reprise sans adult reste inconnue après copie et lecture', () {
    final WatchEntry legacy = _legacy();
    expect(legacy.isAdult, isFalse);
    expect(legacy.adultClassificationKnown, isFalse);
    final WatchEntry updated = legacy.copyWith(posMs: 90000, updatedAt: 2);
    expect(updated.toJson().containsKey('adult'), isFalse);
    final WatchEntry restored = _roundTrip(updated);
    expect(restored.adultClassificationKnown, isFalse);
    expect(restored.posMs, 90000);

    final VodPlayItem item = VodPlayItem.entry(restored);
    expect(item.adultClassificationKnown, isFalse);
    final WatchEntry played = item.toEntry(posMs: 120000, durMs: 600000);
    expect(played.adultClassificationKnown, isFalse);
    expect(played.toJson().containsKey('adult'), isFalse);
  });

  test('titre adulte neutre garde son indicateur après copie et persistance', () {
    final WatchEntry adult = _normal.copyWith(isAdult: true);
    final WatchProgressStore store = WatchProgressStore();
    final WatchEntry recorded = store.record(adult.copyWith(posMs: 75000));
    final WatchEntry restored = _roundTrip(recorded);
    expect(restored.title, 'Programme du soir');
    expect(restored.isAdult, isTrue);
    expect(restored.adultClassificationKnown, isTrue);
    expect(restored.toJson()['adult'], isTrue);
    expect(restored.isResumable, isTrue);
    expect(VodPlayItem.entry(restored).toEntry(posMs: 80000, durMs: 600000).isAdult,
        isTrue);
  });

  test('film classé adulte propage le drapeau vers la reprise', () {
    final VodPlayItem item = VodPlayItem.movie(_film, isAdult: true);
    final WatchEntry entry = item.toEntry(posMs: 60000, durMs: 600000);
    expect(item.isAdult, isTrue);
    expect(entry.isAdult, isTrue);
    expect(entry.adultClassificationKnown, isTrue);
    expect(entry.sourceKey, _film.sourceKey);
    expect(entry.streamUrl, _film.streamUrl);
    final WatchEntry replay = VodPlayItem.entry(_roundTrip(entry))
        .toEntry(posMs: 90000, durMs: 600000);
    expect(replay.isAdult, isTrue);
    expect(replay.id, _film.id);
  });

  test('épisode adulte conserve classification et identité lors de Reprendre', () {
    final VodPlayItem item = VodPlayItem.episode(_episode, _series, isAdult: true);
    final WatchEntry entry = item.toEntry(posMs: 60000, durMs: 600000);
    final WatchEntry replay = VodPlayItem.entry(_roundTrip(entry))
        .toEntry(posMs: 90000, durMs: 600000);
    expect(replay.isAdult, isTrue);
    expect(replay.adultClassificationKnown, isTrue);
    expect(replay.isEpisode, isTrue);
    expect(replay.seriesId, _series.id);
    expect(replay.sourceKey, _series.sourceKey);
    expect(replay.remoteId, _episode.remoteId);
    expect(replay.season, 2);
    expect(replay.episode, 3);
    expect(replay.containerExt, 'mkv');
    expect(replay.title, _series.name);
    expect(replay.subtitle, 'S2 · E3 · La rencontre');
  });

  test('sans catalogue : inconnue, adulte affirmé, normal connu restent distincts', () {
    final WatchEntry legacy = _legacy();
    expect(cinema.adultStatusForWatch(legacy), isNull);
    expect(cinema.adultStatusForWatch(_normal), isFalse);
    expect(cinema.adultStatusForWatch(legacy.copyWith(isAdult: true)), isTrue,
        reason: 'Un indicateur adulte positif prime même si known était faux.');
    final Map<String, Object?> namedAdult = legacy.toJson()..['t'] = 'XXX';
    expect(cinema.adultStatusForWatch(WatchEntry.fromJson(namedAdult)!), isTrue,
        reason: 'Un ancien titre explicitement adulte ne doit pas devenir normal.');
  });

  testWidgets('openVod sans autorisation refuse adulte et reprise inconnue', (tester) async {
    final observer = _PushObserver();
    late BuildContext entryContext;
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: <NavigatorObserver>[observer],
      home: Builder(builder: (context) {
        entryContext = context;
        return const Text('Catalogue normal');
      }),
    ));
    final int initialPushes = observer.pushes;
    for (final VodPlayItem item in <VodPlayItem>[
      VodPlayItem.movie(_film, isAdult: true),
      VodPlayItem.entry(_legacy()),
    ]) {
      await openVod(entryContext, item);
      await tester.pump();
      expect(observer.pushes, initialPushes,
          reason: 'Aucune route de lecture ne doit être créée sans classification et accès.');
      expect(find.byType(TvVodPlayerScreen), findsNothing);
      expect(find.text('Catalogue normal'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
