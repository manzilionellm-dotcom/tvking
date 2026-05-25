// =========================================================
//  upnp_av_transport.dart — Client SOAP pour AVTransport:1
// =========================================================
//  Envoie les commandes UPnP A/V Control Point qui font tourner
//  les MediaRenderers DLNA :
//    - SetAVTransportURI(uri, metadata)  → choisir le flux
//    - Play                              → lecture
//    - Pause                             → pause
//    - Stop                              → arrêt + libère le renderer
//
//  Les requêtes SOAP sont des POST HTTP avec un body XML très
//  spécifique. Le header `SOAPAction` doit nommer l'opération.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/cast_device.dart';
import 'cast_transport.dart';

class UpnpAvTransport implements CastTransport {
  UpnpAvTransport(this.device);

  final CastDevice device;

  static const String _kService = 'urn:schemas-upnp-org:service:AVTransport:1';

  /// Envoie un flux au récepteur et démarre la lecture.
  @override
  Future<void> playStream({
    required String streamUrl,
    String title = '7 MOTION',
  }) async {
    final String metadata = _buildDidlMetadata(streamUrl, title);
    await _soapCall(
      action: 'SetAVTransportURI',
      body: '''
        <InstanceID>0</InstanceID>
        <CurrentURI>${_escape(streamUrl)}</CurrentURI>
        <CurrentURIMetaData>${_escape(metadata)}</CurrentURIMetaData>
      ''',
    );
    // Petit délai pour laisser le device charger l'URI
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _soapCall(
      action: 'Play',
      body: '''
        <InstanceID>0</InstanceID>
        <Speed>1</Speed>
      ''',
    );
  }

  @override
  Future<void> pause() => _soapCall(
        action: 'Pause',
        body: '<InstanceID>0</InstanceID>',
      );

  @override
  Future<void> resume() => _soapCall(
        action: 'Play',
        body: '''
          <InstanceID>0</InstanceID>
          <Speed>1</Speed>
        ''',
      );

  @override
  Future<void> stop() => _soapCall(
        action: 'Stop',
        body: '<InstanceID>0</InstanceID>',
      );

  // ----- Internes -----

  Future<void> _soapCall({
    required String action,
    required String body,
  }) async {
    final String envelope = '''
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
            s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:$action xmlns:u="$_kService">
      $body
    </u:$action>
  </s:Body>
</s:Envelope>'''.trim();

    final http.Response resp = await http.post(
      Uri.parse(device.controlUrl),
      headers: <String, String>{
        'Content-Type': 'text/xml; charset="utf-8"',
        'SOAPAction': '"$_kService#$action"',
      },
      body: envelope,
    ).timeout(const Duration(seconds: 5));

    if (resp.statusCode != 200) {
      if (kDebugMode) {
        debugPrint('[UPnP] $action → HTTP ${resp.statusCode}\n${resp.body}');
      }
      throw Exception(
        'UPnP $action a échoué (HTTP ${resp.statusCode}). Le récepteur a peut-être refusé.',
      );
    }
  }

  /// Construit un bloc de métadonnées DIDL-Lite que les
  /// récepteurs DLNA attendent. Sans ça beaucoup refusent
  /// de jouer le flux.
  String _buildDidlMetadata(String url, String title) {
    return '''
<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"
           xmlns:dc="http://purl.org/dc/elements/1.1/"
           xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
  <item id="1" parentID="0" restricted="1">
    <dc:title>${_escape(title)}</dc:title>
    <upnp:class>object.item.videoItem</upnp:class>
    <res protocolInfo="http-get:*:video/mp2t:*">${_escape(url)}</res>
  </item>
</DIDL-Lite>''';
  }

  String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
