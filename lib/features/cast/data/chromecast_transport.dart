// =========================================================
//  chromecast_transport.dart — Cast vers Chromecast / Google TV
// =========================================================
//  Stub — implémentation complète à venir.
//  Le protocole Chromecast CASTV2 est un binaire protobuf sur
//  TLS mutuel. La discovery se fait en mDNS sur
//  `_googlecast._tcp.local`.
//
//  Pour l'instant : lève une exception explicite si on tente de
//  caster. L'utilisateur sera renvoyé vers le fallback navigateur
//  ou DLNA, qui couvrent la plupart des TVs Google.
// =========================================================

import '../domain/cast_device.dart';
import 'cast_transport.dart';

class ChromecastTransport implements CastTransport {
  ChromecastTransport(this.device);

  final CastDevice device;

  @override
  Future<void> playStream({
    required String streamUrl,
    String title = '7 MOTION',
  }) {
    throw Exception(
      'Cast Chromecast pas encore implémenté. Utilise DLNA ou le '
      'fallback navigateur web en attendant.',
    );
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}
}
