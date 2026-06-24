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
//
//  ⚠️ ÉTAT ACTUEL (2026-06) — CHROMECAST EN MODE DÉGRADÉ.
//  Le Default Media Receiver (CC1AD845) ne décode PAS le MPEG-TS brut
//  des flux IPTV. On le contourne en remuxant le .ts en HLS-fMP4 via le
//  VPS `cast.7themotion.com` (_kCastRemuxBase). CE VPS EST ACTUELLEMENT
//  ÉTEINT → un cast Chromecast sur un flux .ts donnerait un écran noir.
//  Tant qu'il ne tourne pas, on DÉTECTE son indisponibilité (HEAD 3 s)
//  et on remonte une erreur claire au lieu de tenter le load (cf.
//  _remuxReachable). On NE supprime PAS le code VPS : il redeviendra
//  fonctionnel dès le VPS rallumé. Le DLNA (LG/Samsung) n'est PAS
//  concerné — il joue le .ts en direct.
// =========================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/observability/structured_logger.dart';
import '../domain/cast_device.dart';
import 'cast_session_diagnostic.dart' show redactStreamUrl;
import 'cast_transport.dart';
import 'dlna_profiles.dart';
import 'google_cast_api.dart';
import 'local_cast_server.dart';

/// FLAG D'ACTIVATION DU CUSTOM CAST RECEIVER (App ID `46F815A5`).
///
/// `false` (defaut, expedie en prod) : le sender natif pointe sur le
///   Default Media Receiver public `CC1AD845`, qui NE decode PAS le
///   MPEG-TS brut → on WRAPPE le .ts en HLS servi par le serveur local
///   du telephone. Inconvenient : eteindre le telephone coupe le flux.
///
/// `true` : le custom receiver `46F815A5` (cloudflare/cast_receiver.js,
///   mpegts.js) est Published dans la Cast Developer Console et decode
///   le MPEG-TS LUI-MEME → on envoie l'URL Xtream .ts DIRECTE. La TV
///   tire le flux seule → le telephone peut s'eteindre, la TV continue.
///
/// ⚠️ DOIT etre flippe EN MEME TEMPS que `USE_CUSTOM_RECEIVER` dans
///    android_overlay/google_cast/CastOptionsProviderImpl.kt. Les deux
///    decrivent le MEME basculement. Les desynchroniser = ecran noir.
const bool kCastUseCustomReceiver = false;

/// Base du service de remux VPS (cf. server/cast-remux) qui transforme le
/// MPEG-TS live en HLS-fMP4 — le SEUL format que le recepteur Cast par
/// defaut (Shaka) lit nativement. A faire pointer (DNS A) vers ton VPS.
const String _kCastRemuxBase = 'https://cast.7themotion.com';

