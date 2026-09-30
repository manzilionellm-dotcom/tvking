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
  setUp(() => NativeVideoController.backendFactory = null);

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
    c.applyBackendEvent('firstFrame', null);
    expect(c.firstFrame, isTrue);

    c.setUrl('http://a.example.invalid/live/u/p/2.ts');
    expect(c.firstFrame, isFalse, reason: 'le zap remet le logo');
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
