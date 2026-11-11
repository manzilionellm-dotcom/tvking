// Tests portables sur le 116 : les mêmes API exposent les défauts initiaux.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/features/channels/domain/adult_channel_policy.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    AppPlatform.isZuno = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ProfileRepository.instance.resetForTesting(ProfileCatalog.fresh());
    ParentalControls.instance.kidsMode.value = false;
  });
  tearDown(() {
    AppPlatform.isZuno = false;
  });

  test('ZUNO : profil Enfants protégé dès le début de la lecture asynchrone',
      () async {
    var catalog =
        ProfileCatalog.fresh().add(name: 'Enfant', isKids: true, nowMs: 2)!;
    catalog = catalog.activate(catalog.profiles.last.id)!;
    ProfileRepository.instance.resetForTesting(catalog);
    AppPlatform.configureZuno(isAndroidHandset: false);
    ParentalControls.instance.kidsMode.value = false;
    final pending = ParentalControls.instance.load();
    expect(ParentalControls.instance.kidsMode.value, isTrue,
        reason: 'La première image peut être soumise avant la lecture disque.');
    await pending;
    expect(ParentalControls.instance.kidsMode.value, isTrue);
  });

  test('ZUNO : ancien identifiant chaud ne classe pas le média de remplacement',
      () {
    AppPlatform.configureZuno(isAndroidHandset: false);
    const old = Channel(
        id: 'reused-warm-l103',
        name: 'Journal public',
        category: 'News',
        streamUrl: 'https://fixture.invalid/old',
        isLive: true);
    const replacement = Channel(
        id: 'reused-warm-l103',
        name: 'Canal',
        category: 'XXX',
        streamUrl: 'https://fixture.invalid/new',
        isLive: true);
    expect(old.genre, isNot(ChannelGenre.adult));
    expect(isAdultChannel(replacement), isTrue,
        reason: 'Même identifiant, nouvelle catégorie réellement adulte.');
  });
}
