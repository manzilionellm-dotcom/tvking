import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/family/domain/family_profile.dart';

void main() {
  test('un stockage cassé laisse seulement Maison', () {
    expect(decodeProfiles(null).single.isHome, isTrue);
    expect(decodeProfiles('{').single.isHome, isTrue);
    expect(decodeProfiles('[]').single.isHome, isTrue);
  });

  test('un profil enfant survit à l\'aller-retour, Maison reste en tête', () {
    final String raw = encodeProfiles(const <FamilyProfile>[
      kHomeProfile,
      FamilyProfile(id: 'p1', name: 'Lina', child: true),
    ]);
    final List<FamilyProfile> back = decodeProfiles(raw);
    expect(back.first.isHome, isTrue);
    expect(back[1].name, 'Lina');
    expect(back[1].child, isTrue);
    expect(back.length, 2);
  });

  test('on ne dépasse pas six profils et on ignore un doublon', () {
    final List<Map<String, Object>> many = <Map<String, Object>>[
      for (int i = 0; i < 10; i++)
        <String, Object>{'id': 'p$i', 'name': 'N$i', 'child': false},
      <String, Object>{'id': 'p0', 'name': 'doublon', 'child': true},
    ];
    final List<FamilyProfile> back = decodeProfiles(encodeProfiles(<FamilyProfile>[
      kHomeProfile,
      for (final Map<String, Object> item in many)
        FamilyProfile(
          id: item['id']! as String,
          name: item['name']! as String,
          child: item['child']! as bool,
        ),
    ]));
    expect(back.length, 6);
    expect(back.where((FamilyProfile p) => p.id == 'p0').length, 1);
  });
}
