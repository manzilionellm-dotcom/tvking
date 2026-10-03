// =========================================================
//  mpv_audio_output_test.dart — l'essai de sortie reste coupé
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/domain/mpv_audio_output.dart';

void main() {
  test('coupé : on ne donne aucune valeur à ao', () {
    expect(MpvAudioOutput.propertyValue(null), isNull);
    expect(MpvAudioOutput.propertyValue(''), isNull);
    expect(MpvAudioOutput.propertyValue('  '), isNull);
    expect(MpvAudioOutput.propertyValue('off'), isNull);
    expect(MpvAudioOutput.propertyValue('Coupé'), isNull);
    expect(MpvAudioOutput.propertyValue('défaut'), isNull);
  });

  test('une valeur inconnue ou ao=null ne passe pas', () {
    expect(MpvAudioOutput.propertyValue('null'), isNull);
    expect(MpvAudioOutput.propertyValue('ao=null'), isNull);
    expect(MpvAudioOutput.propertyValue('pulse'), isNull);
    expect(MpvAudioOutput.propertyValue('audiotrack,opensles'), isNull);
    expect(MpvAudioOutput.propertyValue('opensles;af=lowpass'), isNull);
  });

  test('les trois essais autorisés, quelle que soit la casse', () {
    expect(MpvAudioOutput.propertyValue('opensles'), 'opensles');
    expect(MpvAudioOutput.propertyValue('AudioTrack'), 'audiotrack');
    expect(MpvAudioOutput.propertyValue(' AAUDIO '), 'aaudio');
  });

  test('une propriété qui contient une adresse est masquée', () {
    const String secret =
        'http://user:s3cret@exemple.test/live/a.ts password=abc';
    final String clean = MpvAudioOutput.redact(secret);
    expect(clean.contains('http'), isFalse);
    expect(clean.contains('s3cret'), isFalse);
    expect(clean, '[masqué]');
    expect(MpvAudioOutput.redact('48000 Hz stereo 2ch floatp'),
        '48000 Hz stereo 2ch floatp');
  });
}
