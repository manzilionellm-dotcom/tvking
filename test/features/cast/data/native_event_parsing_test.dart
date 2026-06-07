// =========================================================
//  native_event_parsing_test.dart — Phase 1+/G2 sync bidirectionnel
// =========================================================
//  Verrouille le parsing des evenements pousses par
//  RemoteMediaClient.Callback / SessionManagerListener (cote
//  Kotlin) vers Dart. Si la regle change cote natif sans MAJ Dart
//  (ou inversement), ces tests sautent et le rappellent.
//
//  Tests purs : on instancie directement les classes immuables —
//  pas besoin du binding Flutter ni de mock du MethodChannel.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/google_cast_api.dart';

void main() {
  group('CastNativeMediaState shape', () {
    test('playing : isPlaying=true, autres false', () {
      const CastNativeMediaState s = CastNativeMediaState(
        playerState: CastNativePlayerState.playing,
        isPlaying: true,
        isPaused: false,
        isBuffering: false,
      );
      expect(s.playerState, CastNativePlayerState.playing);
      expect(s.isPlaying, isTrue);
      expect(s.isPaused, isFalse);
    });

    test('paused : isPaused=true', () {
      const CastNativeMediaState s = CastNativeMediaState(
        playerState: CastNativePlayerState.paused,
        isPlaying: false,
        isPaused: true,
        isBuffering: false,
      );
      expect(s.playerState, CastNativePlayerState.paused);
      expect(s.isPaused, isTrue);
    });

    test('idleReason : defaut = none', () {
      const CastNativeMediaState s = CastNativeMediaState(
        playerState: CastNativePlayerState.idle,
        isPlaying: false,
        isPaused: false,
        isBuffering: false,
      );
      expect(s.idleReason, 'none');
    });

    test('idleReason : error = rejet du recepteur (codec non supporte)', () {
      // error != finished : c'est ce qui permet a l'UI de distinguer
      // "la TV a refuse le flux" d'une fin de lecture normale.
      const CastNativeMediaState s = CastNativeMediaState(
        playerState: CastNativePlayerState.idle,
        isPlaying: false,
        isPaused: false,
        isBuffering: false,
        idleReason: 'error',
      );
      expect(s.idleReason, 'error');
    });
  });

  group('CastNativePlayerState couvre les 6 etats canoniques', () {
    test('idle / loading / playing / paused / buffering / unknown', () {
      // Si on ajoute / renomme une valeur cote Dart sans MAJ Kotlin
      // (ou inversement), les chaines "playing" / "paused" envoyees
      // depuis Kotlin tomberont sur `unknown` -> aucune transition
      // d'etat dans CastManager -> regression silencieuse. Le test
      // fige la liste autorisee.
      expect(CastNativePlayerState.values.length, 6);
      final Set<String> names = CastNativePlayerState.values
          .map((CastNativePlayerState e) => e.name)
          .toSet();
      expect(names, <String>{
        'idle',
        'loading',
        'playing',
        'paused',
        'buffering',
        'unknown',
      });
    });
  });

  group('CastNativeSessionEvent shape', () {
    test('errorCode defaut = 0', () {
      const CastNativeSessionEvent e = CastNativeSessionEvent('started');
      expect(e.kind, 'started');
      expect(e.errorCode, 0);
    });

    test('errorCode explicite', () {
      const CastNativeSessionEvent e = CastNativeSessionEvent('start_failed', 7);
      expect(e.errorCode, 7);
    });
  });
}
