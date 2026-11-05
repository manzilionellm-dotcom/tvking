import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:tv_king/features/player/domain/reconnect_plan.dart';

void main() {
  test('une reconnexion à zéro ne renouvelle pas le budget de panne', () {
    NativeVideoController.backendFactory = null;
    final NativeVideoController c = NativeVideoController();
    addTearDown(c.dispose);
    Duration previous = Duration.zero;
    int recoveries = 0;
    c.addListener(() {
      if (ReconnectPlan.madePlaybackProgress(
        previous: previous,
        current: c.position,
        playing: c.isPlaying,
        buffering: c.isBuffering,
        hasError: c.hasError,
      )) {
        recoveries++;
      }
      previous = c.position;
    });

    c.setUrl('https://stream.example.invalid/live.ts');
    c.applyBackendEvent('ack', 1);
    c.applyBackendEvent('firstFrame', null);
    c.applyBackendEvent('playing', true);
    c.applyBackendEvent('position', 12000);
    expect(recoveries, 1);

    c.applyBackendEvent('error', 'network');
    c.setUrl('https://stream.example.invalid/live.ts');
    expect(c.position, Duration.zero);
    expect(recoveries, 1, reason: 'setUrl ne signifie pas lecture revenue');
    c.applyBackendEvent('ack', 2);
    c.applyBackendEvent('position', 5000);
    expect(recoveries, 1, reason: 'le chargement ne renouvelle pas le budget');
    c.applyBackendEvent('firstFrame', null);
    c.applyBackendEvent('playing', true);
    c.applyBackendEvent('position', 5500);
    expect(recoveries, 2, reason: 'la vraie reprise reste reconnue');
    c.applyBackendEvent('position', 1000);
    expect(recoveries, 2, reason: 'un recul de position est une discontinuité');
    c.applyBackendEvent('buffering', true);
    c.applyBackendEvent('position', 1500);
    expect(recoveries, 2, reason: 'aucune preuve de reprise pendant le buffer');
  });
}
