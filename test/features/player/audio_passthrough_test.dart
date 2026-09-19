// =========================================================
//  audio_passthrough_test.dart — la consigne `audio-spdif` de mpv
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (19/09/2026) : « implémente le passthrough
//  Dolby comme sur la box, pour que le mpv ne dépende plus du système. »
//
//  Ce que ces tests verrouillent :
//    • l'ordre des formats est FIXE (celui que mpv attend), quel que
//      soit l'ordre rendu par Android ;
//    • un nom inconnu de mpv n'y entre jamais (une consigne illisible
//      couperait le passthrough entier) ;
//    • rien d'accepté → chaîne vide, qui EFFACE une consigne précédente.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/audio_passthrough.dart';

void main() {
  test('ordre fixe, celui de mpv, quel que soit l\'ordre natif', () {
    expect(
      AudioPassthrough.spdifPour(<String>['dts', 'eac3', 'ac3']),
      'ac3,eac3,dts',
    );
  });

  test('un nom inconnu de mpv est écarté, les autres passent', () {
    expect(
      AudioPassthrough.spdifPour(<String>['eac3', 'ENCODING_42', 'truehd']),
      'eac3,truehd',
    );
  });

  test('doublons et espaces : une seule fois, propre', () {
    expect(
      AudioPassthrough.spdifPour(<String>[' ac3', 'ac3 ', 'dts-hd']),
      'ac3,dts-hd',
    );
  });

  test('rien d\'accepté → chaîne vide (mpv décode tout)', () {
    expect(AudioPassthrough.spdifPour(const <String>[]), '');
    expect(AudioPassthrough.spdifPour(<String>['pcm']), '');
  });

  test('la liste connue est exactement celle de mpv', () {
    expect(AudioPassthrough.formatsConnus,
        <String>['ac3', 'eac3', 'dts', 'dts-hd', 'truehd']);
  });
}
