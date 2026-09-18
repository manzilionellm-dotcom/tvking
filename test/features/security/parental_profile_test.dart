// =========================================================
//  parental_profile_test.dart — « appareil OU profil »
// =========================================================
//  Le mode enfant EFFECTIF est le OU de deux choses : l'interrupteur de
//  l'appareil, et le profil actif. Le OU (et non le ET) est le cœur du
//  sujet : sur un contrôle parental, la position la plus SÛRE des deux
//  doit gagner. Se tromper dans ce sens ferme trop de contenu à un
//  adulte ; l'inverse en ouvrirait trop à un enfant.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/profiles/profiles_repository.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ProfilesRepository.instance.debugReset();
    await ParentalControls.instance.load();
    await ParentalControls.instance.setKidsMode(false);
  });

  Future<void> pousserProfils() => ProfilesRepository.instance.applyRemote(
        <TvProfile>[
          const TvProfile(id: 'papa', name: 'Papa', emoji: '👨'),
          const TvProfile(
              id: 'enfant1', name: 'Enfant 1', emoji: '🧒', kids: true),
        ],
      );

  test('un profil ENFANT bride, meme interrupteur appareil eteint', () async {
    await pousserProfils();
    expect(ParentalControls.instance.kidsMode.value, isFalse);

    await ProfilesRepository.instance.setActive('enfant1');
    expect(ParentalControls.instance.kidsMode.value, isTrue);
    // …sans que l'interrupteur de l'appareil ait bougé : sinon l'écran de
    // réglages afficherait « activé » et le parent croirait l'avoir mis.
    expect(ParentalControls.instance.deviceKidsMode, isFalse);
  });

  test('revenir sur un profil ADULTE leve le bridage', () async {
    await pousserProfils();
    await ProfilesRepository.instance.setActive('enfant1');
    expect(ParentalControls.instance.kidsMode.value, isTrue);
    await ProfilesRepository.instance.setActive('papa');
    expect(ParentalControls.instance.kidsMode.value, isFalse);
  });

  test('l interrupteur de l appareil bride TOUS les profils', () async {
    await pousserProfils();
    await ProfilesRepository.instance.setActive('papa');
    await ParentalControls.instance.setKidsMode(true);
    expect(ParentalControls.instance.kidsMode.value, isTrue);
  });

  test('eteindre l interrupteur ne debride PAS un profil enfant', () async {
    await pousserProfils();
    await ProfilesRepository.instance.setActive('enfant1');
    await ParentalControls.instance.setKidsMode(false);
    // C'est le geste d'un enfant qui trouve l'écran de réglages : il peut
    // toucher l'interrupteur de l'appareil, il ne peut pas s'affranchir de
    // la règle que le panel a posée sur SON profil.
    expect(ParentalControls.instance.kidsMode.value, isTrue);
  });

  test('re-marquer un profil « enfant » depuis le panel prend effet seul',
      () async {
    await pousserProfils();
    await ProfilesRepository.instance.setActive('papa');
    expect(ParentalControls.instance.kidsMode.value, isFalse);

    // Le parent coche « enfant » sur le profil papa depuis le panel : la
    // box doit se re-filtrer sans qu'on rouvre le moindre écran.
    await ProfilesRepository.instance.applyRemote(<TvProfile>[
      const TvProfile(id: 'papa', name: 'Papa', emoji: '👨', kids: true),
    ]);
    expect(ParentalControls.instance.kidsMode.value, isTrue);
  });
}
