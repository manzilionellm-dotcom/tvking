import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/domain/decoder_fallback.dart';
import 'package:tv_king/features/player/domain/image_engine.dart';
import 'package:tv_king/features/player/domain/playback_error_taxonomy.dart';
import 'package:tv_king/features/player/domain/playback_lease.dart';
import 'package:tv_king/features/player/domain/reconnect_plan.dart';

void main() {
  test('les délais silencieux sont 1, 2, 4 puis 8 secondes', () {
    expect(ReconnectPlan.delayMs(0), 0);
    expect(ReconnectPlan.delayMs(1), 1000);
    expect(ReconnectPlan.delayMs(2), 2000);
    expect(ReconnectPlan.delayMs(3), 4000);
    expect(ReconnectPlan.delayMs(4), 8000);
    expect(ReconnectPlan.delayMs(9), 8000);
  });

  test('une attente déjà posée n\'en arme pas une seconde', () {
    final ReconnectGate gate = ReconnectGate();
    expect(gate.arm(maxAttempts: 8), 1000);
    expect(gate.arm(maxAttempts: 8), isNull);
    expect(gate.fire(), isTrue);
    expect(gate.fire(), isFalse);
    expect(gate.arm(maxAttempts: 8), 2000);
  });

  test('au-delà de 8 essais silencieux, on abandonne', () {
    final ReconnectGate gate = ReconnectGate();
    for (int i = 0; i < 8; i++) {
      expect(gate.arm(maxAttempts: 8), isNotNull);
      expect(gate.fire(), isTrue);
    }
    expect(gate.arm(maxAttempts: 8), isNull);
  });

  test('même adresse et image déjà vue : pas de panneau opaque', () {
    expect(
      ReconnectPlan.coverWithLoader(hadFrame: true, sameUrl: true),
      isFalse,
    );
    expect(
      ReconnectPlan.coverWithLoader(hadFrame: false, sameUrl: true),
      isTrue,
    );
    expect(
      ReconnectPlan.coverWithLoader(hadFrame: true, sameUrl: false),
      isTrue,
    );
  });

  test('le bouton moteur saute FFmpeg quand il n\'est pas dans le binaire', () {
    expect(
      EngineStep.next(ImageEngine.hardware, ffmpegVideo: false).engine,
      ImageEngine.software,
    );
    final EngineStep back =
        EngineStep.next(ImageEngine.software, ffmpegVideo: false);
    expect(back.engine, ImageEngine.hardware);
    expect(back.ffmpegMissing, isTrue);
    expect(hwdecFor(ImageEngine.hardware), 'auto-safe');
    expect(hwdecFor(ImageEngine.software), 'no');
  });

  test('un trou de réseau ne change pas de moteur', () {
    final DecoderDecision d = DecoderFallback.next(
      current: ImageEngine.hardware,
      signal: PictureSignal.network,
      ffmpegVideoReady: false,
      tried: <ImageEngine>{},
    );
    expect(d.reopen, isFalse);
    expect(d.engine, ImageEngine.hardware);
  });

  test('un échec matériel ouvre le logiciel, une seule fois', () {
    final DecoderDecision d = DecoderFallback.next(
      current: ImageEngine.hardware,
      signal: DecoderFallback.fromCategory(PlaybackErrorCategory.decoder),
      ffmpegVideoReady: false,
      tried: <ImageEngine>{},
    );
    expect(d.reopen, isTrue);
    expect(d.engine, ImageEngine.software);
    final DecoderDecision again = DecoderFallback.next(
      current: ImageEngine.software,
      signal: PictureSignal.blackOrFrozen,
      ffmpegVideoReady: false,
      tried: <ImageEngine>{ImageEngine.hardware},
    );
    expect(again.giveUp, isTrue);
    expect(again.reopen, isFalse);
  });

  test('image noire ou figée seulement après 8 secondes de lecture prête', () {
    expect(
      PictureHealth.black(
        decoderReady: true,
        framesRendered: 0,
        playbackReady: true,
        buffering: false,
        elapsedMs: 7999,
      ),
      isFalse,
    );
    expect(
      PictureHealth.black(
        decoderReady: true,
        framesRendered: 0,
        playbackReady: true,
        buffering: false,
        elapsedMs: 8000,
      ),
      isTrue,
    );
    expect(
      PictureHealth.frozen(
        framesRendered: 3,
        playing: true,
        buffering: false,
        msSinceLastFrame: 8000,
      ),
      isTrue,
    );
    expect(
      PictureHealth.frozen(
        framesRendered: 3,
        playing: true,
        buffering: true,
        msSinceLastFrame: 8000,
      ),
      isFalse,
    );
  });

  test('vingt prises de son : un seul propriétaire, les autres se taisent', () {
    final ExclusiveAudio audio = ExclusiveAudio();
    final List<int> silenced = <int>[];
    final List<int> ids = <int>[];
    for (int i = 0; i < 20; i++) {
      final int n = i;
      ids.add(audio.register(() => silenced.add(n)));
    }
    audio.claim(ids.last);
    expect(audio.owner, ids.last);
    expect(silenced, hasLength(19));
    expect(silenced, isNot(contains(19)));
    final PlaybackSession session = PlaybackSession();
    final int first = session.open();
    final int second = session.open();
    expect(session.isCurrent(first), isFalse);
    expect(session.isCurrent(second), isTrue);
  });
}
