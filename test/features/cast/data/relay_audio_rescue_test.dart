// =========================================================
//  relay_audio_rescue_test.dart — Sauvetage audio non transmuxable
// =========================================================
//  Terrain 2026-07-16 (boîte noire client, SHIELD) : les sessions
//  relais avec `audio: aac` jouent, celles avec `audio: ac3` meurent
//  (« Cette TV n'a pas accepté ce flux ») — le Default Media Receiver
//  ne sait ré-emballer que l'AAC/MP3. Le transport Google retente
//  alors UNE fois en TV-directe (les box ExoPlayer décodent l'AC-3
//  nativement).
//
//  Ces tests verrouillent les briques du sauvetage :
//    1. la liste des codecs non transmuxables (contrat partagé
//       serveur local ⇄ transport) ;
//    2. hlsAudioCodecFor : null pour une session inconnue ou un codec
//       pas encore vu (le sauvetage ne doit JAMAIS se déclencher sans
//       preuve du codec).
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/local_cast_server.dart';

void main() {
  test('les codecs à risque couvrent le terrain (ac3 confirmé client)', () {
    expect(
      LocalCastServer.kUntransmuxableAudio,
      containsAll(<String>['mp2', 'ac3', 'eac3', 'dts', 'aac-latm']),
    );
    expect(LocalCastServer.kUntransmuxableAudio, isNot(contains('aac')),
        reason: 'l\'AAC est transmuxable — jamais de faux sauvetage');
  });

  test('hlsAudioCodecFor : null pour une URL de relais inconnue', () {
    expect(
      LocalCastServer.instance
          .hlsAudioCodecFor('http://192.168.1.2:1234/hls/INCONNU.m3u8'),
      isNull,
      reason: 'sans session (ou codec unknown), le sauvetage ne doit '
          'pas se déclencher',
    );
  });
}
