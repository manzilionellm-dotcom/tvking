import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('format déclaré et taille de sortie ne sont jamais confondus', () {
    final controller = NativeVideoController();
    addTearDown(controller.dispose);
    controller.setUrl('https://fixture.invalid/claimed-4k-60fps.ts');
    controller.applyBackendEvent('ack', 1);
    controller.applyBackendEvent('videoSource', <String, Object>{
      'width': 3840,
      'height': 2160,
      'mimeType': 'video/hevc',
      'frameRate': 60,
    });
    expect(controller.videoQuality.hasOutputSize, isFalse);
    expect(controller.videoWidth, 0);
    expect(controller.videoQuality.sourceWidth, 3840);
    expect(controller.videoQuality.sourceFrameRate, 60);
    expect(controller.videoQuality.cadence, isNull);
    expect(controller.videoQuality.sourceDynamicRange, isNull);

    controller.applyBackendEvent('videoSize', <String, Object>{
      'width': 1280,
      'height': 720,
    });
    controller.applyBackendEvent('videoCadence', <String, Object>{
      'renderedFrames': 48,
      'droppedFrames': 2,
      'windowMs': 2000,
    });
    expect(controller.videoWidth, 1280);
    expect(controller.videoHeight, 720);
    expect(controller.videoQuality.outputWidth, 1280);
    expect(controller.videoQuality.sourceWidth, 3840);
    expect(controller.videoQuality.cadence?.framesPerSecond, 24);
    expect(controller.videoQuality.cadence?.droppedFrames, 2);
  });

  test('zap et reconstruction effacent les mesures de la lecture précédente', () {
    final controller = NativeVideoController();
    addTearDown(controller.dispose);
    controller.setUrl('https://fixture.invalid/first.ts');
    controller.applyBackendEvent('ack', 1);
    controller.applyBackendEvent('videoSize', <String, int>{'width': 1280, 'height': 720});
    controller.setUrl('https://fixture.invalid/next.ts');
    controller.applyBackendEvent('videoSize', <String, int>{'width': 3840, 'height': 2160});
    expect(controller.videoQuality.hasOutputSize, isFalse);
    controller.applyBackendEvent('ack', 2);
    controller.applyBackendEvent('videoSize', <String, int>{'width': 1920, 'height': 1080});
    expect(controller.videoQuality.outputWidth, 1920);
    controller.applyBackendEvent('videoQualityReset', null);
    expect(controller.videoQuality.hasOutputSize, isFalse);
    expect(controller.videoWidth, 0);
  });

  test('pause, tampon et erreur invalident la dernière cadence', () {
    final controller = NativeVideoController();
    addTearDown(controller.dispose);
    for (final event in <(String, Object)>[
      ('playing', false), ('buffering', true), ('error', 'fixture'),
    ]) {
      controller.applyBackendEvent('videoCadence', <String, int>{
        'renderedFrames': 50, 'droppedFrames': 0, 'windowMs': 2000,
      });
      expect(controller.videoQuality.cadence, isNotNull);
      controller.applyBackendEvent(event.$1, event.$2);
      expect(controller.videoQuality.cadence, isNull);
    }
  });

  test('valeurs absentes ou invalides ne deviennent ni HDR, ni SDR, ni FPS', () {
    final quality = const NativeVideoQuality()
        .withSourceFormat(<String, Object>{
          'frameRate': double.nan,
          'dynamicRange': 'HDR inferred from channel name',
          'mimeType': 'HEVC from playlist',
        })
        .withVideoSize(<String, Object>{'width': -1, 'height': double.infinity});
    expect(quality.hasOutputSize, isFalse);
    expect(quality.sourceFrameRate, isNull);
    expect(quality.sourceDynamicRange, isNull);
    expect(quality.sourceMimeType, isNull);
    expect(quality.cadence, isNull);
    for (final raw in <Object?>[
      null,
      <String, int>{'frameRate': 60},
      <String, int>{'renderedFrames': 60, 'droppedFrames': 0, 'windowMs': 0},
      <String, int>{'renderedFrames': -1, 'droppedFrames': 0, 'windowMs': 2000},
      <String, int>{'renderedFrames': 60, 'droppedFrames': -1, 'windowMs': 2000},
      <String, int>{'renderedFrames': 60, 'droppedFrames': 0, 'windowMs': 6000},
    ]) {
      expect(quality.withCadence(raw).cadence, isNull);
    }
  });
}
