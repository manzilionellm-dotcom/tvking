// =========================================================
//  zap_resource_discipline_test.dart — discipline « ressources » du zap
// =========================================================
//  Mission stabilité-zap, Étape 4 (non-régression). Le bug n°1 = l'app se
//  ferme après ~5-6 changements de chaîne (accumulation de ressources natives).
//  Le correctif côté Dart repose sur deux invariants que CE test verrouille,
//  pour qu'une régression future les casse bruyamment :
//
//    1) CHAQUE zap qui aboutit recharge l'URL via `setUrl`, qui REMET À ZÉRO
//       l'état d'affichage (erreur, codec, buffering, 1re trame) et notifie
//       EXACTEMENT UNE fois — pas de rafale de notifications par zap.
//    2) APRÈS `dispose()` (l'écran se ferme pendant qu'un zap est en vol), plus
//       aucune notification ne part et rien ne lève — sinon « used after
//       disposed » planterait justement au pire moment.
//
//  Portée : ce test est PUR (pas de binding Flutter, pas de vrai MethodChannel —
//  le controller n'est pas rattaché à une PlatformView ici). Il valide donc la
//  LOGIQUE Dart d'orchestration. Le vrai test « 50 zaps sur la box » qui
//  exerce ExoPlayer/MediaCodec reste un test d'intégration on-device (matériel
//  requis), à ajouter une fois la stack native confirmée par Crashlytics.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';

void main() {
  group('Discipline ressources — zap répété', () {
    test('rafale de 50 zaps : état propre + exactement 1 notification / zap', () {
      final NativeVideoController c = NativeVideoController();

      // On compte les notifications : c'est notre proxy du « nombre de
      // transitions d'état ». Un zap = une ouverture = UNE notification.
      int notifications = 0;
      c.addListener(() => notifications++);

      const int zaps = 50; // la cible mesurable du brief (« 50+ chaînes »).
      for (int i = 0; i < zaps; i++) {
        // Simule l'arrivée sur la chaîne précédente : 1re trame, puis (1 fois
        // sur 3) une erreur réseau terminale ou un codec non supporté. Ces
        // évènements natifs NE notifient PAS (cf. applyNativeEvent) — c'est
        // voulu : seul le prochain setUrl déclenche la transition.
        c.applyNativeEvent('firstFrame', null);
        if (i % 3 == 0) {
          c.applyNativeEvent('error', 'Source error');
        } else if (i % 3 == 1) {
          c.applyNativeEvent('unsupportedCodec', <Object?, Object?>{'codec': 'x'});
        }

        // Le zap « stabilisé » recharge la chaîne suivante.
        c.setUrl('http://example/stream_$i.ts');

        // INVARIANT : setUrl repart d'un état d'affichage propre, peu importe
        // l'erreur héritée de la chaîne précédente. Sinon l'overlay d'erreur
        // resterait collé en zappant → faux « plantage » visuel.
        expect(c.hasError, isFalse, reason: 'zap #$i : erreur non effacée');
        expect(c.unsupportedCodec, isFalse, reason: 'zap #$i : codec non effacé');
        expect(c.diagnostics, isNull, reason: 'zap #$i : diag non effacé');
        expect(c.firstFrame, isFalse, reason: 'zap #$i : 1re trame non remise');
        expect(c.isBuffering, isTrue, reason: 'zap #$i : buffering non réarmé');
      }

      // INVARIANT clé : 1 notification par zap, NI PLUS (pas de tempête de
      // notifications qui ferait re-rendre/ré-ouvrir en boucle) NI MOINS.
      expect(notifications, zaps);

      c.dispose();
    });

    test('après dispose : aucune notification, aucun throw (zap vs fermeture)',
        () {
      final NativeVideoController c = NativeVideoController();
      int notifications = 0;
      c.addListener(() => notifications++);

      // L'écran se ferme.
      c.dispose();

      // Un zap (ou une reconnexion du watchdog) arrive APRÈS la fermeture :
      // ça ne doit NI notifier (ChangeNotifier déjà disposé → assert) NI lever.
      expect(() => c.setUrl('http://example/late.ts'), returnsNormally);
      expect(() => c.play(), returnsNormally);
      expect(() => c.pause(), returnsNormally);

      expect(notifications, 0, reason: 'notification émise après dispose');
    });
  });
}
