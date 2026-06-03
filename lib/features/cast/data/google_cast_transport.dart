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

import '../../../core/observability/structured_logger.dart';
import '../domain/cast_device.dart';
import 'cast_transport.dart';
import 'dlna_profiles.dart';
import 'google_cast_api.dart';
import 'local_cast_server.dart';

class GoogleCastTransport implements CastTransport {
  GoogleCastTransport(this.device);

  final CastDevice device;

  @override
  Future<void> playStream({
    required String streamUrl,
    String title = 'BLACK7 ROYAL',
    String? imageUrl,
  }) async {
    final GoogleCastApi api = GoogleCastApi.instance;

    // 1) Disponibilité FINE du SDK Cast (BUG C) — on ne ment plus :
    //    on distingue "Play Services absent" d'une "init Cast ratée"
    //    (meta-data/OptionsProvider) sur un téléphone qui a pourtant GMS.
    final String availability = await api.castAvailability();
    if (availability != 'available') {
      StructuredLogger.instance.warn(
        domain: 'cast',
        event: 'cast.sdk_init_failed',
        ctx: <String, Object?>{'reason': availability},
      );
      switch (availability) {
        case 'no_gms':
          throw Exception(
            'Google Cast indisponible : ce téléphone n\'a pas Google Play '
            'Services. Utilise le mode QR code pour caster.',
          );
        case 'no_bridge':
          throw Exception(
            'Module Cast non disponible dans cette version de l\'app.',
          );
        default: // init_error
          throw Exception(
            'Le Cast n\'a pas pu démarrer (configuration). Réessaie, ou '
            'utilise le mode QR code en attendant.',
          );
      }
    }

    // 2) Y a-t-il déjà une session active ? (l'utilisateur a déjà
    //    connecté sa TV via le dialog Cast lors d'un cast précédent)
    bool hasSession = await api.hasActiveSession();

    // 3) Pas de session → on demande au SDK d'ouvrir SON dialog natif.
    //    L'utilisateur sélectionne sa TV. Le SDK gère la négociation,
    //    le pairing, etc. — c'est exactement le flow Netflix / YouTube.
    //
    //    BUG E — Pour les Chromecast/Google TV, le SDK natif est la
    //    SEULE source fiable de sélection (notre picker mDNS sert juste
    //    à afficher). On garde donc CE dialog comme unique sélecteur, et
    //    on abaisse le timeout (30s → 12s) avec un message clair en cas
    //    d'annulation, pour ne pas laisser l'utilisateur attendre.
    if (!hasSession) {
      await api.showRoutePicker();
      final DateTime deadline =
          DateTime.now().add(const Duration(seconds: 12));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (await api.hasActiveSession()) {
          hasSession = true;
          break;
        }
      }
      if (!hasSession) {
        throw Exception(
          'Aucune TV sélectionnée dans le sélecteur Chromecast. '
          'Réessaie et tape ta TV dans la liste.',
        );
      }
    }

    // 4) Session OK — on pousse le flux.
    //
    //    Phase 1+/HLS Wrapper (2026-06-01) — DECOUVERTE CLEF :
    //    Google Cast SDK ne supporte PAS officiellement MPEG-TS (.ts)
    //    en LIVE (cf. developers.google.com/cast/docs/media). Les
    //    seuls formats LIVE supportes sont HLS et DASH. Tirer du .ts
    //    brut au Cast = echec ou comportement aleatoire selon le
    //    firmware du receveur (ExoPlayer-based comme SHIELD peut
    //    s'en sortir, vrai Chromecast pur refuse).
    //
    //    Solution : si l'URL pointe vers du .ts (cas IPTV typique),
    //    on la wrap dans une playlist HLS minimale servie par notre
    //    LocalCastServer. Le Cast voit un HLS standard, accepte, et
    //    fetch le segment .ts pass-through. Technique standard
    //    (BubbleUPnP, IPTV Proxy, etc.).
    //
    //    Phase 1+/G1 : on transmet aussi `imageUrl` (logo de la
    //    chaine).
    String urlToCast = streamUrl;
    String mime = _guessMime(streamUrl);

    // BUG A — DÉCISION DE FORMAT.
    // Un Chromecast PUR ne lit pas le MPEG-TS brut (video/mp2t) en live.
    // Règle : on wrappe en HLS TOUT flux qui n'est PAS déjà adaptatif
    // (HLS/DASH), SAUF si le récepteur est de type ExoPlayer (SHIELD &
    // co.) qui, lui, sait lire le .ts direct. → on n'envoie JAMAIS de
    // mp2t direct à un Chromecast pur.
    final bool alreadyAdaptive = _isHlsOrDash(streamUrl);
    final bool exoReceiver = _isExoPlayerReceiver(device);
    final bool shouldWrap = !alreadyAdaptive && !exoReceiver;

