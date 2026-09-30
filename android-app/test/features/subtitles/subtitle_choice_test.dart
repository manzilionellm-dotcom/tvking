import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/subtitles/domain/subtitle_choice.dart';

void main() {
  const SubtitleCue fr = SubtitleCue(group: 1, index: 0, language: 'fre');
  const SubtitleCue fr2 = SubtitleCue(group: 1, index: 1, language: 'fra');
  const SubtitleCue en = SubtitleCue(group: 1, index: 2, language: 'eng');
  const SubtitleCue und = SubtitleCue(group: 1, index: 3, language: 'und');
  const SubtitleCue blank = SubtitleCue(group: 1, index: 4);
  const List<SubtitleCue> all = <SubtitleCue>[fr, fr2, en, und, blank];

  test('fre et fra sont du français, und ne l\'est pas', () {
    expect(subtitleLanguage('fre'), 'fr');
    expect(subtitleLanguage('fra'), 'fr');
    expect(subtitleLanguage('und'), isNull);
    expect(subtitleLanguage(null), isNull);
    expect(subtitleLanguage(''), isNull);
    expect(tracksInLanguage(all, 'fr').map((SubtitleCue t) => t.index), <int>[0, 1]);
  });

  test('on n\'allume rien si c\'est coupé ou si la personne a dit non', () {
    expect(
      autoSubtitle(tracks: all, userLanguage: 'fr', textPref: null, enabled: false),
      isNull,
    );
    expect(
      autoSubtitle(tracks: all, userLanguage: 'fr', textPref: 'off', enabled: true),
      isNull,
    );
  });

  test('sans choix, la langue de l\'app ; un choix précis ne bascule pas', () {
    expect(
      autoSubtitle(tracks: all, userLanguage: 'fr', textPref: null, enabled: true)?.language,
      'fre',
    );
    expect(
      autoSubtitle(tracks: all, userLanguage: 'fr', textPref: 'en', enabled: true)?.language,
      'eng',
    );
    expect(
      autoSubtitle(
        tracks: <SubtitleCue>[fr, und],
        userLanguage: 'fr',
        textPref: 'de',
        enabled: true,
      ),
      isNull,
    );
  });

  test('la touche fait le tour : éteint, français, éteint', () {
    expect(nextSubtitleStep(-1, 2), 0);
    expect(nextSubtitleStep(0, 2), 1);
    expect(nextSubtitleStep(1, 2), -1);
    expect(nextSubtitleStep(-1, 0), -1);
  });
}
