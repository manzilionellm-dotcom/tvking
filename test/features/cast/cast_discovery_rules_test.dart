// =========================================================
//  cast_discovery_rules_test.dart — Correctif #1
// =========================================================
//  Vérifie la règle d'ajout d'un device découvert :
//    - hors fenêtre de découverte → jamais ajouté (pas d'arrivée
//      tardive après le timeout),
//    - dédup par id ET par host:port.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';

CastDevice _dev(String id, String host, int port) => CastDevice(
      id: id,
      name: id,
      kind: CastDeviceKind.chromecast,
      host: host,
      port: port,
      controlUrl: '',
    );

void main() {
  group('castShouldAddDevice', () {
    test('fenêtre fermée → jamais ajouté', () {
      expect(
        castShouldAddDevice(
          <CastDevice>[],
          _dev('a', '1.2.3.4', 8009),
          windowOpen: false,
        ),
        isFalse,
      );
    });

    test('nouveau device + fenêtre ouverte → ajouté', () {
      expect(
        castShouldAddDevice(
          <CastDevice>[],
          _dev('a', '1.2.3.4', 8009),
          windowOpen: true,
        ),
        isTrue,
      );
    });

    test('dédup par id', () {
      final List<CastDevice> existing = <CastDevice>[_dev('a', '1.2.3.4', 8009)];
      expect(
        castShouldAddDevice(existing, _dev('a', '9.9.9.9', 1),
            windowOpen: true),
        isFalse,
      );
    });

    test('dédup par host:port', () {
      final List<CastDevice> existing = <CastDevice>[_dev('a', '1.2.3.4', 8009)];
      expect(
        castShouldAddDevice(existing, _dev('b', '1.2.3.4', 8009),
            windowOpen: true),
        isFalse,
      );
    });

    test('même host, port différent → ajouté', () {
      final List<CastDevice> existing = <CastDevice>[_dev('a', '1.2.3.4', 8009)];
      expect(
        castShouldAddDevice(existing, _dev('b', '1.2.3.4', 9000),
            windowOpen: true),
        isTrue,
      );
    });
  });
}
