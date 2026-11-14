import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:tv_king/features/cast/data/upnp_av_transport.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';

void main() {
  test('DLNA sends valid SetAVTransportURI then Play, Pause and Stop SOAP',
      () async {
    final HttpServer server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final List<String> actions = <String>[];
    String state = 'STOPPED';
    String? setUriBody;
    String? soapHeader;
    server.listen((HttpRequest req) async {
      final String action = (req.headers.value('soapaction') ?? '')
          .split('#')
          .last
          .replaceAll('"', '');
      final String body = await utf8.decoder.bind(req).join();
      actions.add(action);
      if (action == 'SetAVTransportURI') {
        setUriBody = body;
        soapHeader = req.headers.value('soapaction');
      }
      if (action == 'Play') state = 'PLAYING';
      if (action == 'Stop') state = 'STOPPED';
      req.response.headers.contentType =
          ContentType('text', 'xml', charset: 'utf-8');
      req.response.write(
          '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
          '<u:${action}Response xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
          '${action == "GetTransportInfo" ? "<CurrentTransportState>$state</CurrentTransportState>" : ""}'
          '</u:${action}Response></s:Body></s:Envelope>');
      await req.response.close();
    });
    final UpnpAvTransport transport = UpnpAvTransport(CastDevice(
        id: 'test',
        name: 'DLNA Test',
        kind: CastDeviceKind.dlna,
        host: '127.0.0.1',
        port: server.port,
        controlUrl: 'http://127.0.0.1:${server.port}/control'));
    try {
      await transport.playStream(
          streamUrl: 'https://example.com/live.ts?a=1&b=2',
          title: 'A & B <test>');
      await transport.pause();
      await transport.resume();
      await transport.stop();
      expect(actions.indexOf('SetAVTransportURI'),
          lessThan(actions.indexOf('Play')));
      expect(actions, contains('Pause'));
      expect(actions.last, 'Stop');
      expect(soapHeader,
          '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"');
      final XmlDocument xml = XmlDocument.parse(setUriBody!);
      expect(xml.findAllElements('CurrentURI').single.innerText,
          'https://example.com/live.ts?a=1&b=2');
      final XmlDocument didl = XmlDocument.parse(
          xml.findAllElements('CurrentURIMetaData').single.innerText);
      expect(
          didl.descendants
              .whereType<XmlElement>()
              .firstWhere((XmlElement e) => e.name.local == 'title')
              .innerText,
          'A & B <test>');
    } finally {
      await server.close(force: true);
    }
  });
}
