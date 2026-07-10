// =========================================================
//  autoplay_policy_test.dart
// =========================================================
//  Couvre la machine à états « À suivre » EXTRAITE de tv_player_screen :
//  qui a droit à l'autoplay (épisode avec suivant — jamais un film, jamais
//  le live, jamais en fin de saison), le garde-fou anti-binge-infini
//  (3 enchaînements automatiques sans interaction → on attend un OK),
//  la remise à zéro à chaque interaction télécommande, et la mémoire
//  d'annulation (le natif ré-émet `isEnded` en boucle sur l'écran de fin :
//  sans cette mémoire, la carte réapparaîtrait juste après « Annuler »).
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/data/autoplay_policy.dart';

void main() {
  group('AutoplayPolicy — qui a droit à la proposition', () {
    test('épisode avec un épisode suivant → compte à rebours automatique', () {
      final AutoplayPolicy p = AutoplayPolicy();
      expect(
        p.onEnded(isLive: false, currentId: 'ep-101', nextId: 'ep-102'),
        UpNextDecision.autoCountdown,
      );
    });

    test('dernier épisode de la liste (nextId null) → rien (écran de fin)',
        () {
      final AutoplayPolicy p = AutoplayPolicy();
      expect(
        p.onEnded(isLive: false, currentId: 'ep-101', nextId: null),
        UpNextDecision.none,
      );
    });

    test('FILM (vod-…) → jamais d\'enchaînement, même avec un « suivant »',
        () {
      final AutoplayPolicy p = AutoplayPolicy();
      expect(
        p.onEnded(isLive: false, currentId: 'vod-55', nextId: 'vod-56'),
        UpNextDecision.none,
      );
    });

    test('LIVE → jamais (un direct n\'a pas de fin exploitable)', () {
      final AutoplayPolicy p = AutoplayPolicy();
      expect(
        p.onEnded(isLive: true, currentId: 'ep-101', nextId: 'ep-102'),
        UpNextDecision.none,
      );
    });

    test('suivant qui n\'est PAS un épisode (liste hétérogène) → rien', () {
      final AutoplayPolicy p = AutoplayPolicy();
      expect(
        p.onEnded(isLive: false, currentId: 'ep-101', nextId: 'vod-56'),
        UpNextDecision.none,
      );
    });
  });

  group('AutoplayPolicy — garde-fou anti-binge-infini', () {
    test('3 enchaînements automatiques sans interaction → on attend un OK',
        () {
      final AutoplayPolicy p = AutoplayPolicy(); // maxAutoChains = 3
      // Épisodes 1 → 2 → 3 enchaînés tout seuls (personne ne touche rien).
      for (int i = 1; i <= 3; i++) {
        expect(
          p.onEnded(isLive: false, currentId: 'ep-$i', nextId: 'ep-${i + 1}'),
          UpNextDecision.autoCountdown,
        );
        p.onAutoAdvance();
        expect(p.autoChains, i);
      }
      // 4e fin : la carte s'affiche mais N'ENCHAÎNE PLUS toute seule.
      expect(
        p.onEnded(isLive: false, currentId: 'ep-4', nextId: 'ep-5'),
        UpNextDecision.waitForConfirm,
      );
    });

    test('une interaction télécommande remet le compteur à zéro', () {
      final AutoplayPolicy p = AutoplayPolicy();
      p.onAutoAdvance();
      p.onAutoAdvance();
      p.onAutoAdvance();
      expect(
        p.onEnded(isLive: false, currentId: 'ep-4', nextId: 'ep-5'),
        UpNextDecision.waitForConfirm,
      );
      // Quelqu'un appuie sur une touche : il est bien devant l'écran.
      p.onUserInteraction();
      expect(p.autoChains, 0);
      expect(
        p.onEnded(isLive: false, currentId: 'ep-4', nextId: 'ep-5'),
        UpNextDecision.autoCountdown,
      );
    });

    test('garde-fou paramétrable (maxAutoChains)', () {
      final AutoplayPolicy p = AutoplayPolicy(maxAutoChains: 1);
      p.onAutoAdvance();
      expect(
        p.onEnded(isLive: false, currentId: 'ep-2', nextId: 'ep-3'),
        UpNextDecision.waitForConfirm,
      );
    });
  });

  group('AutoplayPolicy — annulation', () {
    test('après « Annuler », le MÊME contenu ne re-propose plus (le natif '
        're-notifie isEnded en boucle sur l\'écran de fin)', () {
      final AutoplayPolicy p = AutoplayPolicy();
      expect(
        p.onEnded(isLive: false, currentId: 'ep-101', nextId: 'ep-102'),
        UpNextDecision.autoCountdown,
      );
      p.onCancel('ep-101');
      // Notifications suivantes du natif : silence radio.
      expect(
        p.onEnded(isLive: false, currentId: 'ep-101', nextId: 'ep-102'),
        UpNextDecision.none,
      );
      expect(
        p.onEnded(isLive: false, currentId: 'ep-101', nextId: 'ep-102'),
        UpNextDecision.none,
      );
    });

    test('l\'annulation ne bloque PAS un autre contenu, et compte comme '
        'une interaction (compteur à zéro)', () {
      final AutoplayPolicy p = AutoplayPolicy();
      p.onAutoAdvance();
      p.onAutoAdvance();
      p.onCancel('ep-101');
      expect(p.autoChains, 0);
      expect(
        p.onEnded(isLive: false, currentId: 'ep-102', nextId: 'ep-103'),
        UpNextDecision.autoCountdown,
      );
    });
  });

  group('AutoplayPolicy — helpers', () {
    test('isEpisodeId reconnaît la convention ep-… / vod-…', () {
      expect(AutoplayPolicy.isEpisodeId('ep-42'), isTrue);
      expect(AutoplayPolicy.isEpisodeId('vod-42'), isFalse);
      expect(AutoplayPolicy.isEpisodeId('live-42'), isFalse);
    });

    test('canPropose est pur : aucune influence de l\'état interne', () {
      final AutoplayPolicy p = AutoplayPolicy();
      p.onCancel('ep-101'); // même annulé…
      // … canPropose répond toujours « il Y A un suivant » (c'est onEnded
      // qui applique la mémoire d'annulation) : le lecteur s'en sert pour
      // savoir si l'overlay POSSÈDE la fin de ce contenu.
      expect(
        p.canPropose(isLive: false, currentId: 'ep-101', nextId: 'ep-102'),
        isTrue,
      );
    });
  });
}
