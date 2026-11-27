// =========================================================
//  playback_epoch_test.dart — zap : on ignore l'ancienne image
// =========================================================
//  Pas de flux réel. On simule les événements que le natif enverrait.
//  But : un zap ne doit jamais prendre la « 1re image » de la chaîne
//  précédente (logo qui saute, ou logo qui reste alors que ça joue).
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';

void main() {
  setUp(() {
    NativeVideoController.backendFactory = null;
    NativeVideoController.appInBackground = false;
  });

  tearDown(() => NativeVideoController.appInBackground = false);

  test('Home et retour restent visibles pendant un zap sans ack', () {
    final NativeVideoController c = NativeVideoController();
    c.setUrl('http://a.example.invalid/1.ts');
    c.applyBackendEvent('appBackground', true);
    expect(NativeVideoController.blocksReopenInBackground, isTrue);
    c.setUrl('http://a.example.invalid/2.ts');
    c.applyBackendEvent('ack', 1); // accusé de l'ancienne chaîne
    c.applyBackendEvent('appBackground', false);
    expect(NativeVideoController.blocksReopenInBackground, isFalse);
    c.applyBackendEvent('position', 9000);
    expect(c.position, Duration.zero,
        reason: 'la porte des événements vidéo reste fermée');
    c.dispose();
    c.applyBackendEvent('appBackground', true);
    expect(NativeVideoController.appInBackground, isFalse,
        reason: 'une vue détruite ne change plus le cycle de vie');
  });

  test('avant l\'ack, les événements de l\'ancienne lecture sont ignorés', () {
    final NativeVideoController c = NativeVideoController();
    c.setUrl('http://a.example.invalid/live/u/p/1.ts');
    // Événements encore en route au moment du zap.
    c.applyBackendEvent('playing', true);
    c.applyBackendEvent('firstFrame', null);
    c.applyBackendEvent('position', 4000);
    expect(c.firstFrame, isFalse, reason: 'le logo doit rester tant que la NOUVELLE chaîne n\'a pas accusé');
    expect(c.isPlaying, isFalse);
    expect(c.position, Duration.zero);
    c.dispose();
  });

  test('un ack périmé n\'ouvre pas la porte du zap suivant', () {
    final NativeVideoController c = NativeVideoController();
    c.setUrl('http://a.example.invalid/live/u/p/1.ts');
    c.applyBackendEvent('ack', 1);
    c.applyBackendEvent('playing', true);
    c.applyBackendEvent('firstFrame', null);
    expect(c.firstFrame, isTrue);
    expect(c.isPlaying, isTrue);

    c.setUrl('http://a.example.invalid/live/u/p/2.ts');
    expect(c.firstFrame, isFalse, reason: 'le zap remet le logo');
    expect(c.isPlaying, isFalse,
        reason: 'rien ne joue entre le silence et le « je joue » de la nouvelle chaîne');
    c.applyBackendEvent('ack', 1); // accusé de la chaîne QU'ON VIENT DE QUITTER
    c.applyBackendEvent('firstFrame', null);
    expect(c.firstFrame, isFalse);
    c.applyBackendEvent('ack', 2);
    c.applyBackendEvent('firstFrame', null);
    expect(c.firstFrame, isTrue);
    c.dispose();
  });

  test('lecture qui avance sans événement firstFrame : on retire le logo', () {
    final NativeVideoController c = NativeVideoController();
    c.setUrl('http://a.example.invalid/live/u/p/1.ts');
    c.applyBackendEvent('ack', 1);
    // Certaines box ne rappellent pas firstFrame (même surface réutilisée).
    c.applyBackendEvent('playing', true);
    c.applyBackendEvent('position', 0); // pas encore une image
    expect(c.firstFrame, isFalse);
    c.applyBackendEvent('position', 800);
    expect(c.firstFrame, isTrue, reason: 'une chaîne qui joue ne doit pas rester sous le logo');
    expect(c.isBuffering, isFalse);
    c.dispose();
  });

  test('la preuve de rendu QA exige la vue et la révision de la vraie image', () {
    final c = NativeVideoController();
    c.setUrl('http://a.example.invalid/1.ts');
    c.applyBackendEvent('ack', 1);
    c.applyBackendEvent('playing', true);
    c.applyBackendEvent('position', 700);
    expect(c.firstFrame, isTrue);
    expect(c.qaRenderedFrame, isNull);
    c.applyBackendEvent('firstFrame', null);
    expect(c.qaRenderedFrame, isNull);
    c.applyBackendEvent('firstFrame', {'view': 4, 'epoch': 1, 'timeMs': 3200});
    expect(c.qaRenderedFrame, (view: 4, epoch: 1, timeMs: 3200));
    c.setUrl('http://a.example.invalid/2.ts', keepPicture: true);
    expect(c.qaRenderedFrame, isNull);
    c.applyBackendEvent('ack', 2);
    c.applyBackendEvent('firstFrame', {'view': 4, 'epoch': 1, 'timeMs': 3300});
    expect(c.qaRenderedFrame, isNull);
    c.applyBackendEvent('firstFrame', {'view': 4, 'epoch': 2, 'timeMs': 4000});
    expect(c.qaRenderedFrame, (view: 4, epoch: 2, timeMs: 4000));
    c.applyBackendEvent('reopen', null);
    expect(c.qaRenderedFrame, isNull);
    c.dispose();
  });

  test('un repli décodeur remet le logo sans compter une erreur', () {
    final NativeVideoController c = NativeVideoController();
    c.setUrl('http://a.example.invalid/live/u/p/1.ts');
    c.applyBackendEvent('ack', 1);
    c.applyBackendEvent('firstFrame', null);
    expect(c.firstFrame, isTrue);
    c.applyBackendEvent('reopen', null);
    expect(c.firstFrame, isFalse, reason: 'le carton de chaîne couvre la surface pendant le changement de moteur');
    expect(c.isBuffering, isTrue);
    expect(c.hasError, isFalse);
    expect(c.reopenCount, 1);
    c.dispose();
  });

  test('les infos moteur ne sont pas jetées entre deux zap', () {
    final NativeVideoController c = NativeVideoController();
    c.setUrl('http://a.example.invalid/live/u/p/1.ts');
    c.applyBackendEvent('imageCaps', <String, Object?>{
      'engine': 'hardware',
      'ffmpegVideo': false,
      'contrastHardware': false,
    });
    expect(c.ffmpegVideoReady, isFalse);
    expect(c.contrastHardware, isFalse);
    expect(c.imageEngineWire, 'hardware');
    c.applyBackendEvent('ack', 1);
    c.applyBackendEvent('engineExhausted', 'software');
    expect(c.engineExhausted, isTrue);
    expect(c.hasError, isFalse, reason: 'sinon l\'écran rouvrirait le même décodeur en boucle');
    c.dispose();
  });

  test('une position sans lecture ne retire pas le logo', () {
    final NativeVideoController c = NativeVideoController();
    c.setUrl('http://a.example.invalid/live/u/p/1.ts');
    c.applyBackendEvent('ack', 1);
    c.applyBackendEvent('playing', false);
    c.applyBackendEvent('position', 5000);
    expect(c.firstFrame, isFalse);
    c.dispose();
  });
}
