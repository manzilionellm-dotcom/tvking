// =========================================================
//  cast_brand_detection_test.dart — Reconnaissance des marques TV
// =========================================================
//  Vérifie detectCastBrand() pour les 10 marques de TV les plus
//  répandues, depuis le fabricant, le nom convivial OU l'OS annoncé
//  (webOS→LG, Tizen→Samsung, Bravia→Sony, etc.). Purement informatif
//  (affichage + diagnostic) — n'affecte pas le protocole de cast.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';

void main() {
  group('detectCastBrand — 10 marques principales', () {
    test('par fabricant', () {
      expect(detectCastBrand('TV', 'Samsung Electronics'), 'Samsung');
      expect(detectCastBrand('TV', 'LG Electronics'), 'LG');
      expect(detectCastBrand('TV', 'Sony'), 'Sony');
      expect(detectCastBrand('TV', 'TCL'), 'TCL');
      expect(detectCastBrand('TV', 'Hisense'), 'Hisense');
      expect(detectCastBrand('TV', 'VIZIO'), 'Vizio');
      expect(detectCastBrand('TV', 'Philips'), 'Philips');
      expect(detectCastBrand('TV', 'Panasonic'), 'Panasonic');
      expect(detectCastBrand('TV', 'Sharp'), 'Sharp');
      expect(detectCastBrand('TV', 'Toshiba'), 'Toshiba');
    });

    test('par nom convivial / OS annoncé', () {
      expect(detectCastBrand('[LG] webOS TV QNED816QA', null), 'LG');
      expect(detectCastBrand('Tizen Smart TV (Salon)', null), 'Samsung');
      expect(detectCastBrand('BRAVIA 4K', null), 'Sony');
      expect(detectCastBrand('Hisense VIDAA TV', null), 'Hisense');
      expect(detectCastBrand('Vizio SmartCast', null), 'Vizio');
      expect(detectCastBrand('Panasonic VIERA', null), 'Panasonic');
      expect(detectCastBrand('AQUOS 55', null), 'Sharp');
      expect(detectCastBrand('REGZA 50', null), 'Toshiba');
    });

    test('marque inconnue / device générique → null', () {
      expect(detectCastBrand('Salon', null), isNull);
      expect(detectCastBrand('Chambre', 'Google Cast'), isNull);
      expect(detectCastBrand('Récepteur DLNA', null), isNull);
    });

    test('insensible à la casse', () {
      expect(detectCastBrand('tv', 'samsung'), 'Samsung');
      expect(detectCastBrand('WEBOS tv', null), 'LG');
    });
  });
}
