// Tests de l'anti-harcèlement des mises à jour (UpdatePolicy, pur).
// Scénario terrain corrigé : « je viens d'installer, et une heure après
// on me fait encore installer une autre ».

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/update/update_policy.dart';

void main() {
  const int h = 60 * 60 * 1000; // 1 heure en ms
  const int now = 1000000 * h;

  group('Grâce d\'installation fraîche', () {
    test('1 h après une installation fraîche → silence', () {
      expect(
        UpdatePolicy.shouldPropose(
          mandatory: false,
          versionCode: 42,
          nowMs: now,
          firstRunAtMs: now - 1 * h,
        ),
        isFalse,
      );
    });

    test('après la grâce (13 h) → proposition possible', () {
      expect(
        UpdatePolicy.shouldPropose(
          mandatory: false,
          versionCode: 42,
          nowMs: now,
          firstRunAtMs: now - 13 * h,
        ),
        isTrue,
      );
    });

    test('firstRun inconnu (0) → pas de grâce, on ne bloque pas', () {
      expect(
        UpdatePolicy.shouldPropose(
          mandatory: false,
          versionCode: 42,
          nowMs: now,
        ),
        isTrue,
      );
    });
  });

  group('Espacement global (1 proposition / 24 h, toutes versions)', () {
    test('5 builds publiés dans la journée → une seule proposition', () {
      // Une proposition a eu lieu il y a 2 h ; une NOUVELLE version sort.
      expect(
        UpdatePolicy.shouldPropose(
          mandatory: false,
          versionCode: 43, // version différente !
          nowMs: now,
          lastLaunchedCode: 42,
          lastLaunchedAtMs: now - 2 * h,
          lastProposalAtMs: now - 2 * h,
          firstRunAtMs: now - 100 * h,
        ),
        isFalse,
      );
    });

    test('25 h après la dernière proposition → nouvelle version proposée',
        () {
      expect(
        UpdatePolicy.shouldPropose(
          mandatory: false,
          versionCode: 43,
          nowMs: now,
          lastLaunchedCode: 42,
          lastLaunchedAtMs: now - 25 * h,
          lastProposalAtMs: now - 25 * h,
          firstRunAtMs: now - 100 * h,
        ),
        isTrue,
      );
    });
  });

  group('Même version', () {
    test('jamais reproposée avant 24 h — même un correctif critique', () {
      for (final bool mandatory in <bool>[false, true]) {
        expect(
          UpdatePolicy.shouldPropose(
            mandatory: mandatory,
            versionCode: 42,
            nowMs: now,
            lastLaunchedCode: 42,
            lastLaunchedAtMs: now - 3 * h,
            lastProposalAtMs: now - 3 * h,
            firstRunAtMs: now - 100 * h,
          ),
          isFalse,
          reason: 'mandatory=$mandatory',
        );
      }
    });
  });

  group('Correctif critique (mandatory)', () {
    test('perce la grâce ET l\'espacement (version différente)', () {
      expect(
        UpdatePolicy.shouldPropose(
          mandatory: true,
          versionCode: 99,
          nowMs: now,
          lastLaunchedCode: 42,
          lastLaunchedAtMs: now - 2 * h,
          lastProposalAtMs: now - 2 * h,
          firstRunAtMs: now - 1 * h, // grâce active
        ),
        isTrue,
      );
    });
  });
}