/// Construit l'URL HLS-fMP4 (servie par le VPS remux en HTTPS) pour un flux
/// MPEG-TS brut. L'upstream est encode en base64url dans le chemin → le
/// service reste stateless (cf. server/cast-remux/server.js).
String _castRemuxUrl(String upstreamUrl) {
  final String b64 =
      base64Url.encode(utf8.encode(upstreamUrl)).replaceAll('=', '');
  return '$_kCastRemuxBase/live/$b64/master.m3u8';
}

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
    String castPath = 'direct';

    // Decision de remux pour le Cast :
    //   1. On ne touche PAS un flux deja adaptatif (HLS/DASH).
    //   2. On remux le MPEG-TS brut (.ts / Xtream /live/).
    //
    // POURQUOI (2026-06-20, valide par diag terrain SHIELD) : le recepteur
    // Cast par defaut (Shaka depuis fin 2025) ne sait PAS lire du MPEG-TS
    // brut -> erreur "codec / format non supporte". Le seul format que TOUS
    // les Chromecast lisent nativement = HLS-fMP4. Un Worker Cloudflare ne
    // peut pas transcoder ; on passe donc par le service de remux VPS
    // (server/cast-remux, ffmpeg -c copy = remux conteneur, pas de
    // re-encodage) qui sert le flux en HLS-fMP4 https. Le Chromecast tire
    // tout du VPS -> le telephone peut s'eteindre.
    if (!isHlsOrDash(streamUrl) && _looksLikeRawMpegTs(streamUrl)) {
      urlToCast = _castRemuxUrl(streamUrl);
      mime = 'application/x-mpegURL';
      castPath = 'remux_hls';
    }

    // DIAGNOSTIC (brief §4.3) — tracer EXACTEMENT l'URL et le MIME
    // pousses au recepteur (URL redactee, pas de fuite credentials).
    StructuredLogger.instance.info(
      domain: 'cast',
      event: 'google.load_media',
      ctx: <String, Object?>{
        'path': castPath,
        'mime': mime,
        'url': redactStreamUrl(urlToCast),
        'receiverHost': device.host,
        'receiverName': device.name,
        'isExoPlayerDevice': isExoPlayerReceiver(device),
      },
    );

    // GARDE-FOU CHROMECAST (mode dégradé) : le chemin remux dépend du VPS
    // cast.7themotion.com. S'il ne répond pas, le Default Media Receiver
    // recevrait une URL morte → écran noir avec le titre affiché. On
    // détecte l'indisponibilité (HEAD court) et on remonte une erreur
    // claire AVANT de tenter le load, plutôt que d'infliger l'écran noir.
    if (castPath == 'remux_hls') {
      final bool remuxUp = await _remuxReachable();
      if (!remuxUp) {
        StructuredLogger.instance.warn(
          domain: 'cast',
          event: 'google.remux_unavailable',
          ctx: <String, Object?>{'base': _kCastRemuxBase},
        );
        throw Exception(
          'Le cast vers Chromecast est temporairement indisponible. '
          'Utilise une TV compatible DLNA (LG/Samsung) ou réessaie plus tard.',
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

    // VERITE TERRAIN (2026-06-06) : loadMedia=true signifie seulement
    // que le recepteur a ACCEPTE la commande, PAS que la video joue.
    // Sur un .ts non decodable on voyait l'icone "cast" bleue sans
    // image, mais le diagnostic affichait "succes". On attend donc la
    // lecture REELLE (etat PLAYING) avant de declarer le succes.
    await _awaitRealPlayback(api);
  }

  /// Attend que le recepteur passe REELLEMENT en lecture.
  /// - PLAYING -> succes.
  /// - IDLE + idleReason "error" -> la TV a rejete le flux.
  /// - timeout (18 s) -> la lecture n'a jamais demarre (format non lu).
  Future<void> _awaitRealPlayback(GoogleCastApi api) async {
    final Completer<void> done = Completer<void>();
    final Timer timer = Timer(const Duration(seconds: 18), () {
      if (!done.isCompleted) {
        done.completeError(Exception(
          'La TV n\'a pas démarré la lecture — format probablement non '
          'pris en charge par le récepteur Cast.',
        ));
      }
    });
    final StreamSubscription<CastNativeMediaState> sub =
        api.mediaStateStream.listen((CastNativeMediaState s) {
      if (s.playerState == CastNativePlayerState.playing) {
        if (!done.isCompleted) done.complete();
      } else if (s.playerState == CastNativePlayerState.idle &&
          s.idleReason == 'error') {
        if (!done.isCompleted) {
          done.completeError(Exception(
            'La TV a refusé le flux (codec / format non supporté).',
          ));
        }
      }
    });
    try {
      await done.future;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  /// (BUG A) Le flux est-il deja un conteneur adaptatif — HLS
  /// (`.m3u8`) ou DASH (`.mpd`) ? Ces formats sont lus nativement par
  /// TOUS les recepteurs Cast ; les wrapper les casserait.
  @visibleForTesting
  static bool isHlsOrDash(String url) {
    final String lower = url.toLowerCase();
    return lower.contains('.m3u8') ||
        lower.contains('mpegurl') ||
        lower.contains('.mpd') ||
        lower.contains('dash+xml');
  }

  /// (BUG A) Le recepteur est-il base sur ExoPlayer (NVIDIA SHIELD,
  /// beaucoup de dongles Google TV) ? Ces appareils decodent le
  /// MPEG-TS brut directement, contrairement au Default Media Receiver
  /// pur d'un Chromecast. On renifle nom / modele / fabricant.
  @visibleForTesting
  static bool isExoPlayerReceiver(CastDevice device) {
    final String hay =
        '${device.name} ${device.model ?? ''} ${device.manufacturer ?? ''}'
            .toLowerCase();
    return hay.contains('shield') || hay.contains('nvidia');
  }

  /// (BUG B) L'URL relais HLS pointe vers l'IP LAN du telephone. La TV
  /// doit etre sur le meme /24 pour la joindre ; sur un VLAN invite ou
  /// avec isolation AP elle ne peut pas, et le wrap garantirait un
  /// ecran noir. On ne bloque QUE quand on peut PROUVER que les deux
  /// hotes different (les deux en IPv4 litteral) — si l'un des deux
  /// n'est pas une IPv4 litterale, on ne presume rien (true).
  @visibleForTesting
  static bool sameSubnet(String localUrl, String receiverHost) {
    final String? localHost = Uri.tryParse(localUrl)?.host;
    if (localHost == null || localHost.isEmpty) return true;
    final List<int>? a = _ipv4Octets(localHost);
    final List<int>? b = _ipv4Octets(receiverHost);
    if (a == null || b == null) return true;
    return a[0] == b[0] && a[1] == b[1] && a[2] == b[2];
  }

  /// Parse `a.b.c.d` en 4 octets 0-255, ou `null` si ce n'est pas une
  /// IPv4 litterale (hostname, IPv6, valeur hors borne…).
  static List<int>? _ipv4Octets(String host) {
    final List<String> parts = host.split('.');
    if (parts.length != 4) return null;
    final List<int> out = <int>[];
    for (final String p in parts) {
      final int? n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return null;
      out.add(n);
    }
    return out;
  }

  /// Detecte une URL qui pointe vers du MPEG-TS brut (cas IPTV
  /// typique) : extension .ts, ou path /live/.../<id>(.ts)? sans
  /// extension explicite, ou MIME deja typage TS dans le URL.
  bool _looksLikeRawMpegTs(String url) {
    final String lower = url.toLowerCase();
    if (lower.contains('.m3u8') || lower.contains('mpegurl')) return false;
    if (lower.contains('.mpd') || lower.contains('dash+xml')) return false;
    if (lower.contains('.mp4')) return false;
    if (lower.contains('.mkv')) return false;
    // .ts explicite OU pattern Xtream /live/USER/PASS/ID (sans ext)
    if (lower.contains('.ts')) return true;
    if (lower.contains('/live/')) return true;
    if (lower.contains('mp2t') || lower.contains('mpegts')) return true;
    return false;
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

  /// Teste si le VPS de remux ([_kCastRemuxBase]) répond, avec un timeout
  /// court (3 s). On fait un GET sur la racine (le HEAD n'est pas garanti
  /// supporté) et on l'annule dès la réponse — on veut juste savoir si le
  /// serveur est joignable, pas lire un corps. Tolérant : n'importe quel
  /// code HTTP = serveur debout ; seules une exception réseau / un timeout
  /// = injoignable. Best-effort, ne jette jamais.
  Future<bool> _remuxReachable() async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final Uri base = Uri.parse(_kCastRemuxBase);
      final HttpClientRequest req =
          await client.getUrl(base).timeout(const Duration(seconds: 3));
      final HttpClientResponse resp =
          await req.close().timeout(const Duration(seconds: 3));
      // N'importe quelle réponse HTTP prouve que le serveur est debout.
      await resp.listen(null, cancelOnError: true).cancel();
      return true;
    } on Exception {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
