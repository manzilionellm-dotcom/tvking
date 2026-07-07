// =========================================================
//  freeze_recovery_policy_test.dart
// =========================================================
//  Couvre la machine à états anti-gel EXTRAITE de tv_player_screen. Le test
//  le plus important ici est « gel persistant après une 1re tentative » : il
//  reproduit exactement le bug du spinner infini du 2026-07-06 (le verrou
//  `_recovering` n'était jamais relâché tant que la position n'avançait pas,
//  donc plus AUCUNE reconnexion ne partait après la tentative #1, et l'écran
//  d'erreur borné — P1-6 — était inatteignable). Sans le correctif dans
//  `onTick`, ce test échoue en boucle infinie de FreezeAction.none.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/data/freeze_recovery_policy.dart';

void main() {
  final DateTime t0 = DateTime(2026, 7, 6, 12);

  group('FreezeRecoveryPolicy', () {
    test('lecture saine : la progression ré-arme tout, aucun tick n\'agit',
        () {
      final FreezeRecoveryPolicy p = FreezeRecoveryPolicy(now: t0);
      p.onProgress(t0.add(const Duration(seconds: 5)));
      expect(p.onTick(t0.add(const Duration(seconds: 10))), FreezeAction.none);
      expect(p.attempts, 0);
      expect(p.isFatal, isFalse);
    });

    test('avant 15 s sans progression, le tick ne fait rien', () {
      final FreezeRecoveryPolicy p = FreezeRecoveryPolicy(now: t0);
      expect(p.onTick(t0.add(const Duration(seconds: 14))), FreezeAction.none);
      expect(p.attempts, 0);
    });

    test('gel de 15 s → 1re reconnexion (reopen)', () {
      final FreezeRecoveryPolicy p = FreezeRecoveryPolicy(now: t0);
      expect(
        p.onTick(t0.add(const Duration(seconds: 16))),
        FreezeAction.reopen,
      );
      expect(p.attempts, 1);
    });

    test(
        'RÉGRESSION 2026-07-06 : le gel qui PERSISTE après une tentative '
        'relance encore — pas de verrou bloqué pour toujours', () {
      final FreezeRecoveryPolicy p = FreezeRecoveryPolicy(now: t0);
      // 1re tentative à t=16s.
      DateTime now = t0.add(const Duration(seconds: 16));
      expect(p.onTick(now), FreezeAction.reopen);
      expect(p.attempts, 1);

      // La reconnexion échoue elle aussi : AUCUNE progression n'arrive.
      // Avant le correctif, tous les ticks suivants renvoyaient `none` pour
      // toujours (verrou `_recovering` jamais relâché) → spinner infini.
      now = now.add(const Duration(seconds: 4)); // tick watchdog suivant
      expect(p.onTick(now), FreezeAction.none); // pas encore un plein cycle
      now = now.add(const Duration(seconds: 15)); // encore gelé 15s de plus
      expect(p.onTick(now), FreezeAction.reopen); // 2e tentative — PAS none
      expect(p.attempts, 2);
    });

    test('budget épuisé après maxAttempts → écran d\'erreur (fatal)', () {
      final FreezeRecoveryPolicy p =
          FreezeRecoveryPolicy(now: t0, maxAttempts: 3);
      DateTime now = t0;
      for (int i = 1; i <= 3; i++) {
        now = now.add(const Duration(seconds: 16));
        expect(p.onTick(now), FreezeAction.reopen);
        expect(p.attempts, i);
        expect(p.isFatal, isFalse);
      }
      // Toujours gelé au-delà de la dernière tentative → fatal.
      now = now.add(const Duration(seconds: 16));
      expect(p.onTick(now), FreezeAction.fatal);
      expect(p.isFatal, isTrue);
      // Et ça reste fatal (aucun spam de ticks une fois l'écran affiché).
      expect(p.onTick(now.add(const Duration(seconds: 100))), FreezeAction.none);
    });

    test('openChannel() (nouvelle chaîne / Réessayer manuel) repart neuf', () {
      final FreezeRecoveryPolicy p =
          FreezeRecoveryPolicy(now: t0, maxAttempts: 1);
      final DateTime frozen = t0.add(const Duration(seconds: 16));
      expect(p.onTick(frozen), FreezeAction.reopen);
      expect(p.onTick(frozen.add(const Duration(seconds: 16))),
          FreezeAction.fatal);
      expect(p.isFatal, isTrue);

      final DateTime retryAt = frozen.add(const Duration(seconds: 20));
      p.openChannel(retryAt);
      expect(p.isFatal, isFalse);
      expect(p.attempts, 0);
      // Horloge fraîche : pas de watchdog immédiat juste après le retry.
      expect(p.onTick(retryAt.add(const Duration(seconds: 1))),
          FreezeAction.none);
    });

    test('erreur native pendant une tentative en cours : pas de double reopen',
        () {
      final FreezeRecoveryPolicy p = FreezeRecoveryPolicy(now: t0);
      final DateTime now = t0.add(const Duration(seconds: 16));
      expect(p.onTick(now), FreezeAction.reopen); // tentative lancée
      // Le natif remonte une erreur PENDANT que cette tentative est en cours
      // (avant le prochain tick) : on ne relance pas une 2e fois par-dessus.
      expect(p.onPlayerError(now.add(const Duration(seconds: 1))),
          FreezeAction.none);
      expect(p.attempts, 1);
    });

    test('erreur native hors reconnexion : relance immédiatement', () {
      final FreezeRecoveryPolicy p = FreezeRecoveryPolicy(now: t0);
      p.onProgress(t0); // lecture saine, pas de reconnexion en cours
      expect(p.onPlayerError(t0.add(const Duration(seconds: 1))),
          FreezeAction.reopen);
      expect(p.attempts, 1);
    });
  });
}
