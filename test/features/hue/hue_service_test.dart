// =========================================================
//  hue_service_test.dart — Philips Hue : les briques pures
// =========================================================
//  Aucune ampoule ni réseau ici : on teste le PARSING (réponse SSDP du
//  pont, discovery.meethue.com, saisie IP, réponse d'association) et la
//  RESTAURATION (le corps JSON qui remet chaque lampe exactement comme
//  avant la scène) — c'est là que se jouent les « lumières cassées
//  après un film ».
//
//  NON VÉRIFIABLE EN CI (pont Hue réel requis) :
//   • SSDP + MulticastLock sur Firestick (réponses UDP 239.255.255.250)
//   • GET https://discovery.meethue.com depuis le LAN du client
//   • POST /api + bouton physique → username
//   • CLIP v1 HTTP/HTTPS locale (groupe 0, restauration par lampe)
//   • cinemaStart teinté par l'affiche pendant une VOD
//  Procédure box : Réglages → Image et lumière → Rechercher (ou saisir
//  l'IP du pont dans l'app Hue) → Associer (bouton du pont) → Test 4 s.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/hue/data/hue_service.dart';

void main() {
  group('parseSsdpForBridgeIp', () {
    test('réponse typique du pont (hue-bridgeid) → IP extraite', () {
      const String resp = 'HTTP/1.1 200 OK\r\n'
          'HOST: 239.255.255.250:1900\r\n'
          'EXT:\r\n'
          'CACHE-CONTROL: max-age=100\r\n'
          'LOCATION: http://192.168.1.34:80/description.xml\r\n'
          'SERVER: Hue/1.0 UPnP/1.0 IpBridge/1.56.0\r\n'
          'hue-bridgeid: ECB5FAFFFE00AA00\r\n'
          'ST: urn:schemas-upnp-org:device:Basic:1\r\n\r\n';
      expect(HueService.parseSsdpForBridgeIp(resp), '192.168.1.34');
    });

    test('réponse d\'un autre appareil (TV DLNA…) → null', () {
      const String resp = 'HTTP/1.1 200 OK\r\n'
          'LOCATION: http://192.168.1.50:7676/smp_2_\r\n'
          'SERVER: Samsung UPnP SDK/1.0\r\n'
          'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n';
      expect(HueService.parseSsdpForBridgeIp(resp), isNull);
    });

    test('casse des en-têtes et schéma HTTPS / HTTP://', () {
      const String resp = 'HTTP/1.1 200 OK\r\n'
          'Location: HTTPS://10.0.0.5/description.xml\r\n'
          'HUE-BRIDGEID: AA\r\n\r\n';
      expect(HueService.parseSsdpForBridgeIp(resp), '10.0.0.5');
    });

    test('sans signature Hue → null même avec LOCATION', () {
      const String resp = 'HTTP/1.1 200 OK\r\n'
          'LOCATION: http://192.168.1.1/description.xml\r\n'
          'SERVER: router/1.0\r\n\r\n';
      expect(HueService.parseSsdpForBridgeIp(resp), isNull);
    });
  });

  group('parseCloudDiscovery / normalizeBridgeIp / privé', () {
    test('réponse officielle meethue → 1re IP privée', () {
      const String body =
          '[{"id":"001788fffe2c6c32","internalipaddress":"192.168.1.2","port":80}]';
      expect(HueService.parseCloudDiscovery(body), '192.168.1.2');
    });

    test('IP publique ignorée (jamais de pont Hue sur le WAN)', () {
      const String body =
          '[{"id":"x","internalipaddress":"8.8.8.8","port":80}]';
      expect(HueService.parseCloudDiscovery(body), isNull);
    });

    test('JSON cassé / liste vide → null, jamais d\'exception', () {
      expect(HueService.parseCloudDiscovery('[]'), isNull);
      expect(HueService.parseCloudDiscovery('{}'), isNull);
      expect(HueService.parseCloudDiscovery('pas json'), isNull);
    });

    test('plusieurs ponts → première IP privée', () {
      const String body =
          '[{"id":"a","internalipaddress":"1.2.3.4"},'
          '{"id":"b","internalipaddress":"10.0.0.8"}]';
      expect(HueService.parseCloudDiscovery(body), '10.0.0.8');
    });

    test('normalizeBridgeIp accepte URL / port / espaces', () {
      expect(HueService.normalizeBridgeIp('  http://192.168.1.34:80/  '),
          '192.168.1.34');
      expect(HueService.normalizeBridgeIp('192.168.1.34'), '192.168.1.34');
      expect(HueService.normalizeBridgeIp('pas-une-ip'), isNull);
      expect(HueService.normalizeBridgeIp('300.1.1.1'), isNull);
    });

    test('isPrivateIpv4 : RFC1918 + link-local seulement', () {
      expect(HueService.isPrivateIpv4('192.168.0.1'), isTrue);
      expect(HueService.isPrivateIpv4('10.1.2.3'), isTrue);
      expect(HueService.isPrivateIpv4('172.16.0.1'), isTrue);
      expect(HueService.isPrivateIpv4('172.31.255.255'), isTrue);
      expect(HueService.isPrivateIpv4('169.254.1.1'), isTrue);
      expect(HueService.isPrivateIpv4('172.15.0.1'), isFalse);
      expect(HueService.isPrivateIpv4('8.8.8.8'), isFalse);
      expect(HueService.isPrivateIpv4('not-ip'), isFalse);
    });

    test('parseHueConfigLooksLikeBridge', () {
      expect(
          HueService.parseHueConfigLooksLikeBridge(
              '{"name":"Philips hue","bridgeid":"ECB5FAFFFE00AA00"}'),
          isTrue);
      expect(HueService.parseHueConfigLooksLikeBridge('{"swversion":"1"}'),
          isFalse);
      expect(HueService.parseHueConfigLooksLikeBridge('[]'), isFalse);
    });
  });

  group('parsePairResponse', () {
    test('succès → clé d\'app extraite', () {
      const String body =
          '[{"success":{"username":"aBcDeF123456"}}]';
      final ({HuePairResult result, String? appKey}) r =
          HueService.parsePairResponse(body);
      expect(r.result, HuePairResult.success);
      expect(r.appKey, 'aBcDeF123456');
    });

    test('erreur 101 = bouton pas encore pressé (on re-tente)', () {
      const String body =
          '[{"error":{"type":101,"address":"","description":"link button not pressed"}}]';
      expect(HueService.parsePairResponse(body).result,
          HuePairResult.linkButtonNotPressed);
    });

    test('réponse inattendue / JSON cassé → error, jamais d\'exception', () {
      expect(HueService.parsePairResponse('{}').result, HuePairResult.error);
      expect(HueService.parsePairResponse('pas du json').result,
          HuePairResult.error);
      expect(HueService.parsePairResponse('[]').result, HuePairResult.error);
    });
  });

  group('HueLightState — restauration exacte', () {
    test('lampe éteinte → {"on":false} SEULEMENT (pas de flash)', () {
      const HueLightState s =
          HueLightState(id: '1', on: false, bri: 200, hue: 8000, sat: 140);
      expect(s.restoreBody(), <String, Object?>{'on': false});
    });

    test('lampe couleur (colormode hs) → on/bri/hue/sat', () {
      const HueLightState s = HueLightState(
          id: '2', on: true, bri: 180, hue: 8000, sat: 140, colormode: 'hs');
      final Map<String, Object?> body = s.restoreBody(transitionDs: 20);
      expect(body['on'], true);
      expect(body['bri'], 180);
      expect(body['hue'], 8000);
      expect(body['sat'], 140);
      expect(body.containsKey('ct'), isFalse);
    });

    test('lampe blanc chaud (colormode ct) → on/bri/ct, pas de hue/sat', () {
      const HueLightState s = HueLightState(
          id: '3', on: true, bri: 254, hue: 8000, sat: 140, ct: 366,
          colormode: 'ct');
      final Map<String, Object?> body = s.restoreBody();
      expect(body['ct'], 366);
      expect(body.containsKey('hue'), isFalse);
      expect(body.containsKey('sat'), isFalse);
    });

    test('fromLightJson lit l\'état du GET /lights', () {
      final HueLightState? s = HueLightState.fromLightJson('7',
          <String, dynamic>{
            'state': <String, dynamic>{
              'on': true,
              'bri': 120,
              'hue': 3000,
              'sat': 200,
              'ct': 300,
              'colormode': 'hs',
            },
            'name': 'Salon',
          });
      expect(s, isNotNull);
      expect(s!.on, isTrue);
      expect(s.bri, 120);
      expect(s.colormode, 'hs');
    });

    test('lampe sans bloc state (accessoire, capteur) → null', () {
      expect(
          HueLightState.fromLightJson('9', <String, dynamic>{'name': 'x'}),
          isNull);
    });
  });

  group('immersion couleur (rgbToHue / dominantFromRgba)', () {
    test('rouge pur → teinte ~0', () {
      final r = HueService.rgbToHue(255, 0, 0);
      expect(r.hue, lessThan(2000));
      expect(r.sat, 254);
    });
    test('bleu pur → teinte vers 2/3 du cercle', () {
      final b = HueService.rgbToHue(0, 0, 255);
      expect(b.hue, closeTo(65535 * 240 / 360, 2000));
      expect(b.sat, 254);
    });
    test('gris → saturation nulle', () {
      expect(HueService.rgbToHue(128, 128, 128).sat, 0);
    });
    test('dominante ignore le noir et le gris, garde le vif', () {
      // 1 px noir, 1 px gris, 1 px bleu vif → doit ressortir bleu.
      final rgba = <int>[
        0, 0, 0, 255, // noir (écarté)
        130, 130, 130, 255, // gris (écarté)
        20, 40, 240, 255, // bleu vif (gardé)
      ];
      final d = HueService.dominantFromRgba(rgba, stride: 1);
      expect(d, isNotNull);
      expect(d!.hue, closeTo(65535 * 230 / 360, 6000));
    });
    test('image entièrement terne → null (repli braise)', () {
      final rgba = <int>[10, 10, 10, 255, 12, 12, 12, 255];
      expect(HueService.dominantFromRgba(rgba, stride: 1), isNull);
    });
  });

}
