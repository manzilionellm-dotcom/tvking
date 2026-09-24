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
import 'multicast_lock.dart';
import 'roku_ecp_transport.dart';

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

    // ID racine (UUID) déjà émis. Un même appareil envoie souvent
    // 3-5 réponses SSDP (une par service UPnP qu'il expose) avec
    // des USN différents mais le MÊME UUID racine — par exemple :
    //   uuid:abc::upnp:rootdevice
    //   uuid:abc::urn:schemas-upnp-org:device:MediaRenderer:1
    //   uuid:abc::urn:schemas-upnp-org:service:AVTransport:1
    // → on dédupe sur le préfixe "uuid:abc" pour ne lister la TV
    //   qu'UNE seule fois.
    final Set<String> seenRootIds = <String>{};
    final List<RawDatagramSocket> sockets = <RawDatagramSocket>[];

    // Comme pour mDNS : sans MulticastLock, Android filtre les
    // réponses SSDP (239.255.255.250) et aucune TV DLNA n'est trouvée.
    // Relâché dans le `finally`.
    await MulticastLock.instance.acquire();

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
        _handleResponse(dg, seenRootIds, controller);
      });

      // Envoie les M-SEARCH pour MediaRenderer + AVTransport (DLNA),
      // pour roku:ecp (TVs / dongles Roku) et "ssdp:all" comme filet
      // de sécurité (certains devices ne répondent qu'à ssdp:all).
      final List<String> targets = <String>[
        'urn:schemas-upnp-org:device:MediaRenderer:1',
        'urn:schemas-upnp-org:service:AVTransport:1',
        'roku:ecp',
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
      await MulticastLock.instance.release();
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
    Set<String> seenRootIds,
    StreamController<CastDevice> controller,
  ) async {
    try {
      final String text = String.fromCharCodes(dg.data);
      final Map<String, String> headers = _parseHeaders(text);
      final String? location = headers['LOCATION'];
      final String? usn = headers['USN'];
      final String? st = headers['ST'];
      if (location == null || usn == null) return;

      // Extrait l'UUID racine : "uuid:abc::urn:..." → "uuid:abc"
      // ou "uuid:abc" si pas de "::"
      final int sep = usn.indexOf('::');
      final String rootId = sep > 0 ? usn.substring(0, sep) : usn;
      if (seenRootIds.contains(rootId)) return;
      // IMPORTANT : on NE marque PAS rootId comme "seen" maintenant.
      // Une TV LG webOS annonce 5+ services UPnP par multicast SSDP,
      // chacun avec un LOCATION URL différent qui pointe vers une
      // description XML potentiellement différente. Pour la TV de
      // l'utilisateur, c'était la description du service rootdevice
      // qui arrivait en 1er — SANS AVTransport — donc on rejetait
      // mais on marquait quand même rootId comme vu → les autres 4
      // annonces (qui contenaient AVTransport) étaient skip.
      //
      // Fix : on ne marque seen QU'APRÈS avoir confirmé qu'on a un
      // device EXPLOITABLE (avec AVTransport pour DLNA, ou Roku
      // valide). Si la 1ère annonce ne donne rien, les autres ont
      // leur chance.

      // ----- Branche Roku -----
      // Roku répond avec ST = "roku:ecp" et LOCATION pointant vers
      // http://<ip>:8060/. Pas de descripteur UPnP — on interroge
      // directement /query/device-info pour le nom.
      if ((st != null && st.contains('roku:ecp')) ||
          location.contains(':8060')) {
        final CastDevice? device =
            await _parseRokuDevice(location, rootId);
        if (device == null) return;
        seenRootIds.add(rootId);
        if (!controller.isClosed) controller.add(device);
        return;
      }

      // ----- Branche DLNA / UPnP standard -----
      // Télécharge le descripteur UPnP
      final http.Response resp = await http
          .get(Uri.parse(location))
          .timeout(const Duration(seconds: 3));
      if (resp.statusCode != 200) return;

      final CastDevice? device =
          _parseDeviceDescriptor(resp.body, location, rootId);
      if (device == null) return;
      seenRootIds.add(rootId);
      if (!controller.isClosed) controller.add(device);
    } catch (e) {
      if (kDebugMode) debugPrint('[SSDP] parse error: $e');
    }
  }

  /// Construit un CastDevice à partir d'une réponse SSDP Roku.
  /// Roku n'a pas de descripteur UPnP : on interroge son endpoint
  /// `/query/device-info` (XML simple) pour récupérer le nom de
  /// l'appareil et son modèle.
  Future<CastDevice?> _parseRokuDevice(
    String location,
    String rootId,
  ) async {
    try {
      final Uri loc = Uri.parse(location);
      final Map<String, String> info =
          await RokuEcpTransport.queryDeviceInfo(loc.host);

      final String friendly = info['user-device-name'] ??
          info['friendly-device-name'] ??
          info['default-device-name'] ??
          'Roku';
      final String? model =
          info['model-name'] ?? info['model-number'];

      return CastDevice(
        id: rootId,
        name: friendly,
        kind: CastDeviceKind.roku,
        host: loc.host,
        port: loc.port == 0 ? 8060 : loc.port,
        controlUrl: 'http://${loc.host}:${loc.port == 0 ? 8060 : loc.port}',
        manufacturer: 'Roku',
        model: model,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[SSDP] Roku parse error: $e');
      return null;
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
