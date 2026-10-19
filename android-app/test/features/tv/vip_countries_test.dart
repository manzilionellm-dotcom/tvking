import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/tv/data/vip_countries_repository.dart';
import 'package:tv_king/features/tv/domain/vip_countries.dart';
import 'package:tv_king/features/tv/domain/vip_channel_groups.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('dix pays maximum, doublons supprimés sans perdre l’ordre choisi', () {
    expect(VipCountries.normalize([' RS ', 'fr', 'rs', '', '???']), [
      'rs',
      'fr',
    ]);
    expect(
      VipCountries.normalize([
        'fr',
        'rs',
        'se',
        'uk',
        'de',
        'it',
        'es',
        'pt',
        'be',
        'ch',
        'us',
      ]),
      hasLength(10),
    );
    expect(VipCountries.move(['rs', 'fr', 'se'], 2, 0), ['se', 'rs', 'fr']);
    expect(VipCountries.move(['rs', 'fr'], 0, -1), ['rs', 'fr']);
  });

  test(
    'ordre conservé après redémarrage, profils isolés et vidage explicite',
    () async {
      SharedPreferences.setMockInitialValues({});
      final original = ActiveProfile.instance.id;
      addTearDown(() => ActiveProfile.instance.set(original));
      ActiveProfile.instance.set('vip-a');
      final first = VipCountriesRepository();
      final restarted = VipCountriesRepository();
      addTearDown(first.dispose);
      addTearDown(restarted.dispose);
      await first.save(['rs', 'fr'], profileId: 'vip-a');
      await restarted.load();
      expect(restarted.current, ['rs', 'fr']);
      ActiveProfile.instance.set('vip-b');
      await restarted.load();
      expect(restarted.current, isEmpty);
      await restarted.save(['se'], profileId: 'vip-b');
      // Un ancien écran ne peut pas remplacer la sélection du profil courant.
      await first.save(['de'], profileId: 'vip-a');
      expect(restarted.current, ['se']);
      ActiveProfile.instance.set('vip-a');
      await restarted.load();
      expect(restarted.current, ['de']);
      await restarted.save([], profileId: 'vip-a');
      await first.load();
      expect(first.current, isEmpty);
    },
  );

  test(
    'Serbie reconnue par ses variantes ; la catégorie prime sur le titre',
    () {
      for (final label in [
        'RS',
        'SRB',
        'Serbia',
        'Serbie',
        'Srbija',
        'Србија',
      ]) {
        expect(ChannelClassifier.detectCountryKey('France 24', label), 'rs');
      }
      expect(
        ChannelClassifier.detectCountryKey('TV', 'FR | Généralistes'),
        'fr',
      );
    },
  );

  test(
    'groupes sans calcul sur cache froid, ordre et chaînes inconnues conservés',
    () async {
      Channel c(String id, String category, {bool live = true}) => Channel(
        id: id,
        name: 'TV',
        category: category,
        streamUrl: 'https://example.invalid/$id.ts',
        isLive: live,
      );
      final channels = [
        c('r1', 'SRB'),
        c('f1', 'FR'),
        c('r2', 'Serbia'),
        c('other', 'Divers'),
        c('film', 'FR', live: false),
      ];
      expect(vipChannelGroups(channels), isEmpty);
      expect(ChannelPrecompute.cachedCountry(channels.first).known, isFalse);
      await ChannelPrecompute.run(channels);
      final groups = vipChannelGroups(channels);
      expect(groups['rs']!.map((c) => c.id), ['r1', 'r2']);
      expect(groups['fr']!.map((c) => c.id), ['f1']);
      expect(channels.map((c) => c.id), ['r1', 'f1', 'r2', 'other', 'film']);
    },
  );
}
