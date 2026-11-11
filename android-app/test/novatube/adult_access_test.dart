import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/novatube_content_policy.dart';
import 'package:tv_king/core/app/novatube_private_features.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/cinema/data/watch_progress.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/security/data/adult_access.dart';
import 'package:tv_king/features/security/data/app_pin_settings.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';
import 'package:tv_king/features/tv/data/home_shelves.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_common.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_screen.dart';
import 'package:tv_king/features/vod/data/download_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AdultAccess access;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ActiveProfile.instance.set('p1');
    await ParentalControls.instance.load();
    access = AdultAccess.forTesting(supported: true);
    await access.load();
  });

  tearDown(() => access.dispose());

  test('premier lancement verrouillé, ancien PIN par défaut refusé', () async {
    expect(access.enabled.value, isFalse);
    expect(access.canAccess, isFalse);
    expect(await access.enableWithPin('0000'), isFalse);
    expect(await access.unlockWithPin('3579'), isFalse);
  });

  test('bon PIN requis pour activer puis pour chaque nouvelle visite',
      () async {
    await AppPinSettings.instance.setPin('3579');
    expect(await access.enableWithPin('2580'), isFalse);
    expect(access.enabled.value, isFalse);
    expect(await access.enableWithPin('3579'), isTrue);
    expect(access.canAccess, isTrue);
    access.lock();
    expect(access.enabled.value, isTrue);
    expect(access.canAccess, isFalse);
    expect(await access.unlockWithPin('2580'), isFalse);
    expect(await access.unlockWithPin('3579'), isTrue);
    await access.disable();
    expect(access.enabled.value, isFalse);
    expect(await access.unlockWithPin('3579'), isFalse);
  });

  test('activation conservée après redémarrage, session jamais conservée',
      () async {
    await AppPinSettings.instance.setPin('3579');
    expect(await access.enableWithPin('3579'), isTrue);
    final AdultAccess reopened = AdultAccess.forTesting(supported: true);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.enabled.value, isTrue);
    expect(reopened.unlocked.value, isFalse);
    expect(reopened.canAccess, isFalse);
  });

  test('changement de profil verrouille avant toute lecture asynchrone',
      () async {
    await AppPinSettings.instance.setPin('3579');
    await access.enableWithPin('3579');
    ActiveProfile.instance.set('p2');
    expect(access.canAccess, isFalse);
    expect(access.unlocked.value, isFalse);
    await access.load();
    expect(access.enabled.value, isFalse);
    expect(await access.enableWithPin('3579'), isFalse);
    ActiveProfile.instance.set('p1');
    await access.load();
    expect(access.enabled.value, isTrue);
    expect(access.canAccess, isFalse);
  });

  test('mode enfants coupe une session et refuse son ouverture avec le PIN',
      () async {
    await AppPinSettings.instance.setPin('3579');
    await access.enableWithPin('3579');
    await ParentalControls.instance.setKidsMode(true);
    expect(access.unlocked.value, isFalse);
    expect(access.canAccess, isFalse);
    expect(await access.enableWithPin('3579'), isFalse);
    expect(await access.unlockWithPin('3579'), isFalse);
  });

  test('cinq erreurs verrouillent aussi la bonne saisie pendant le délai',
      () async {
    await AppPinSettings.instance.setPin('3579');
    await access.enableWithPin('3579');
    access.lock();
    for (int i = 0; i < 5; i++) {
      expect(await access.unlockWithPin('2580'), isFalse);
    }
    expect(await access.unlockWithPin('3579'), isFalse);
    expect(await AppPinSettings.instance.lockRemainingMs(), greaterThan(0));
  });

  test('édition sans option ne se réactive ni par préférences ni par PIN',
      () async {
    await AppPinSettings.instance.setPin('3579');
    await access.enableWithPin('3579');
    final AdultAccess play = AdultAccess.forTesting(supported: false);
    addTearDown(play.dispose);
    await play.load();
    expect(play.enabled.value, isFalse);
    expect(await play.enableWithPin('3579'), isFalse);
    expect(await play.unlockWithPin('3579'), isFalse);
    expect(play.canAccess, isFalse);
  });

  test('import privé distinct de l’autorisation de lecture', () {
    expect(NovatubeContentPolicy.canImport(name: 'Fixture', category: '18+'),
        NovatubePrivateFeatures.adultCatalogs);
    expect(NovatubeContentPolicy.allows(name: 'Fixture', category: '18+'),
        isFalse);
    expect(NovatubeContentPolicy.allows(name: 'Fixture', category: 'Sports'),
        isTrue);
  });

  test('catégorie conservée dans historique, reprise et téléchargements', () {
    const VodPlayItem item = VodPlayItem(
      id: 'fixture',
      isEpisode: false,
      title: 'Titre neutre',
      url: 'https://example.invalid/fixture.mp4',
      categoryKey: '18+',
    );
    final WatchEntry entry = item.toEntry(posMs: 40000, durMs: 600000);
    final WatchEntry restored = WatchEntry.fromJson(entry.toJson())!;
    expect(restored.categoryKey, '18+');
    expect(VodPlayItem.entry(restored).categoryKey, '18+');
    expect(VodPlayItem.entry(restored).isAllowedInPlay, isFalse);
    const Download download = Download(
      id: 'fixture',
      name: 'Titre neutre',
      sourceUrl: 'https://example.invalid/fixture.mp4',
      filePath: '/fixture.mp4',
      status: DownloadStatus.paused,
      receivedBytes: 0,
      totalBytes: 0,
      createdAt: 0,
      category: '18+',
      profileId: 'p2',
    );
    final Download copy = Download.fromMap(download.copyWith().toMap());
    expect(copy.category, '18+');
    expect(copy.profileId, 'p2');
  });

  test('reprise série : la catégorie suit aussi l’épisode suivant', () {
    const WatchEntry entry = WatchEntry(
      id: 'p3:e:901',
      isEpisode: true,
      title: 'Série au nom neutre',
      streamUrl: 'https://example.invalid/episode-1.mp4',
      posMs: 40000,
      durMs: 600000,
      updatedAt: 1,
      sourceKey: 'p3',
      remoteId: '901',
      categoryKey: '+18',
      seriesId: 'p3:s:123',
      season: 1,
      episode: 1,
    );
    final CinemaTitle series = seriesTitleFromEntry(entry);
    expect(series.categoryKey, '+18');
    const CinemaEpisode next = CinemaEpisode(
      id: 'p3:e:902',
      remoteId: '902',
      seriesId: 'p3:s:123',
      season: 1,
      number: 2,
      title: 'Épisode suivant',
      streamUrl: 'https://example.invalid/episode-2.mp4',
      containerExt: 'mp4',
    );
    final VodPlayItem item = VodPlayItem.episode(next, series);
    expect(item.toEntry(posMs: 0, durMs: 600000).categoryKey, '+18');
    expect(item.toVodMovie().category, '+18');
    expect(item.isAllowedInPlay, isFalse);
  });

  test('accueil : catégorie +18 masquée sans cache ou malgré un ancien genre', () {
    const Channel cold = Channel(
      id: 'novatube-adult-home-cold-fixture',
      name: 'Chaîne neutre',
      category: '+18',
      streamUrl: 'https://example.invalid/live.ts',
      isLive: true,
    );
    expect(ChannelPrecompute.cachedGenre(cold), isNull);
    expect(hiddenForKids(cold), isTrue);

    // Une actualisation peut réutiliser l’ID d’une ancienne chaîne sportive.
    // La protection doit lire les nouvelles métadonnées, pas ce vieux cache.
    const Channel previous = Channel(
      id: 'novatube-adult-home-refreshed-fixture',
      name: 'Chaîne neutre',
      category: 'Sports',
      streamUrl: 'https://example.invalid/live.ts',
      isLive: true,
    );
    expect(previous.genre, ChannelGenre.sports);
    expect(hiddenForKids(previous), isFalse);
    const Channel refreshed = Channel(
      id: 'novatube-adult-home-refreshed-fixture',
      name: 'Chaîne neutre',
      category: '+18',
      streamUrl: 'https://example.invalid/live.ts',
      isLive: true,
    );
    expect(ChannelPrecompute.cachedGenre(refreshed), ChannelGenre.sports);
    expect(hiddenForKids(refreshed), isTrue);
  });
}
