// =========================================================
//  native_video_controller_test.dart — état du lecteur natif TV
// =========================================================
//  Verrouille la traduction des évènements poussés par NativeVideoView.kt
//  (côté natif) vers l'état Dart consommé par tv_player_screen.dart. En
//  particulier le cas AJOUTÉ pour la stabilité : `unsupportedCodec`, qui
//  doit être DISTINCT d'une simple erreur réseau (l'écran affiche « Format
//  non supporté » + Réessayer au lieu de reconnecter en boucle).
//
//  Tests purs : on pilote le controller via `applyNativeEvent`
//  (@visibleForTesting) — pas besoin du binding Flutter ni d'un vrai
//  MethodChannel.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';

void main() {
  group('NativeVideoController — évènements natifs', () {
    test('unsupportedCodec : drapeau dédié + erreur + diagnostic capturé', () {
      final NativeVideoController c = NativeVideoController();
      c.applyNativeEvent('unsupportedCodec', <Object?, Object?>{
        'device': 'Generic TV Box',
        'android': '9 (SDK 28)',
        'codec': 'video/hevc',
        'hardwareDecoders': '',
      });

      // C'est le drapeau qui pousse l'écran vers « Format non supporté ».
      expect(c.unsupportedCodec, isTrue);
      // hasError est AUSSI vrai : tout code qui regarde hasError reste correct.
      expect(c.hasError, isTrue);
      // Le diagnostic est typé String->Object? et conserve le codec demandé.
      expect(c.diagnostics, isNotNull);
      expect(c.diagnostics!['codec'], 'video/hevc');
      expect(c.diagnostics!['device'], 'Generic TV Box');
    });

    test('error réseau terminale : hasError sans unsupportedCodec', () {
      final NativeVideoController c = NativeVideoController();
      c.applyNativeEvent('error', 'Source error');

      expect(c.hasError, isTrue);
      // PAS un problème de codec → l'écran propose « Chargement trop long »,
      // pas « Format non supporté ».
      expect(c.unsupportedCodec, isFalse);
    });

    test('firstFrame : masque le buffering', () {
      final NativeVideoController c = NativeVideoController();
      expect(c.isBuffering, isTrue); // état initial
      c.applyNativeEvent('firstFrame', null);

      expect(c.firstFrame, isTrue);
      expect(c.isBuffering, isFalse);
    });

    test('setUrl efface tout état d\'erreur (nouvelle tentative propre)', () {
      final NativeVideoController c = NativeVideoController();
      c.applyNativeEvent('unsupportedCodec', <Object?, Object?>{'codec': 'x'});
      expect(c.unsupportedCodec, isTrue);
      expect(c.hasError, isTrue);

      // Réessayer / zapper recharge une URL → l'état d'erreur DOIT repartir à
      // zéro, sinon l'overlay resterait collé sur la nouvelle chaîne.
      c.setUrl('http://example/stream.ts');

      expect(c.unsupportedCodec, isFalse);
      expect(c.hasError, isFalse);
      expect(c.diagnostics, isNull);
      expect(c.firstFrame, isFalse);
      expect(c.isBuffering, isTrue);
    });
  });
}
