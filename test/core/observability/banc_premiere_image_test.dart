// =========================================================
//  banc_premiere_image_test.dart — le temps jusqu'à la 1re image
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (19/09/2026) : « ajoute un événement
//  tv_player.first_frame_ms dans la Boîte noire, avec médiane par build
//  dans le panel — le critère temps de chargement devient mesuré, pas
//  estimé. »
//
//  Ce que ces tests verrouillent :
//    • chaque ouverture mesurée est GARDÉE (une liste, pas une moyenne) ;
//    • la médiane résiste à un zap à 20 s au milieu d'une soirée à 1,5 s ;
//    • une ligne abîmée (ms absent, négatif, texte) est ignorée sans
//      faire tomber le comptage ;
//    • « rien mesuré » voyage comme null, jamais comme 0 ms ;
//    • la mesure ne change PAS la note : c'est une mesure, pas un
//      reproche.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/observability/banc_essai.dart';

Map<String, Object?> _image(Object? ms) => <String, Object?>{
      'lvl': 'info',
      'domain': 'native',
      'event': 'tv_player.first_frame',
      'ctx': <String, Object?>{'ms': ms, 'channelId': 'c1'},
    };

void main() {
  group('collecte', () {
    test('chaque ouverture est gardée, dans l\'ordre du journal', () {
      final BancMesure m = mesurerBanc(<Map<String, Object?>>[
        _image(1500),
        _image(900),
        _image(2100),
      ], duree: const Duration(hours: 2));
      expect(m.premieresImages, 3);
      expect(m.premieresImagesMs, <int>[1500, 900, 2100]);
    });

    test('la médiane ignore le zap catastrophique', () {
      // Une soirée à ~1,5 s et UN zap à 20 s (chaîne morte puis secours).
      // Moyenne = 5,2 s → « build lent ». Médiane = 1,5 s → la vérité.
      final BancMesure m = mesurerBanc(<Map<String, Object?>>[
        _image(1400),
        _image(1500),
        _image(1600),
        _image(1500),
        _image(20000),
      ], duree: const Duration(hours: 2));
      expect(m.premiereImageMedianeMs, 1500);
    });

    test('nombre pair : milieu des deux valeurs centrales', () {
      final BancMesure m = mesurerBanc(<Map<String, Object?>>[
        _image(1000),
        _image(2000),
      ], duree: const Duration(hours: 2));
      expect(m.premiereImageMedianeMs, 1500);
    });

    test('ms absent, négatif ou texte → ligne ignorée, comptage intact', () {
      final BancMesure m = mesurerBanc(<Map<String, Object?>>[
        _image(null),
        _image(-5),
        _image('vite'),
        <String, Object?>{
          'lvl': 'info',
          'domain': 'native',
          'event': 'tv_player.first_frame',
        },
        _image(1200),
      ], duree: const Duration(hours: 2));
      expect(m.premieresImages, 1);
      expect(m.premiereImageMedianeMs, 1200);
    });

    test('rien mesuré → null, pas 0', () {
      final BancMesure m = mesurerBanc(const <Map<String, Object?>>[],
          duree: const Duration(hours: 2));
      expect(m.premieresImages, 0);
      expect(m.premiereImageMedianeMs, isNull);
      expect(noterBanc(m).toJson()['ttff_med'], isNull);
      expect(noterBanc(m).toJson()['ttff_n'], 0);
    });
  });

  group('transport et note', () {
    test('le heartbeat porte la médiane et le nombre d\'ouvertures', () {
      final BancVerdict v = noterBanc(mesurerBanc(<Map<String, Object?>>[
        _image(800),
        _image(1200),
        _image(1000),
      ], duree: const Duration(hours: 2)));
      expect(v.toJson()['ttff_med'], 1000);
      expect(v.toJson()['ttff_n'], 3);
    });

    test('la mesure ne pèse PAS dans la note', () {
      final BancVerdict lent = noterBanc(mesurerBanc(<Map<String, Object?>>[
        _image(15000),
        _image(15000),
      ], duree: const Duration(hours: 2)));
      final BancVerdict vide = noterBanc(mesurerBanc(
          const <Map<String, Object?>>[],
          duree: const Duration(hours: 2)));
      expect(lent.note, vide.note,
          reason: 'une lenteur se lit dans la colonne 1re image, elle ne '
              'se punit pas deux fois');
      expect(lent.note, 100);
    });

    test('la 1re image ne compte pas comme un incident', () {
      final BancMesure m = mesurerBanc(<Map<String, Object?>>[
        _image(1000),
      ], duree: const Duration(hours: 2));
      expect(m.incidents, 0);
    });
  });
}
