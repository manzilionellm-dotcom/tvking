// =========================================================
//  audio_attribute_trial_test.dart — bouton d'essai, coupé d'abord
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/domain/audio_attribute_trial.dart';

void main() {
  test('le défaut est coupé et un mot inconnu y revient', () {
    expect(AudioAttributeTrial.parse(null), AudioAttributeTrial.off);
    expect(AudioAttributeTrial.parse(''), AudioAttributeTrial.off);
    expect(AudioAttributeTrial.parse('http://exemple.test'), AudioAttributeTrial.off);
    expect(AudioAttributeTrial.armed(null), isFalse);
    expect(AudioAttributeTrial.label(null), 'Attributs : coupé');
    expect(AudioAttributeTrial.key, 'zuno.audio.profile');
  });

  test('le bouton tourne film, musique, parole, défaut Media3, puis coupé', () {
    expect(AudioAttributeTrial.next(AudioAttributeTrial.off), AudioAttributeTrial.film);
    expect(AudioAttributeTrial.next(AudioAttributeTrial.film), AudioAttributeTrial.music);
    expect(AudioAttributeTrial.next(AudioAttributeTrial.music), AudioAttributeTrial.speech);
    expect(AudioAttributeTrial.next(AudioAttributeTrial.speech), AudioAttributeTrial.media3);
    expect(AudioAttributeTrial.next(AudioAttributeTrial.media3), AudioAttributeTrial.off);
    expect(AudioAttributeTrial.label(AudioAttributeTrial.film), 'Attributs : film');
    expect(AudioAttributeTrial.label(AudioAttributeTrial.music), 'Attributs : musique');
    expect(AudioAttributeTrial.label(AudioAttributeTrial.speech), 'Attributs : parole');
    expect(
      AudioAttributeTrial.label(AudioAttributeTrial.media3),
      'Attributs : défaut Media3',
    );
    expect(AudioAttributeTrial.armed(AudioAttributeTrial.music), isTrue);
    expect(AudioAttributeTrial.label(AudioAttributeTrial.music).contains('http'), isFalse);
  });
}
