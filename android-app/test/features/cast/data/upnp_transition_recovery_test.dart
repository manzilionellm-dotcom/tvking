// =========================================================
//  upnp_transition_recovery_test.dart — Rattrapage UPnP 701
// =========================================================
//  Terrain LG webOS QNED816QA (2026-07-17) : la TV reste VERROUILLÉE
//  sur le cast précédent et répond « Transition not available »
//  (fault UPnP 701) à SetAVTransportURI. Avant : l'échec faisait
//  passer à la stratégie suivante, qui re-tapait la même TV coincée
//  → 9 échecs de suite, ~90 s perdues, « Ta TV est bloquée ».
//  Désormais playStream DÉBLOQUE (Stop appuyé + attente réelle de
//  libération) et rejoue UNE fois SetAVTransportURI.
//
//  On teste contre un FAUX renderer DLNA (vrai serveur HTTP local,
//  même approche que hls_relay_session_test) qui simule les états
//  et les fautes SOAP de la TV.
// =========================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/upnp_av_transport.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';

/// Renderer DLNA simulé : répond aux actions SOAP AVTransport avec
/// des comportements paramétrables (faute 701, TV muette, etc.).
class _FakeRenderer {
  HttpServer? _server;

  /// Actions SOAP reçues, dans l'ordre (Stop, SetAVTransportURI…).
  final List<String> actions = <String>[];

  /// État courant renvoyé par GetTransportInfo.
  String transportState = 'STOPPED';

  /// Nombre de SetAVTransportURI à refuser avec la faute paramétrée.
  int setUriFailures = 0;

  /// Code/description de la faute SOAP renvoyée sur SetAVTransportURI.
  int faultCode = 701;
  String? faultDescription = 'Transition not available';

  /// TV « muette » : GetTransportInfo répond 500 (état inconnu).
  bool muteTransportInfo = false;

  Future<CastDevice> start() async {
    final HttpServer server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((HttpRequest req) async {
      // L'action vit dans l'en-tête SOAPACTION : "urn:...#Action".
      final String soapAction = req.headers.value('soapaction') ?? '';
      final String action =
          soapAction.split('#').last.replaceAll('"', '').trim();
      await utf8.decoder.bind(req).join(); // draine le corps
      actions.add(action);

      switch (action) {
        case 'GetTransportInfo':
          if (muteTransportInfo) {
            _respond(req, 500, _fault(code: 401, description: 'Invalid'));
          } else {
            _respond(req, 200, _transportInfoResponse(transportState));
          }
        case 'SetAVTransportURI':
          if (setUriFailures > 0) {
            setUriFailures--;
            _respond(req, 500,
                _fault(code: faultCode, description: faultDescription));
          } else {
            transportState = 'STOPPED';
            _respond(req, 200, _okResponse('SetAVTransportURI'));
          }
        case 'Play':
          transportState = 'PLAYING';
          _respond(req, 200, _okResponse('Play'));
        case 'Stop':
          _respond(req, 200, _okResponse('Stop'));
        default:
          _respond(req, 500, _fault(code: 401, description: 'Invalid'));
      }
    });
    return CastDevice(
      id: 'uuid:fake-lg',
      name: '[LG] Renderer Test',
      kind: CastDeviceKind.dlna,
      host: '127.0.0.1',
      port: server.port,
      controlUrl: 'http://127.0.0.1:${server.port}/AVTransport/control',
      manufacturer: 'LG Electronics.',
      model: 'LG TV',
    );
  }

  Future<void> close() async => _server?.close(force: true);

  int countOf(String action) =>
      actions.where((String a) => a == action).length;

  static void _respond(HttpRequest req, int status, String body) {
    req.response.statusCode = status;
    req.response.headers.contentType =
        ContentType('text', 'xml', charset: 'utf-8');
    req.response.write(body);
    req.response.close();
  }

  static String _okResponse(String action) =>
      '<?xml version="1.0"?><s:Envelope '
      'xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
      '<u:${action}Response '
      'xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"/>'
      '</s:Body></s:Envelope>';

  static String _transportInfoResponse(String state) =>
      '<?xml version="1.0"?><s:Envelope '
      'xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
      '<u:GetTransportInfoResponse '
      'xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
      '<CurrentTransportState>$state</CurrentTransportState>'
      '<CurrentTransportStatus>OK</CurrentTransportStatus>'
      '</u:GetTransportInfoResponse></s:Body></s:Envelope>';

  /// Faute UPnP conforme (UPnP DA 1.0 §3.2.2) — description optionnelle
  /// (certaines TVs n'envoient QUE le code).
  static String _fault({required int code, String? description}) =>
      '<?xml version="1.0"?><s:Envelope '
      'xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
      '<s:Fault><faultcode>s:Client</faultcode>'
      '<faultstring>UPnPError</faultstring><detail>'
      '<UPnPError xmlns="urn:schemas-upnp-org:control-1-0">'
      '<errorCode>$code</errorCode>'
      '${description != null ? '<errorDescription>$description</errorDescription>' : ''}'
      '</UPnPError></detail></s:Fault></s:Body></s:Envelope>';
}

