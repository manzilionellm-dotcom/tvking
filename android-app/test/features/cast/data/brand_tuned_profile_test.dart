// =========================================================
//  brand_tuned_profile_test.dart — Étiquetage DLNA par marque
// =========================================================
//  Recherche sourcée 2026-07-09 (MediaTomb/SamyGO/minidlna/Serviio) :
//  le même flux MPEG-TS live doit être annoncé différemment selon le
//  constructeur. Ces règles sont pures → testées sans réseau.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/dlna_profiles.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';

CastDevice _device({String name = 'TV', String? manufacturer, String? model}) {
  return CastDevice(
    id: 'test',
    name: name,
    kind: CastDeviceKind.dlna,
    host: '192.168.1.10',
    port: 0,
    controlUrl: 'http://192.168.1.10:0/AVTransport/control',
    manufacturer: manufacturer,
    model: model,
  );
}

DlnaProfile get _liveTs =>
    DlnaProfiles.select(url: 'http://x/live/u/p/1.ts', finalMime: 'video/mp2t');

void main() {
  group('CastManager.brandTunedProfile', () {
    test('Samsung : video/mpeg + MPEG_TS_HD_NA_ISO (jamais mp2t)', () {
      final DlnaProfile p = CastManager.brandTunedProfile(
        device: _device(name: '[TV] Samsung QE55', manufacturer: 'Samsung'),
        base: _liveTs,
      );
      expect(p.mime, 'video/mpeg');
      expect(p.profileName, 'MPEG_TS_HD_NA_ISO');
      // Le protocolInfo reste live (OP=00, FLAGS streaming 01700000).
      expect(p.buildProtocolInfo(), contains('DLNA.ORG_OP=00'));
      expect(p.buildProtocolInfo(), contains('DLNA.ORG_FLAGS=01700000'));
    });

    test('Panasonic Viera : vnd.dlna.mpeg-tts + AVC_TS_MP_HD_AC3', () {
      final DlnaProfile p = CastManager.brandTunedProfile(
        device: _device(manufacturer: 'Panasonic', model: 'VIERA TX-55'),
        base: _liveTs,
      );
      expect(p.mime, 'video/vnd.dlna.mpeg-tts');
      expect(p.profileName, 'AVC_TS_MP_HD_AC3');
    });

    test('Hisense VIDAA : video/mpeg générique sans PN', () {
      final DlnaProfile p = CastManager.brandTunedProfile(
        device: _device(name: 'Hisense 55A7', manufacturer: 'Hisense'),
        base: _liveTs,
      );
      expect(p.mime, 'video/mpeg');
      expect(p.profileName, isNull);
    });

    test('marque inconnue / LG : profil de base inchangé', () {
      final DlnaProfile p = CastManager.brandTunedProfile(
        device: _device(name: '[LG] webOS TV', manufacturer: 'LG Electronics.'),
        base: _liveTs,
      );
      expect(identical(p, _liveTs) || p.mime == _liveTs.mime, isTrue);
    });

    test('non-TS (mp4) : jamais retouché', () {
      final DlnaProfile mp4 = DlnaProfiles.select(
          url: 'http://x/movie.mp4', finalMime: 'video/mp4');
      final DlnaProfile p = CastManager.brandTunedProfile(
        device: _device(manufacturer: 'Samsung'),
        base: mp4,
      );
      expect(p.mime, mp4.mime);
      expect(p.profileName, mp4.profileName);
    });
  });
}
