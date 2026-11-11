// API existantes : ce test vérifie la valeur métier, pas un nouveau symbole.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/features/cinema/data/cinema_repository.dart';
import 'package:tv_king/features/cinema/data/watch_progress.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_common.dart';

const title = CinemaTitle(
    id: 'p99:m:123',
    kind: CinemaKind.movie,
    sourceKey: 'p99',
    remoteId: '123',
    name: 'Quenovar',
    categoryKey: 'unknown',
    searchKey: 'quenovar',
    streamUrl: 'https://fixture.invalid/movie');
const previous = WatchEntry(
    id: 'p99:m:123',
    isEpisode: false,
    title: 'Quenovar',
    streamUrl: 'https://fixture.invalid/movie',
    sourceKey: 'p99',
    remoteId: '123',
    posMs: 60000,
    durMs: 600000,
    updatedAt: 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    AppPlatform.isZuno = false;
    SharedPreferences.setMockInitialValues(
        <String, Object>{'security.kids_mode.v1': true});
    ProfileRepository.instance.resetForTesting(ProfileCatalog.fresh());
    AppPlatform.configureZuno(isAndroidHandset: false);
    await ParentalControls.instance.load();
    CinemaRepository.instance.clear();
  });
  tearDown(() {
    AppPlatform.isZuno = false;
    CinemaRepository.instance.clear();
  });

  test('Enfants : fabriquer un film inconnu ne lui attribue pas normal connu',
      () {
    expect(VodPlayItem.movie(title).adultClassificationKnown, isFalse);
    expect(VodPlayItem.movie(title, isAdult: false).adultClassificationKnown,
        isFalse);
  });
  test('Enfants : adult:false ancien ne prouve pas la catégorie actuelle', () {
    final saved = jsonEncode(previous.toJson());
    final restored = WatchEntry.fromJson(jsonDecode(saved))!;
    expect(restored.adultClassificationKnown, isTrue);
    expect(CinemaRepository.instance.adultStatusForWatch(restored), isNull);
    expect(VodPlayItem.entry(restored).adultClassificationKnown, isFalse);
    expect(jsonEncode(restored.toJson()), saved);
    expect(restored.posMs, 60000);
  });
  test(
      'adulte explicite reste adulte et 7 MOTION conserve le contrat historique',
      () {
    expect(VodPlayItem.movie(title, isAdult: true).isAdult, isTrue);
    expect(VodPlayItem.movie(title, isAdult: true).adultClassificationKnown,
        isTrue);
    AppPlatform.isZuno = false;
    expect(VodPlayItem.movie(title).adultClassificationKnown, isTrue);
    expect(CinemaRepository.instance.adultStatusForWatch(previous), isFalse);
  });
}
