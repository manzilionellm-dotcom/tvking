import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('la PiP reçoit les dimensions du flux courant après son accusé', () {
    final controller = NativeVideoController();
    addTearDown(controller.dispose);
    controller.setUrl('https://fixture.invalid/video.ts');
    // Une réponse tardive de la chaîne précédente ne doit pas changer le
    // ratio de la fenêtre pendant le zap.
    controller.applyBackendEvent('videoFormat', <String, Object>{
      'width': 3840,
      'height': 2160,
    });
    expect(controller.videoWidth, 0);
    expect(controller.videoHeight, 0);
    controller.applyBackendEvent('ack', 1);
    controller.applyBackendEvent('videoFormat', <String, Object>{
      'width': 720,
      'height': 576,
    });
    expect(controller.videoWidth, 720);
    expect(controller.videoHeight, 576);

    controller.setUrl('https://fixture.invalid/other.ts');
    expect(controller.videoWidth, 0);
    expect(controller.videoHeight, 0);
    controller.applyBackendEvent('ack', 2);
    controller.applyBackendEvent('videoFormat', <String, Object>{
      'width': -1,
      'height': double.infinity,
    });
    expect(controller.videoWidth, 0);
    expect(controller.videoHeight, 0);
  });
}