    StructuredLogger.instance.info(
      domain: 'cast',
      event: 'cast.format_decision',
      ctx: <String, Object?>{
        'alreadyAdaptive': alreadyAdaptive,
        'exoReceiver': exoReceiver,
        'decision': shouldWrap ? 'hls-wrap' : 'direct',
        'mime': mime,
        'model': device.model,
      },
    );

    if (shouldWrap) {
      final String? wrappedUrl =
          await LocalCastServer.instance.registerRelay(
        upstreamUrl: streamUrl,
        profile: const DlnaProfile(
          mime: 'video/mp2t',
          profileName: 'MPEG_TS_SD_NA_ISO',
          transferMode: DlnaTransferMode.streaming,
          objectClass: 'object.item.videoItem.videoBroadcast',
          fileExtension: 'ts',
        ),
        receiverHost: device.host,
        wrapInHls: true,
      );
      if (wrappedUrl != null) {
        // BUG B — la TV doit pouvoir JOINDRE le serveur HLS local (le
        // téléphone). Le pairing Cast passe par le cloud Google et
        // réussit même en isolation AP, mais le fetch HLS téléphone→TV,
        // lui, échoue en silence si TV et téléphone ne sont pas sur le
        // même sous-réseau. On vérifie ça AVANT d'envoyer (au minimum :
        // même /24).
        if (!_sameSubnet(wrappedUrl, device.host)) {
          StructuredLogger.instance.warn(
            domain: 'cast',
            event: 'cast.relay_unreachable',
            ctx: <String, Object?>{'tvHost': device.host},
          );
          throw Exception(
            'Ta TV ne peut pas joindre ton téléphone (WiFi invité / '
            'isolation AP probable). Mets les deux sur le même WiFi, ou '
            'utilise le mode QR code.',
          );
        }
        urlToCast = wrappedUrl;
        mime = 'application/x-mpegURL';
      } else {
        // Le wrap a échoué : plutôt que d'envoyer du mp2t direct (que
        // le Chromecast refusera), on remonte une erreur claire.
        StructuredLogger.instance.warn(
          domain: 'cast',
          event: 'cast.hls_wrap_failed',
          ctx: <String, Object?>{'upstream': streamUrl},
        );
        throw Exception(
          'Impossible de préparer le flux pour ta TV. Essaie le mode '
          'QR code (lecture via le navigateur de la TV).',
        );
      }
    }

    final bool loaded = await api.loadMedia(
      streamUrl: urlToCast,
      title: title,
      mime: mime,
      imageUrl: imageUrl,
    );
    if (!loaded) {
      throw Exception('La TV a refusé le flux.');
    }
  }

  /// `true` si l'URL est DÉJÀ un format adaptatif (HLS ou DASH) que le
  /// Chromecast accepte nativement → pas besoin de wrap.
  @visibleForTesting
  static bool isHlsOrDash(String url) {
    final String lower = url.toLowerCase();
    return lower.contains('.m3u8') ||
        lower.contains('mpegurl') ||
        lower.contains('.mpd') ||
        lower.contains('dash+xml');
  }

  bool _isHlsOrDash(String url) => isHlsOrDash(url);

  /// `true` si le récepteur est de type ExoPlayer (NVIDIA SHIELD,
  /// certains Android TV) qui sait lire le MPEG-TS brut direct. On
  /// reste CONSERVATEUR : seuls les modèles clairement ExoPlayer sont
  /// reconnus ; tout le reste est wrappé par défaut (Chromecast pur).
  @visibleForTesting
  static bool isExoPlayerReceiver(CastDevice device) {
    final String s =
        '${device.model ?? ''} ${device.manufacturer ?? ''} ${device.name}'
            .toLowerCase();
    return s.contains('shield') || s.contains('nvidia');
  }

  bool _isExoPlayerReceiver(CastDevice device) =>
      isExoPlayerReceiver(device);

  /// `true` si l'IP du serveur local ([localUrl]) et la TV ([tvHost])
  /// sont sur le même sous-réseau /24 (heuristique). En cas de doute
  /// (parse impossible, non-IPv4), on renvoie `true` pour ne pas
  /// bloquer un cast qui marcherait.
  @visibleForTesting
  static bool sameSubnet(String localUrl, String tvHost) {
    try {
      final String phoneIp = Uri.parse(localUrl).host;
      String net(String ip) {
        final List<String> p = ip.split('.');
        return p.length == 4 ? '${p[0]}.${p[1]}.${p[2]}' : ip;
      }
      // Si l'un des deux n'est pas une IPv4 littérale, on ne tranche pas.
      if (!RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(phoneIp) ||
          !RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(tvHost)) {
        return true;
      }
      return net(phoneIp) == net(tvHost);
    } catch (_) {
      return true;
    }
  }

  bool _sameSubnet(String localUrl, String tvHost) =>
      sameSubnet(localUrl, tvHost);

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
