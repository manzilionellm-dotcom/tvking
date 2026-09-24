// =========================================================
//  google_cast_transport_test.dart — Bugs A & B
// =========================================================
//  Vérifie les décisions PURES du transport Chromecast :
//    - isHlsOrDash : ne wrappe pas un flux déjà adaptatif ;
//    - isExoPlayerReceiver : SHIELD lit le .ts direct ;
//    - sameSubnet : la TV doit joindre le serveur HLS local.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/google_cast_transport.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';

CastDevice _dev({String name = 'TV', String? model, String? manuf}) =>
    CastDevice(
      id: 'x',
      name: name,
      kind: CastDeviceKind.chromecast,
      host: '192.168.1.20',
      port: 8009,
      controlUrl: '',
      manufacturer: manuf,
      model: model,
    );

void main() {
  group('isHlsOrDash (BUG A)', () {
    test('HLS / DASH → adaptatif (pas de wrap)', () {
      expect(GoogleCastTransport.isHlsOrDash('http://x/live.m3u8'), isTrue);
      expect(GoogleCastTransport.isHlsOrDash('http://x/v.mpd'), isTrue);
    });
    test('MPEG-TS / sans extension → non adaptatif (wrap)', () {
      expect(GoogleCastTransport.isHlsOrDash('http://x/live/u/p/12.ts'), isFalse);
      expect(GoogleCastTransport.isHlsOrDash('http://x/live/u/p/12'), isFalse);
    });
  });

  group('isExoPlayerReceiver (BUG A)', () {
    test('SHIELD → ExoPlayer (direct OK)', () {
      expect(GoogleCastTransport.isExoPlayerReceiver(_dev(model: 'SHIELD')), isTrue);
      expect(
          GoogleCastTransport.isExoPlayerReceiver(_dev(manuf: 'NVIDIA')), isTrue);
    });
    test('Chromecast pur → wrap par défaut', () {
      expect(
          GoogleCastTransport.isExoPlayerReceiver(_dev(name: 'Chambre')), isFalse);
    });
  });

  group('sameSubnet (BUG B)', () {
    test('même /24 → joignable', () {
      expect(
        GoogleCastTransport.sameSubnet('http://192.168.1.5:8080/x.m3u8',
            '192.168.1.20'),
        isTrue,
      );
    });
    test('sous-réseaux différents → injoignable', () {
      expect(
        GoogleCastTransport.sameSubnet('http://192.168.1.5/x', '10.0.0.5'),
        isFalse,
      );
    });
    test('host non-IPv4 → on ne bloque pas (true)', () {
      expect(
        GoogleCastTransport.sameSubnet('http://monpc.local/x', 'tv.local'),
        isTrue,
      );
    });
  });
}
