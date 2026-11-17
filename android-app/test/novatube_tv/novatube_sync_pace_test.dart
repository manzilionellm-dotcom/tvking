// =========================================================
//  Rythme de synchronisation panel → box : jamais en boucle chaque seconde
//  dans l'édition NovaTube ; Zuno inchangé. Lancé dans les deux modes.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/app/novatube_tv_edition.dart';
import 'package:tv_king/features/subscription/domain/activation_pace.dart';
import 'package:tv_king/features/subscription/domain/box_signal.dart';

void main() {
  if (kNovatubeTv) {
    test('NovaTube : jamais moins de 5 s entre deux lectures du statut', () {
      for (final bool waiting in <bool>[true, false]) {
        for (int failures = 0; failures < 12; failures++) {
          final Duration d =
              ActivationPace.next(waiting: waiting, failures: failures);
          expect(d, greaterThanOrEqualTo(const Duration(seconds: 5)));
          expect(d, lessThanOrEqualTo(const Duration(minutes: 2)));
        }
      }
    });

    test('NovaTube : reprise progressive après des échecs réseau', () {
      final List<int> secs = <int>[
        for (int f = 0; f < 6; f++)
          ActivationPace.next(waiting: true, failures: f).inSeconds,
      ];
      expect(secs, <int>[5, 10, 20, 40, 80, 80]);
      expect(ActivationPace.next(waiting: false, failures: 9),
          const Duration(minutes: 2));
    });

    test('NovaTube : canal du panel ouvert → simple filet toutes les 60 s', () {
      expect(signalPace(channelUp: true, waiting: true, failures: 0),
          const Duration(seconds: 60));
    });
  } else {
    test('Zuno : rythme historique inchangé (1 s / 2 s / 25 s / 45 s)', () {
      expect(ActivationPace.fast, const Duration(seconds: 1));
      expect(ActivationPace.calm, const Duration(seconds: 2));
      expect(ActivationPace.parked, const Duration(seconds: 25));
      expect(ActivationPace.ceiling, const Duration(seconds: 45));
    });
  }
}
