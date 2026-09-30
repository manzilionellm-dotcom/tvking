// =========================================================
//  spoken_track_test.dart — voix de la langue, pas le commentaire
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/spoken_track.dart';

SpokenTrack _t({
  required int index,
  String? language,
  String? label,
  bool selected = false,
  int roleFlags = 0,
  int group = 0,
}) {
  return SpokenTrack(
    group: group,
    index: index,
    language: language,
    label: label,
    selected: selected,
    roleFlags: roleFlags,
  );
}

void main() {
  test('fre et fra sont le français, und n\'est pas une langue', () {
    expect(spokenLanguage('fre'), 'fr');
    expect(spokenLanguage('fra'), 'fr');
    expect(spokenLanguage('en-US'), 'en');
    expect(spokenLanguage('und'), isNull);
    expect(spokenLanguage(''), isNull);
  });

  test('la langue de l\'app gagne sur la piste déjà sélectionnée', () {
    final SpokenTrack? pick = chooseSpokenTrack(
      <SpokenTrack>[
        _t(index: 0, language: 'eng', label: 'English', selected: true),
        _t(index: 1, language: 'fre', label: 'VF'),
      ],
      'fr',
    );
    expect(pick?.index, 1);
  });

  test('un commentaire français ne remplace pas la VF', () {
    final SpokenTrack? pick = chooseSpokenTrack(
      <SpokenTrack>[
        _t(index: 0, language: 'fr', label: 'Commentaire', selected: true),
        _t(index: 1, language: 'fr', label: 'VF'),
      ],
      'fr',
    );
    expect(pick?.index, 1);
    expect(isSideTrack(_t(index: 0, label: 'Audio Description')), isTrue);
    expect(isSideTrack(_t(index: 0, label: 'VF')), isFalse);
  });

  test('le drapeau Media3 commentaire compte même sans libellé', () {
    final SpokenTrack? pick = chooseSpokenTrack(
      <SpokenTrack>[
        _t(index: 0, language: 'fr', selected: true, roleFlags: kRoleCommentary),
        _t(index: 1, language: 'fr', roleFlags: 0),
      ],
      'fr',
    );
    expect(pick?.index, 1);
    expect(
      isSideTrack(_t(index: 0, roleFlags: kRoleDescribesVideo)),
      isTrue,
    );
  });

  test('si la piste déjà choisie convient, on ne change rien', () {
    final SpokenTrack? pick = chooseSpokenTrack(
      <SpokenTrack>[
        _t(index: 0, language: 'en', label: 'English'),
        _t(index: 1, language: 'fr', label: 'VF', selected: true),
      ],
      'fr',
    );
    expect(pick, isNull);
  });

  test('sans la langue demandée, on quitte le commentaire', () {
    final SpokenTrack? pick = chooseSpokenTrack(
      <SpokenTrack>[
        _t(index: 0, language: 'en', label: 'Director commentary', selected: true),
        _t(index: 1, language: 'de', label: 'Deutsch'),
      ],
      'fr',
    );
    expect(pick?.index, 1);
  });

  test('que des commentaires : on ne coupe pas le son', () {
    final SpokenTrack? pick = chooseSpokenTrack(
      <SpokenTrack>[
        _t(index: 0, label: 'Commentary', selected: true),
        _t(index: 1, label: 'AD'),
      ],
      'fr',
    );
    expect(pick, isNull);
  });

  test('« Recommended » n\'est pas un commentaire', () {
    expect(isSideTrack(_t(index: 0, label: 'Recommended')), isFalse);
  });
}
