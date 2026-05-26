// =========================================================
//  cast_transport.dart — Interface abstraite "envoyer un flux"
// =========================================================
//  Chaque protocole de cast (DLNA, Chromecast, Roku, fallback
//  web...) implémente cette interface. Le CastManager parle
//  uniquement à `CastTransport` et délègue le détail du
//  protocole au bon implémentateur via une factory basée sur
//  `CastDevice.kind`.
//
//  Cette indirection permet d'ajouter un nouveau protocole en
//  écrivant juste un fichier "*_transport.dart" + un cas dans
//  la factory — sans toucher au reste de l'app.
// =========================================================

import '../domain/cast_device.dart';
import 'roku_ecp_transport.dart';
import 'upnp_av_transport.dart';
import 'web_browser_transport.dart';

abstract class CastTransport {
  /// Envoie [streamUrl] au récepteur et démarre la lecture.
  /// [title] est affiché dans l'OSD du récepteur quand celui-ci
  /// gère un titre (DLNA, Chromecast). Roku ne l'affiche pas
  /// toujours, ignore en silence si non supporté.
  Future<void> playStream({
    required String streamUrl,
    String title = '7 MOTION',
  });

  Future<void> pause();
  Future<void> resume();
  Future<void> stop();

  /// Construit l'implémentation appropriée pour un device donné.
  /// Le `CastManager` appelle cette factory dès qu'il a besoin de
  /// piloter un récepteur. Aucune ressource n'est ouverte ici —
  /// les connexions réseau sont établies au premier appel à
  /// [playStream].
  static CastTransport forDevice(CastDevice device) {
    switch (device.kind) {
      case CastDeviceKind.dlna:
        return UpnpAvTransport(device);
      case CastDeviceKind.roku:
        return RokuEcpTransport(device);
      case CastDeviceKind.chromecast:
      case CastDeviceKind.googleCast:
        // Sans Google Cast SDK natif (refusé : trop lourd, +~5 MB APK),
        // on bascule TOUT Chromecast sur le transport navigateur web :
        //   - Google TV / Android TV ont un Chrome intégré → marche
        //   - Chromecast dongle pur sans browser → ne marche pas, mais
        //     au moins pas d'erreur cryptique ; l'utilisateur peut
        //     ouvrir l'URL sur sa TV manuellement via le sheet QR.
        // Le picker ouvre le sheet QR (showWebCastSetup) au tap sur
        // un Chromecast pour guider l'utilisateur dès la première fois.
        return WebBrowserTransport(device);
      case CastDeviceKind.webBrowser:
        return WebBrowserTransport(device);
    }
  }
}
