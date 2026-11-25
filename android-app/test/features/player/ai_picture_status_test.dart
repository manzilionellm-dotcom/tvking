import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';

Map<String, Object?> _processedFrame({double p95 = 5, int score = 400}) =>
    <String, Object?>{
      'sessionId': 4,
      'active': true,
      'reason': null,
      'scale': 2,
      'sourceWidth': 640,
      'sourceHeight': 360,
      'outputWidth': 1280,
      'outputHeight': 720,
      'p95Ms': p95,
      'score': score,
      'modelSha256': List<String>.filled(64, 'a').join(),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  NativeVideoController open() {
    final controller = NativeVideoController();
    addTearDown(controller.dispose);
    controller.setUrl('https://fixture.invalid/picture.ts');
    controller.applyBackendEvent('ack', 1);
    return controller;
  }

  test('seule la vraie activation ×2 du moteur est acceptée', () {
    final active = NativeAiPictureStatus.read(_processedFrame());
    expect(active?.active, isTrue);
    expect(active?.p95Ms, 5);
    expect(active?.score, 400);
    for (final incomplete in <Object?>[
      null,
      <String, Object>{'model': 'ArtCNN_C4F16', 'score': 1000, 'p95Ms': 1},
      <String, Object>{'active': false},
      <String, Object?>{..._processedFrame(), 'active': 'true'},
      <String, Object?>{..._processedFrame(), 'scale': 1},
      <String, Object?>{..._processedFrame(), 'outputWidth': 640},
      <String, Object?>{..._processedFrame(), 'sourceHeight': 0},
      <String, Object?>{..._processedFrame(), 'reason': 'TOO_SLOW'},
    ]) {
      expect(NativeAiPictureStatus.read(incomplete), isNull);
    }
    final refused = NativeAiPictureStatus.read(<String, Object>{
      'active': false, 'reason': 'TOO_SLOW', 'score': 1000,
    });
    expect(refused?.active, isFalse);
    expect(refused?.fallback, NativeAiFallback.fluidity);
  });

  test('p95 et score restent diagnostics sans provoquer des rebuilds par image', () {
    final controller = open();
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.applyBackendEvent('aiPicture', _processedFrame());
    expect(controller.videoQuality.aiPicture?.active, isTrue);
    expect(notifications, 1);
    controller.applyBackendEvent('aiPicture', _processedFrame(p95: 6, score: 350));
    expect(controller.videoQuality.aiPicture?.p95Ms, 6);
    expect(controller.videoQuality.aiPicture?.score, 350);
    expect(notifications, 1);
    // Les dimensions du shader ne remplacent pas les callbacks de sortie.
    expect(controller.videoQuality.hasOutputSize, isFalse);
    expect(controller.videoQuality.sourceWidth, 0);
    controller.applyBackendEvent('aiPicture', <String, Object>{
      'active': false, 'reason': 'MARGIN_LOST',
    });
    expect(notifications, 2);
    expect(controller.videoQuality.aiPicture?.active, isFalse);
  });

  test('erreur, image tenue, reprise et fin effacent la preuve IA', () {
    for (final event in <(String, Object?)>[
      ('error', 'fixture'),
      ('holdFrame', true),
      ('reopen', null),
      ('reconnecting', true),
      ('engineExhausted', true),
      ('ended', null),
      ('videoQualityReset', null),
    ]) {
      final controller = open();
      controller.applyBackendEvent('aiPicture', _processedFrame());
      expect(controller.videoQuality.aiPicture?.active, isTrue);
      controller.applyBackendEvent(event.$1, event.$2);
      expect(controller.videoQuality.aiPicture, isNull, reason: event.$1);
      if (event.$1 == 'error' || event.$1 == 'holdFrame') {
        controller.applyBackendEvent('aiPicture', _processedFrame());
        expect(controller.videoQuality.aiPicture, isNull,
            reason: 'callback tardif pendant ${event.$1}');
      }
    }
  });

  test('un statut tardif attend la fin de la reconnexion sans image tenue', () {
    final controller = open();
    controller.applyBackendEvent('aiPicture', _processedFrame());
    expect(controller.videoQuality.aiPicture?.active, isTrue);

    // Une panne avant la première copie PixelCopy n'a pas de holdFrame.
    // Le dernier statut du GPU peut encore arriver pendant le délai réseau.
    controller.applyBackendEvent('holdFrame', false);
    controller.applyBackendEvent('buffering', true);
    controller.applyBackendEvent('reconnecting', true);
    controller.applyBackendEvent('aiPicture', _processedFrame());
    expect(controller.nativeRetrying, isTrue);
    expect(controller.videoQuality.aiPicture, isNull);

    // La preuve portée par une nouvelle image peut revenir après la reprise.
    controller.applyBackendEvent('firstFrame', null);
    expect(controller.nativeRetrying, isFalse);
    controller.applyBackendEvent('aiPicture', _processedFrame());
    expect(controller.videoQuality.aiPicture?.active, isTrue);
  });

  test('zap, format changé, Cast et autre lecteur invalident l’ancien état', () async {
    final controller = open();
    controller.applyBackendEvent('aiPicture', _processedFrame());
    controller.setUrl('https://fixture.invalid/next.ts');
    controller.applyBackendEvent('aiPicture', _processedFrame());
    expect(controller.videoQuality.aiPicture, isNull);
    controller.applyBackendEvent('ack', 2);
    controller.applyBackendEvent('aiPicture', _processedFrame());
    expect(controller.videoQuality.aiPicture?.active, isTrue);
    controller.applyBackendEvent('videoSource', <String, int>{
      'width': 1280, 'height': 720,
    });
    expect(controller.videoQuality.aiPicture, isNull);
    controller.applyBackendEvent('aiPicture', _processedFrame());
    await controller.suspendForCast();
    controller.applyBackendEvent('aiPicture', _processedFrame());
    expect(controller.videoQuality.aiPicture, isNull);
    await controller.resumeAfterCast();
    controller.applyBackendEvent('aiPicture', _processedFrame());
    expect(controller.videoQuality.aiPicture?.active, isTrue);
    final other = open();
    expect(controller.videoQuality.aiPicture, isNull);
    controller.applyBackendEvent('aiPicture', _processedFrame());
    expect(controller.videoQuality.aiPicture, isNull);
    expect(other.videoQuality.aiPicture, isNull);
  });
}
