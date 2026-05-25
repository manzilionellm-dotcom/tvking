// =========================================================
//  web_browser_transport.dart — Fallback universel via navigateur
// =========================================================
//  Stub — implémentation complète à venir.
//  Idée : l'app héberge un mini-serveur HTTP local qui sert
//  une page HTML5 <video>. L'utilisateur scanne un QR code
//  avec sa TV (ou tape l'URL dans le navigateur de la TV) et
//  la chaîne joue. Marche sur N'IMPORTE QUELLE TV avec un
//  navigateur web — Google TV, Samsung Tizen, LG WebOS, vieilles
//  Smart TVs...
// =========================================================

import '../domain/cast_device.dart';
import 'cast_transport.dart';

class WebBrowserTransport implements CastTransport {
  WebBrowserTransport(this.device);

  final CastDevice device;

  @override
  Future<void> playStream({
    required String streamUrl,
    String title = 'TV King',
  }) {
    throw Exception(
      'Fallback navigateur pas encore implémenté.',
    );
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}
}
