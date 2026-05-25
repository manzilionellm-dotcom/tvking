// =========================================================
//  ssdp_discovery.dart — Découverte UPnP / DLNA
// =========================================================
//  Implémentation pure Dart du protocole SSDP (Simple Service
//  Discovery Protocol) — pas de dépendance native.
//
//  Fonctionnement :
//    1. On envoie un M-SEARCH UDP broadcast sur 239.255.255.250:1900
//    2. Les MediaRenderers du LAN répondent en HTTP-like avec
//       un en-tête LOCATION qui pointe vers leur descripteur XML
//    3. On télécharge le descripteur via HTTP
//    4. On en extrait : nom convivial + URL du service AVTransport
//    5. On émet un `CastDevice` complet
//
//  Marche sur :
//    - Fire TV avec AirReceiver / BubbleUPnP installé
//    - Smart TVs récentes (Samsung, LG, Sony, Philips...)
//    - Box DLNA (Apple TV via AirReceiver, etc.)
//    - Tout récepteur UPnP-AV standard
//
//  NE MARCHE PAS sur :
//    - Chromecast natif (utilise Google Cast SDK, pas DLNA)
//    - AirPlay (protocole propriétaire Apple)
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../domain/cast_device.dart';

class SsdpDiscovery {
  SsdpDiscovery._();
  static final SsdpDiscovery instance = SsdpDiscovery._();

  static const String _kMulticastIp = '239.255.255.250';
  static const int _kSsdpPort = 1900;

  /// Lance une découverte de durée [timeout] et émet un CastDevice
  /// à chaque récepteur découvert. Le stream se ferme à la fin.
  Stream<CastDevice> discover({
    Duration timeout = const Duration(seconds: 4),
  }) async* {
    final StreamController<CastDevice> controller =
        StreamController<CastDevice>();

    // IDs déjà émis pour éviter les doublons (un device répond
    // souvent plusieurs fois aux M-SEARCH).
    final Set<String> seenIds = <String>{};
    final List<RawDatagramSocket> sockets = <RawDatagramSocket>[];

    try {
      // On bind sur 0.0.0.0:0 (port aléatoire), pas en multicast bind,
      // pour pouvoir recevoir les réponses unicast vers nous.
      final RawDatagramSocket socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      sockets.add(socket);
      socket.broadcastEnabled = true;

      // Listen sur les réponses
      socket.listen((RawSocketEvent event) {
        if (event != RawSocketEvent.read) return;
        final Datagram? dg = socket.receive();
        if (dg == null) return;
        _handleResponse(dg, seenIds, controller);
      });

      // Envoie les M-SEARCH pour MediaRenderer ET pour AVTransport
      final List<String> targets = <String>[
        'urn:schemas-upnp-org:device:MediaRenderer:1',
        'urn:schemas-upnp-org:service:AVTransport:1',
        'ssdp:all',
      ];
      for (final String st in targets) {
        final String msg = _buildSearchMessage(st);
        socket.send(
          msg.codeUnits,
          InternetAddress(_kMulticastIp),
          _kSsdpPort,
        );
      }

      // Yield les devices jusqu'à expiration
      final Future<void> deadline = Future<void>.delayed(timeout);
      bool done = false;
      deadline.then((_) => done = true);

      await for (final CastDevice device in controller.stream) {
        if (done) break;
        yield device;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[SSDP] error: $e');
    } finally {
      for (final RawDatagramSocket s in sockets) {
        s.close();
      }
      if (!controller.isClosed) await controller.close();
    }
  }

  String _buildSearchMessage(String searchTarget) {
    return 'M-SEARCH * HTTP/1.1\r\n'
        'HOST: $_kMulticastIp:$_kSsdpPort\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 3\r\n'
        'ST: $searchTarget\r\n'
        '\r\n';
  }

  Future<void> _handleResponse(
    Datagram dg,
    Set<String> seenIds,
    StreamController<CastDevice> controller,
  ) async {
    try {
      final String text = String.fromCharCodes(dg.data);
      final Map<String, String> headers = _parseHeaders(text);
      final String? location = headers['LOCATION'];
      final String? usn = headers['USN'];
      if (location == null || usn == null) return;
      if (seenIds.contains(usn)) return;
      seenIds.add(usn);

      // Télécharge le descripteur UPnP
      final http.Response resp = await http
          .get(Uri.parse(location))
          .timeout(const Duration(seconds: 3));
      if (resp.statusCode != 200) return;

      final CastDevice? device =
          _parseDeviceDescriptor(resp.body, location, usn);
      if (device == null) return;
      if (!controller.isClosed) controller.add(device);
    } catch (e) {
      if (kDebugMode) debugPrint('[SSDP] parse error: $e');
    }
  }

  Map<String, String> _parseHeaders(String text) {
    final Map<String, String> result = <String, String>{};
    final List<String> lines = text.split(RegExp(r'\r?\n'));
    for (final String line in lines) {
      final int colon = line.indexOf(':');
      if (colon <= 0) continue;
      final String key = line.substring(0, colon).trim().toUpperCase();
      final String value = line.substring(colon + 1).trim();
      result[key] = value;
    }
    return result;
  }

  /// Parse le XML UPnP du descripteur et extrait friendlyName +
  /// l'URL absolue du service AVTransport.
  CastDevice? _parseDeviceDescriptor(
    String body,
    String locationUrl,
    String usn,
  ) {
    try {
      final XmlDocument doc = XmlDocument.parse(body);
      final Iterable<XmlElement> deviceElements =
          doc.findAllElements('device');
      if (deviceElements.isEmpty) return null;
      final XmlElement device = deviceElements.first;

      final String name =
          _childText(device, 'friendlyName') ?? 'Récepteur DLNA';
      final String? manufacturer = _childText(device, 'manufacturer');
      final String? model = _childText(device, 'modelName');

      // Cherche le service AVTransport
      String? avTransportControlUrl;
      for (final XmlElement svc in doc.findAllElements('service')) {
        final String? type = _childText(svc, 'serviceType');
        if (type != null && type.contains('AVTransport')) {
          avTransportControlUrl = _childText(svc, 'controlURL');
          break;
        }
      }
      if (avTransportControlUrl == null) return null;

      final Uri loc = Uri.parse(locationUrl);
      final Uri controlUrl =
          loc.resolve(avTransportControlUrl);

      return CastDevice(
        id: usn,
        name: name,
        kind: CastDeviceKind.dlna,
        host: controlUrl.host,
        port: controlUrl.port,
        controlUrl: controlUrl.toString(),
        manufacturer: manufacturer,
        model: model,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[SSDP] descriptor parse: $e');
      return null;
    }
  }

  String? _childText(XmlElement parent, String name) {
    final Iterable<XmlElement> match = parent.findElements(name);
    if (match.isEmpty) return null;
    return match.first.innerText.trim();
  }
}
