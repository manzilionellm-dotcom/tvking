// =========================================================
//  web_browser_transport.dart — Fallback universel "navigateur"
// =========================================================
//  Concrètement : on démarre `LocalCastServer` qui sert une page
//  HTML5 <video> sur http://<ip-du-phone>:<port>/. L'utilisateur
//  ouvre cette URL sur sa TV (en scannant un QR code, ou en
//  tapant l'URL dans le navigateur de sa TV). À chaque chaîne
//  jouée depuis le téléphone, la page TV met à jour son flux
//  automatiquement (polling de /current toutes les 2s).
//
//  Couverture : N'IMPORTE QUELLE TV avec un navigateur web —
//  Google TV, Android TV, Samsung Tizen, LG WebOS, Vizio, Hisense,
//  vieilles Smart TVs, écrans connectés, etc. C'est le filet
//  de sécurité ultime quand ni DLNA, ni Chromecast, ni Roku ne
//  marchent.
// =========================================================

import '../domain/cast_device.dart';
import 'cast_transport.dart';
import 'local_cast_server.dart';

class WebBrowserTransport implements CastTransport {
  WebBrowserTransport(this.device);

  final CastDevice device;

  @override
  Future<void> playStream({
    required String streamUrl,
    String title = 'BLACK7 ROYAL',
    String? imageUrl,
  }) async {
    // Le serveur est déjà démarré par la sélection du device. Ici on
    // se contente de pousser la nouvelle URL — la TV la reprendra
    // sous 2s via son polling.
    //
    // Phase 1+/G1 : `imageUrl` (logo de chaine) n'est pas encore
    // affiche sur la page HTML5 du LocalCastServer. Backlog dedie
    // (signature `setCurrent` a etendre + affichage cote HTML page).
    // ignore: unused_local_variable
    final _ = imageUrl;
    await LocalCastServer.instance.start();
    LocalCastServer.instance.setCurrent(url: streamUrl, title: title);
  }

  @override
  Future<void> pause() async {
    // Pas de pause côté serveur — la TV gère via ses propres contrôles
    // (le tag <video> a `controls` activé).
  }

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {
    LocalCastServer.instance.setCurrent(url: '', title: '');
  }
}