void main() {
  group('isTransitionNotAvailable (pur)', () {
    test('reconnaît la description et le code nu', () {
      expect(
        UpnpAvTransport.isTransitionNotAvailable(
            'Exception: UPnP SetAVTransportURI a échoué : '
            'Transition not available'),
        isTrue,
      );
      expect(
        UpnpAvTransport.isTransitionNotAvailable(
            'Exception: UPnP SetAVTransportURI a échoué : code UPnP 701'),
        isTrue,
      );
      expect(
        UpnpAvTransport.isTransitionNotAvailable(
            'Exception: UPnP SetAVTransportURI a échoué : '
            'Resource not found'),
        isFalse,
      );
      expect(
        UpnpAvTransport.isTransitionNotAvailable('TimeoutException'),
        isFalse,
      );
    });
  });

  group('playStream — rattrapage 701 « Transition not available »', () {
    test('701 puis TV libérée → Stop appuyé + 2e SetAVTransportURI → joue',
        () async {
      final _FakeRenderer tv = _FakeRenderer()..setUriFailures = 1;
      final CastDevice device = await tv.start();
      final UpnpAvTransport transport = UpnpAvTransport(device);
      try {
        await transport.playStream(
          streamUrl: 'http://127.0.0.1:1/hls/x.m3u8',
          title: 'Test 701',
        );
        // Deux SetAVTransportURI : le refus 701 puis la 2e chance.
        expect(tv.countOf('SetAVTransportURI'), 2);
        // Le Stop de déblocage est bien parti ENTRE les deux SetURI.
        final int firstSet = tv.actions.indexOf('SetAVTransportURI');
        final int lastSet = tv.actions.lastIndexOf('SetAVTransportURI');
        expect(
          tv.actions
              .sublist(firstSet + 1, lastSet)
              .contains('Stop'),
          isTrue,
          reason: 'Stop appuyé entre le refus et la nouvelle tentative',
        );
        expect(tv.countOf('Play'), 1);
      } finally {
        await tv.close();
      }
    });

    test('701 persistant → une SEULE nouvelle chance puis échec propre',
        () async {
      final _FakeRenderer tv = _FakeRenderer()
        ..setUriFailures = 99
        ..muteTransportInfo = true; // TV muette : pas d'attente longue
      final CastDevice device = await tv.start();
      final UpnpAvTransport transport = UpnpAvTransport(device);
      try {
        await expectLater(
          transport.playStream(
            streamUrl: 'http://127.0.0.1:1/hls/x.m3u8',
            title: 'Test 701 persistant',
          ),
          throwsA(isA<Exception>().having(
            (Exception e) => e.toString().toLowerCase(),
            'message',
            contains('transition not available'),
          )),
        );
        expect(tv.countOf('SetAVTransportURI'), 2,
            reason: 'exactement UNE nouvelle chance — pas de boucle');
        expect(tv.countOf('Play'), 0);
      } finally {
        await tv.close();
      }
    });

    test('faute 701 SANS description (code nu) → rattrapage quand même',
        () async {
      final _FakeRenderer tv = _FakeRenderer()
        ..setUriFailures = 1
        ..faultDescription = null;
      final CastDevice device = await tv.start();
      final UpnpAvTransport transport = UpnpAvTransport(device);
      try {
        await transport.playStream(
          streamUrl: 'http://127.0.0.1:1/hls/x.m3u8',
          title: 'Test 701 code nu',
        );
        expect(tv.countOf('SetAVTransportURI'), 2);
      } finally {
        await tv.close();
      }
    });

    test('autre faute (716 Resource not found) → PAS de nouvelle chance',
        () async {
      final _FakeRenderer tv = _FakeRenderer()
        ..setUriFailures = 1
        ..faultCode = 716
        ..faultDescription = 'Resource not found';
      final CastDevice device = await tv.start();
      final UpnpAvTransport transport = UpnpAvTransport(device);
      try {
        await expectLater(
          transport.playStream(
            streamUrl: 'http://127.0.0.1:1/hls/x.m3u8',
            title: 'Test 716',
          ),
          throwsA(isA<Exception>().having(
            (Exception e) => e.toString().toLowerCase(),
            'message',
            contains('resource not found'),
          )),
        );
        expect(tv.countOf('SetAVTransportURI'), 1,
            reason: 'le rattrapage est RÉSERVÉ au 701 — un refus de '
                'DIDL doit passer à la stratégie suivante, comme avant');
      } finally {
        await tv.close();
      }
    });
  });
}
