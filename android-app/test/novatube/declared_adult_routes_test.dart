import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/cinema/data/watch_progress.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/security/data/adult_access.dart';
import 'package:tv_king/features/tv/data/home_shelves.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_common.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_detail_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_content_unavailable.dart';
import 'package:tv_king/features/tv/presentation/tv_player_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_vod_player_screen.dart';
import 'package:tv_king/features/voice/domain/voice_catalog.dart';

const Channel _restrictedChannel = Channel(
  id: 'restricted-channel',
  name: 'Horizon',
  category: 'Divers',
  streamUrl: 'https://example.invalid/live',
  isLive: true,
  declaredAdult: true,
);
const Channel _ordinaryChannel = Channel(
  id: 'ordinary-channel',
  name: 'Horizon nature',
  category: 'Divers',
  streamUrl: 'https://example.invalid/live-ordinary',
  isLive: true,
);

CinemaTitle _title(CinemaKind kind, {bool adult = true}) => CinemaTitle(
      id: 'fixture-${kind.name}-$adult',
      kind: kind,
      sourceKey: 'p1',
      remoteId: '9',
      name: 'Horizon',
      categoryKey: 'divers',
      searchKey: 'horizon',
      streamUrl: 'https://example.invalid/movie.mp4',
      declaredAdult: adult,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AdultAccess.instance.lock());

  test('un signal serveur seul bloque la route Direct avant le lecteur natif',
      () {
    expect(
        const TvPlayerScreen(
                channels: <Channel>[_restrictedChannel], startIndex: 0)
            .createState(),
        isA<NovatubeUnavailableState<TvPlayerScreen>>());
    expect(
        const TvPlayerScreen(
                channels: <Channel>[_ordinaryChannel], startIndex: 0)
            .createState(),
        isNot(isA<NovatubeUnavailableState<TvPlayerScreen>>()));
  });

  test('fiches film et série à libellés neutres respectent le signal serveur',
      () {
    expect(TvMovieDetailScreen(title: _title(CinemaKind.movie)).createState(),
        isA<NovatubeUnavailableState<TvMovieDetailScreen>>());
    expect(TvSeriesScreen(title: _title(CinemaKind.series)).createState(),
        isA<NovatubeUnavailableState<TvSeriesScreen>>());
  });

  test('la route VOD et une reprise gardent le classement déclaré', () {
    final VodPlayItem item = VodPlayItem.movie(_title(CinemaKind.movie));
    final WatchEntry entry = item.toEntry(posMs: 45000, durMs: 900000);
    final VodPlayItem restored =
        VodPlayItem.entry(WatchEntry.fromJson(entry.toJson())!);
    expect(restored.declaredAdult, isTrue);
    expect(TvVodPlayerScreen(item: restored).createState(),
        isA<NovatubeUnavailableState<TvVodPlayerScreen>>());
  });

  test('favoris et reprises enfants excluent les libellés neutres déclarés',
      () {
    expect(hiddenForKids(_restrictedChannel), isTrue);
    expect(hiddenForKids(_ordinaryChannel), isFalse);
    expect(
        favoriteChannels(<Channel>[
          _restrictedChannel,
          _ordinaryChannel
        ], <String>{
          _restrictedChannel.id,
          _ordinaryChannel.id
        }, hide: hiddenForKids),
        <Channel>[_ordinaryChannel]);
    final WatchEntry adult = VodPlayItem.movie(_title(CinemaKind.movie))
        .toEntry(posMs: 45000, durMs: 900000);
    final WatchEntry ordinary =
        VodPlayItem.movie(_title(CinemaKind.movie, adult: false))
            .toEntry(posMs: 45000, durMs: 900000);
    expect(continueForHome(<WatchEntry>[adult, ordinary], kidsMode: true),
        <WatchEntry>[ordinary]);
  });

  test('recherche vocale masque chaînes, films et séries déclarés adultes', () {
    final List<VoiceHit> hits = searchCatalog(
      query: 'Horizon',
      channels: <Channel>[_restrictedChannel, _ordinaryChannel],
      movies: <CinemaTitle>[_title(CinemaKind.movie)],
      series: <CinemaTitle>[_title(CinemaKind.series)],
      hideAdult: true,
    );
    expect(hits.map((VoiceHit hit) => hit.channel?.id),
        <String>[_ordinaryChannel.id]);
  });
}
