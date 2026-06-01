// =========================================================
//  google_cast_transport.dart — Cast vers Chromecast / Google TV
// =========================================================
//  Remplace l'ancien `chromecast_transport.dart` stub.
//  Délègue tout au `GoogleCastApi` (qui parle au SDK natif).
//
//  Modèle d'utilisation par le CastManager :
//    1. forDevice(device) → instancie cette classe
//    2. playStream(...) → vérifie isCastAvailable + hasActiveSession :
//       - Si session déjà active → loadMedia direct
//       - Sinon → showRoutePicker (l'utilisateur tape sa TV dans
//         le dialog natif Cast), attendre ~500ms, puis loadMedia
//    3. play/pause/stop → délégation directe
//
//  Note IMPORTANTE : le SDK Cast natif gère LUI-MÊME la discovery
//  des Chromecasts / Google TV. Notre mDNS Discovery dans
//  `mdns_discovery.dart` reste utile pour AFFICHER les devices
//  dans notre picker custom, mais la VRAIE session passe par le
//  SDK qui peut découvrir des récepteurs que mDNS rate (cas du
//  multi-VLAN avec Bonjour gateway).
// =========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/cast_device.dart';
import 'cast_transport.dart';
import 'google_cast_api.dart';

class GoogleCastTransport implements CastTransport {
  GoogleCastTransport(this.device);

  final CastDevice device;

  @override
  Future<void> playStream({
    required String streamUrl,
    String title = '7 MOTION',
    String? imageUrl,
  }) async {
    final GoogleCastApi api = GoogleCastApi.instance;

    // 1) Le SDK Cast est-il disponible sur ce device ?
    //    Faux sur les phones sans Google Play Services (Huawei récents,
    //    custom ROMs). Dans ce cas on lève — le CastManager retombera
    //    sur le fallback navigateur ou affichera un message friendly.
    final bool available = await api.isCastAvailable();
    if (!available) {
      throw Exception(
        'Google Cast indisponible sur ce téléphone — '
        'Google Play Services requis.',
      );
    }

    // 2) Y a-t-il déjà une session active ? (l'utilisateur a déjà
    //    connecté sa TV via le dialog Cast lors d'un cast précédent)
    bool hasSession = await api.hasActiveSession();

    // 3) Pas de session → on demande au SDK d'ouvrir SON dialog natif.
    //    L'utilisateur sélectionne sa TV. Le SDK gère la négociation,
    //    le pairing, etc. — c'est exactement le flow Netflix / YouTube.
    if (!hasSession) {
      await api.showRoutePicker();
      // Le dialog est asynchrone côté utilisateur (il doit tap sa TV).
      // On poll hasActiveSession pendant 30s max — au-delà on suppose
      // que l'utilisateur a annulé.
      final DateTime deadline =
          DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (await api.hasActiveSession()) {
          hasSession = true;
          break;
        }
      }
      if (!hasSession) {
        throw Exception('Aucune TV sélectionnée.');
      }
    }

    // 4) Session OK — on pousse le flux.
    //    Le SDK Cast natif gère le MediaInfo, le MediaLoadOptions,
    //    le contentType, la metadata… on lui passe juste l'URL +
    //    titre + MIME deviné depuis l'URL.
    //    Phase 1+/G1 : on transmet aussi `imageUrl` (logo de la
    //    chaine) — la TV l'affiche en idle et en overlay pendant la
    //    lecture. Sans ca le recepteur tombait sur son placeholder
    //    generique meme quand on connaissait le logo.
    final String mime = _guessMime(streamUrl);
    final bool loaded = await api.loadMedia(
      streamUrl: streamUrl,
      title: title,
      mime: mime,
      imageUrl: imageUrl,
    );
    if (!loaded) {
      throw Exception('La TV a refusé le flux.');
    }
  }

  @override
  Future<void> pause() => GoogleCastApi.instance.pause();

  @override
  Future<void> resume() => GoogleCastApi.instance.play();

  @override
  Future<void> stop() async {
    try {
      await GoogleCastApi.instance.stop();
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('[Cast] stop: $e');
    }
    try {
      await GoogleCastApi.instance.disconnect();
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('[Cast] disconnect: $e');
    }
  }

  /// Devine le MIME depuis l'URL. Le SDK Cast est strict sur le
  /// contentType — il faut soit `video/mp4`, `video/mp2t`,
  /// `application/x-mpegURL`, `application/dash+xml`, etc.
  String _guessMime(String url) {
    final String lower = url.toLowerCase();
    if (lower.contains('.m3u8') || lower.contains('mpegurl')) {
      return 'application/x-mpegURL';
    }
    if (lower.contains('.mpd') || lower.contains('dash+xml')) {
      return 'application/dash+xml';
    }
    if (lower.contains('.mp4')) return 'video/mp4';
    if (lower.contains('.mkv')) return 'video/x-matroska';
    // Cas IPTV courant : .ts brut ou /live/.../...ts
    return 'video/mp2t';
  }
}
