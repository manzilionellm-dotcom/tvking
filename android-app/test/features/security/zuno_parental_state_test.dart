import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/features/channels/domain/adult_channel_policy.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';

const unknown = Channel(
    id: 'l103-unclassified',
    name: 'Quenovar',
    category: '',
    streamUrl: 'https://fixture.invalid/unknown',
    isLive: true);
const normal = Channel(
    id: 'l103-classified',
    name: 'Journal',
    category: 'News',
    streamUrl: 'https://fixture.invalid/news',
    isLive: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final controls = ParentalControls.instance;
  final profiles = ProfileRepository.instance;
  setUp(() {
    AppPlatform.isZuno = false;
    controls.resetProtectionForTesting();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    profiles.resetForTesting(ProfileCatalog.fresh());
    AppPlatform.configureZuno(isAndroidHandset: false);
  });
  tearDown(() {
    AppPlatform.isZuno = false;
    controls.resetProtectionForTesting();
    RepairFlags.debugReset();
  });

  test(
      'catalogue confirmé : JSON incomplet ne devient pas un profil adulte connu',
      () {
    expect(ProfileCatalog.confirmsActiveProfile(null), isTrue);
    expect(
        ProfileCatalog.confirmsActiveProfile(ProfileCatalog.fresh().encode()),
        isTrue);
    for (final value in <String>[
      '{cassé',
      '{}',
      '{"activeId":"absent","profiles":[]}'
    ]) {
      expect(ProfileCatalog.confirmsActiveProfile(value), isFalse,
          reason: value);
    }
    final map =
        jsonDecode(ProfileCatalog.fresh().encode()) as Map<String, dynamic>;
    ((map['profiles'] as List<Object?>).first as Map<String, dynamic>)
        .remove('isKids');
    expect(ProfileCatalog.confirmsActiveProfile(jsonEncode(map)), isFalse);
  });

  test('lecture fautive reste fermée et ne modifie aucune préférence',
      () async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{ProfileKeys.kidsMode('p1'): 'incorrect'});
    controls.protectZunoBeforeProfile();
    await controls.loadBeforeFirstFrame();
    expect(controls.readiness.value, ParentalReadiness.failed);
    expect(controls.contentReady, isFalse);
    expect(controls.kidsMode.value, isTrue);
    expect(
        (await SharedPreferences.getInstance()).get(ProfileKeys.kidsMode('p1')),
        'incorrect');
  });

  test('lecture des restrictions enfant ne crée aucune écriture automatique',
      () async {
    var catalog =
        ProfileCatalog.fresh().add(name: 'Enfant', isKids: true, nowMs: 2)!;
    catalog = catalog.activate(catalog.profiles.last.id)!;
    profiles.resetForTesting(catalog);
    await controls.loadBeforeFirstFrame();
    expect(controls.contentReady, isTrue);
    expect(controls.kidsMode.value, isTrue);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    await controls.setKidsMode(false);
    expect(controls.kidsMode.value, isTrue);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  test(
      'enfants : inconnu et other restent cachés, connu normal devient visible',
      () async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{ProfileKeys.kidsMode('p1'): true});
    await controls.loadBeforeFirstFrame();
    expect(isHiddenFromNormalCatalog(unknown), isTrue);
    expect(unknown.genre, ChannelGenre.other);
    expect(isHiddenFromNormalCatalog(unknown), isTrue);
    expect(normal.genre, isNot(ChannelGenre.other));
    expect(isHiddenFromNormalCatalog(normal), isFalse);
  });

  test(
      'changement de portée ferme immédiatement puis confirme la nouvelle lecture',
      () async {
    await controls.loadBeforeFirstFrame();
    expect(controls.contentReady, isTrue);
    final generation = controls.contentGeneration;
    ActiveProfile.instance.notifyPlaylistRemoved(1);
    expect(controls.contentReady, isFalse);
    expect(controls.contentGeneration, greaterThan(generation));
    await controls.load();
    expect(controls.contentReady, isTrue);
  });

  test('repli attente immédiate n’accorde aucune permission', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      RepairFlags.parentalWaitImmediateKey: true,
      ProfileKeys.kidsMode('p1'): 'incorrect',
    });
    await RepairFlags.load();
    expect(RepairFlags.parentalWaitImmediate, isTrue);
    controls.protectZunoBeforeProfile();
    await controls.loadBeforeFirstFrame(budget: Duration.zero);
    expect(controls.contentReady, isFalse);
    await controls.load();
    expect(controls.contentReady, isFalse);
  });

  test('7 MOTION garde ses permissions et son cache historique', () async {
    AppPlatform.isZuno = false;
    await controls.load();
    expect(controls.protectsZuno, isFalse);
    expect(controls.kidsMode.value, isFalse);
    expect(isHiddenFromNormalCatalog(unknown), isFalse);
  });
}
