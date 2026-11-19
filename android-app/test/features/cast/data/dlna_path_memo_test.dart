// =========================================================
//  dlna_path_memo_test.dart — Mémoire de chemin DLNA (2026-07-09)
// =========================================================
//  Boîte noire Nebula-22A4AB : le direct répond en ~3 s la plupart du
//  temps, puis reste muet 15 s (timeout SOAP) par vagues. Chaque vague
//  coûtait 15 s de direct + ~22 s de relais = sessions à 40-70 s.
//
//  La mémoire de chemin apprend par appareil :
//    - 1 échec CONNEXION direct récent  → timeout SOAP direct 8 s
//    - ≥ 2 échecs consécutifs récents   → on démarre au relais (s=3)
//    - fenêtre expirée (15 min)         → comportement par défaut
//      (le direct — téléphone-éteint-TV-continue — est re-sondé)
//
//  Ces tests verrouillent les deux décisions PURES (sans stack réseau).
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/upnp_av_transport.dart';

void main() {
  final DateTime now = DateTime(2026, 7, 9, 16, 30);

  group('dlnaStartStrategyFor — départ direct vs relais', () {
    test('aucun historique → direct (stratégie 0)', () {
      expect(
        CastManager.dlnaStartStrategyFor(
          failStreak: 0,
          lastFail: null,
          now: now,
        ),
        0,
      );
    });

    test('1 seul échec récent → toujours direct (0)', () {
      expect(
        CastManager.dlnaStartStrategyFor(
          failStreak: 1,
          lastFail: now.subtract(const Duration(minutes: 1)),
          now: now,
        ),
        0,
      );
    });

    test('2 échecs consécutifs récents → relais (3)', () {
      expect(
        CastManager.dlnaStartStrategyFor(
          failStreak: 2,
          lastFail: now.subtract(const Duration(minutes: 1)),
          now: now,
        ),
        3,
      );
    });

    test('2 échecs mais fenêtre expirée → direct re-sondé (0)', () {
      expect(
        CastManager.dlnaStartStrategyFor(
          failStreak: 2,
          lastFail: now.subtract(kDlnaPathMemoTtl + const Duration(seconds: 1)),
          now: now,
        ),
        0,
      );
    });
  });

  group('dlnaStartStrategyFor — souvenir de VICTOIRE (LG 2026-07-17)', () {
    // Terrain : la cascade re-payait ~45 s d'essais perdus à CHAQUE
    // chaîne (direct 15 s + relay+full en timeout) avant de retomber
    // sur la stratégie gagnante. Le souvenir de victoire démarre
    // directement dessus.
    test('victoire fraîche → on démarre sur la stratégie gagnante', () {
      expect(
        CastManager.dlnaStartStrategyFor(
          failStreak: 0,
          lastFail: null,
          now: now,
          winningStrategy: 4, // relay+minimal (gagnant Roland Garros)
          lastWin: now.subtract(const Duration(minutes: 2)),
        ),
        4,
      );
    });

    test('victoire expirée (TTL) → échelle complète (0)', () {
      expect(
        CastManager.dlnaStartStrategyFor(
          failStreak: 0,
          lastFail: null,
          now: now,
          winningStrategy: 4,
          lastWin: now.subtract(kDlnaPathMemoTtl + const Duration(seconds: 1)),
        ),
        0,
      );
    });

    test('échec direct PLUS RÉCENT que la victoire → la mémoire '
        'd\'échecs garde la main', () {
      expect(
        CastManager.dlnaStartStrategyFor(
          failStreak: 2,
          lastFail: now.subtract(const Duration(minutes: 1)),
          now: now,
          winningStrategy: 1, // vieille victoire directe
          lastWin: now.subtract(const Duration(minutes: 5)),
        ),
        3,
        reason: 'la TV vient de rester muette en direct : repartir '
            'sur la victoire directe périmée re-paierait les timeouts',
      );
    });

    test('victoire plus récente que le dernier échec → la victoire '
        'gagne', () {
      expect(
        CastManager.dlnaStartStrategyFor(
          failStreak: 2,
          lastFail: now.subtract(const Duration(minutes: 5)),
          now: now,
          winningStrategy: 4,
          lastWin: now.subtract(const Duration(minutes: 1)),
        ),
        4,
      );
    });

    test('sans victoire → comportement historique inchangé', () {
      expect(
        CastManager.dlnaStartStrategyFor(
          failStreak: 2,
          lastFail: now.subtract(const Duration(minutes: 1)),
          now: now,
          winningStrategy: null,
          lastWin: null,
        ),
        3,
      );
    });
  });

  group('dlnaDirectSoapTimeoutFor — timeout SOAP adaptatif', () {
    test('aucun historique → timeout plein (15 s)', () {
      expect(
        CastManager.dlnaDirectSoapTimeoutFor(
          failStreak: 0,
          lastFail: null,
          now: now,
        ),
        UpnpAvTransport.kDefaultSoapTimeout,
      );
    });

    test('1 échec récent → timeout raccourci (8 s)', () {
      expect(
        CastManager.dlnaDirectSoapTimeoutFor(
          failStreak: 1,
          lastFail: now.subtract(const Duration(minutes: 2)),
          now: now,
        ),
        kDlnaShortSoapTimeout,
      );
    });

    test('échec trop ancien → timeout plein (15 s)', () {
      expect(
        CastManager.dlnaDirectSoapTimeoutFor(
          failStreak: 3,
          lastFail: now.subtract(const Duration(hours: 1)),
          now: now,
        ),
        UpnpAvTransport.kDefaultSoapTimeout,
      );
    });
  });
}
