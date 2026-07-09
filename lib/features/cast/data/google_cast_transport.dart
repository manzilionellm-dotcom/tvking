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
//  ⚠️ ÉTAT ACTUEL (2026-07) — CHROMECAST via RÉCEPTEUR CUSTOM + PROXY.
//  Le Default Media Receiver (CC1AD845) ne décode PAS le MPEG-TS brut des
//  flux IPTV. On charge donc le récepteur custom (5BDFD969, mpegts.js) qui
//  décode le TS sur la TV, et on lui envoie l'URL HTTPS de MÊME origine
//  https://app.7themotion.com/cast-proxy?u=… (signée par le Worker) : cela
//  lève le blocage contenu mixte / CORS du fetch depuis la page récepteur.
//  Repli si le proxy est injoignable : le RELAIS HLS du téléphone
//  (registerRelay/wrapInHls). Le DLNA (LG/Samsung) n'est PAS concerné — il
//  joue le .ts en direct.
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

/// FLAG D'ACTIVATION DU CUSTOM CAST RECEIVER (App ID `5BDFD969`, « 7 MOTION TS »).
///
/// `false` : le sender natif pointe sur le Default Media Receiver public
///   `CC1AD845`, qui NE decode PAS le MPEG-TS brut → on WRAPPE le .ts en
///   HLS (serveur local du telephone / VPS). Inconvenient : dependance
///   telephone ou VPS.
///
/// `true` : le custom receiver `5BDFD969` (page mpegts.js servie par le
///   Worker à `https://app.7themotion.com/cast-receiver`) decode le MPEG-TS
///   LUI-MEME sur la TV → on envoie l'URL Xtream .ts DIRECTE (sans VPS).
///
/// ⚠️ kCastUseCustomReceiver (ici) et USE_CUSTOM_RECEIVER
///    (android_overlay/google_cast/CastOptionsProviderImpl.kt) DOIVENT
///    TOUJOURS valoir LA MÊME CHOSE. Les desynchroniser = ECRAN NOIR.
///
/// ✅ ACTIVÉ (2026-06-25) : `5BDFD969` est desormais PUBLISHED (Custom
///    Receiver → https://app.7themotion.com/cast-receiver). Le receiver
///    mpegts.js decode le MPEG-TS sur la TV → on envoie le .ts DIRECT, sans
///    VPS, et la box reapparait dans le picker (le filtre par app id publie
///    ne cache plus les appareils).
///
/// ✅ REACTIVÉ (2026-07-01) — le blocage CORS / contenu mixte du 2026-06-29 est
///    RESOLU. On n'envoie plus le .ts HTTP brut au custom receiver : on envoie
///    l'URL HTTPS `https://app.7themotion.com/cast-proxy?u=…` (MÊME origine que
///    la page receiver, en-tetes CORS ouverts, re-type video/mp2t). Le LOAD
///    interceptor du receiver route video/mp2t vers mpegts.js, qui fetch cette
///    URL HTTPS sans contenu mixte ni CORS → la TV decode le TS elle-meme et le
///    telephone peut etre eteint. Le RELAIS HLS du telephone reste le repli si
///    le proxy n'est pas joignable. cf. playStream (stratégie cast_proxy) +
///    worker.js /cast-proxy. DOIT rester SYNCHRONE avec USE_CUSTOM_RECEIVER
///    (CastOptionsProviderImpl.kt) — les deux valent `true`.
/// ⚠️ MISE À JOUR (2026-07-06, CAST_HANDOFF §6.2) : ce flag reste la valeur
///    INITIALE (compile-time) chargée par l'OptionsProvider Kotlin, mais le
///    receiver est désormais BASCULÉ DYNAMIQUEMENT par session via
///    GoogleCastApi.setReceiverApplicationId :
///      - proxy /cast-proxy DÉLIVRE (2xx)  → custom 5BDFD969 (TS décodé TV,
///        téléphone éteint possible) — chemin PRIORITAIRE, inchangé ;
///      - proxy BLOQUÉ par le fournisseur (456/403/512 sur IP datacenter,
///        diag terrain 2026-07-06 : upstream=456) → relais HLS du téléphone
///        envoyé au Default Media Receiver CC1AD845 (la page custom HTTPS ne
///        peut pas fetch un relais HTTP — mixed content).
const bool kCastUseCustomReceiver = true;

/// App ID du récepteur custom « 7 MOTION TS » (page mpegts.js du Worker).
/// Doit rester aligné avec CUSTOM_RECEIVER_ID (CastOptionsProviderImpl.kt).
const String kCastCustomReceiverAppId = '5BDFD969';

/// App ID du Default Media Receiver public de Google. Lit le HLS nativement
/// (pas de fetch depuis une page HTTPS → pas de blocage mixed-content sur le
/// relais HTTP du téléphone). Aligné avec DEFAULT_RECEIVER_ID (Kotlin).
const String kCastDefaultReceiverAppId = 'CC1AD845';

/// Overlay de diagnostic du receiver custom (mpegts.js) : coin haut-gauche,
/// texte vert, 15 dernieres lignes (LOAD contentId, branche mpegts/CAF,
/// mpegts ERROR + MEDIA_INFO codecs, events du <video>, status du 1er fetch).
/// Passe `{debug:true}` en customData du LOAD. Repasser a `false` en prod
/// une fois le bug trouve. Sans effet sur le Default Media Receiver.
/// PROD (tronc client) : `false` — les clients ne doivent pas voir le texte
/// vert. La branche cast de diagnostic le garde a `true`.
const bool kCastDebugOverlay = false;

/// Base du Worker (même domaine que le récepteur Cast custom) qui signe et sert
/// le proxy Cast. Le secret HMAC vit UNIQUEMENT côté Worker : l'app demande une
/// URL signée à `/cast-sign`, elle n'embarque aucun secret.
const String _kCastProxyBase = 'https://app.7themotion.com';

class GoogleCastTransport implements CastTransport {
  GoogleCastTransport(this.device);

  final CastDevice device;

  /// Dernier chemin de routage reellement emprunte par [playStream] :
  /// 'cast_proxy' | 'local_hls_relay' | 'direct'. Lu par CastManager pour
  /// etiqueter correctement l'AttemptResult (au lieu de 'direct' en dur).
  String lastCastPath = 'direct';

  /// URL exacte transmise a loadMedia, token signe masque. Null tant qu'aucun cast.
  String? lastCastUrlRedacted;

  /// URL REELLE du relais HLS local quand le chemin est
  /// 'local_hls_relay' (null sinon). Le CastManager s'en sert pour :
  ///   1. liberer la session (clearRelay) au disconnect / au zap ;
  ///   2. activer le maintien en vie (foreground service) — le
  ///      telephone alimente la TV, il ne doit pas s'endormir.
  String? lastRelayUrl;

  /// URL upstream d'ORIGINE (avant que le probe du telephone ne suive les
  /// redirections). Renseignee par CastManager juste avant [playStream].
  ///
  /// Pourquoi : les flux Xtream/IPTV redirigent souvent
  /// `http://portail/.../ID.ts` vers un endpoint a TOKEN par-connexion
  /// (`http://IP/live/USER/PASS/ID?token`). Le telephone resout ce token
  /// pendant le probe, mais il peut etre PERISSABLE : au moment ou la TV
  /// (via /cast-proxy) va le chercher, il est deja perime → « format non
  /// pris en charge ». En signant l'URL D'ORIGINE, le Worker /cast-proxy
  /// re-suit la redirection LUI-MEME au play-time (≤3 sauts) et obtient
  /// un token FRAIS. Diag terrain SHIELD 2026-07-06 : les 3 sessions
  /// redirigeaient vers une IP brute /live/ → ce chemin est le bon.
  /// `null` → on retombe sur l'URL deja resolue (comportement historique).
  String? originalUpstreamUrl;

  @override
  Future<void> playStream({
    required String streamUrl,
    String title = '7 MOTION',
    String? imageUrl,
  }) async {
    // Reset des marqueurs de diagnostic : evite d'afficher le chemin
    // du cast precedent si celui-ci echoue avant la decision de routage.
    lastCastPath = 'direct';
    lastCastUrlRedacted = null;
    lastRelayUrl = null;
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

    // 2) DÉCISION DE ROUTAGE — AVANT d'établir la session, parce qu'elle
    //    détermine QUEL RECEIVER charger sur la TV (CAST_HANDOFF §6.2) :
    //      - cast_proxy       → custom 5BDFD969 (mpegts.js décode le TS) ;
    //      - local_hls_relay  → Default CC1AD845 (lit le HLS du téléphone
    //        nativement ; la page custom HTTPS ne PEUT PAS fetch un relais
    //        HTTP — mixed content).
    //    Coût : la signature + vérification du proxy (quelques secondes au
    //    pire) précède l'ouverture du picker — négligeable en pratique.
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

    // Decision de routage du flux pour le Cast :
    //   1. On ne touche PAS un flux deja adaptatif (HLS/DASH).
    //   2. Pour le MPEG-TS brut (.ts / Xtream /live/) : la page mpegts.js
    //      (5BDFD969 -> /cast-receiver) decode le TS sur la TV, alimentee par
    //      le proxy HTTPS de meme origine /cast-proxy (contourne contenu mixte
    //      + CORS). Repli : relais HLS du telephone si le proxy est injoignable.
    if (!isHlsOrDash(streamUrl) && _looksLikeRawMpegTs(streamUrl)) {
      // CHEMIN PRINCIPAL (2026-07-01) — PROXY CAST via le récepteur custom.
      // Le récepteur custom (mpegts.js) décode le MPEG-TS sur la TV, mais il ne
      // peut PAS fetch un flux IPTV HTTP brut (contenu mixte) ni sans en-tête
      // CORS. On lui envoie donc l'URL HTTPS de MÊME origine
      // /cast-proxy?u=… (signée par le Worker) : mpegts.js la lit sans blocage
      // et le téléphone peut être éteint (la TV tire le flux directement). On
      // NE renvoie PLUS jamais le .ts brut au Default Media Receiver
      // (structurellement indécodable → « format non supporté »).
      //
      // Le proxy Worker suit lui-même les redirects (≤3), donc on lui passe
      // simplement l'URL upstream nettoyée (sans pré-vol réseau côté téléphone).
      // On PRÉFÈRE l'URL d'origine (avant redirection) : le token IPTV résolu
      // par le téléphone peut être périmé quand la TV le fetch (cf.
      // originalUpstreamUrl). Le Worker re-suit la redirection au play-time.
      // Nettoyage minimal : trim + strip des « ? » orphelins de fin (fréquents
      // sur les URLs Xtream .ts) qui perturbent certains parseurs.
      final String signSource =
          (originalUpstreamUrl != null && originalUpstreamUrl!.trim().isNotEmpty)
              ? originalUpstreamUrl!
              : streamUrl;
      String upstream = signSource.trim();
      while (upstream.endsWith('?')) {
        upstream = upstream.substring(0, upstream.length - 1);
      }
      String? proxied =
          kCastUseCustomReceiver ? await _signedCastProxyUrl(upstream) : null;

      // NOUVEAU (CAST_HANDOFF §6.1) : ne PAS faire confiance aveuglément au
      // proxy — le Worker peut être BLOQUÉ par le fournisseur IPTV (IP
      // datacenter refusée : upstream=456 relevé sur le terrain 2026-07-06).
      // Dans ce cas mpegts.js recevrait un 502 en boucle → écran noir. On
      // vérifie que /cast-proxy DÉLIVRE vraiment avant de l'envoyer à la TV.
      if (proxied != null && !await _proxyDelivers(proxied)) {
        StructuredLogger.instance.warn(
          domain: 'cast',
          event: 'proxy.blocked_fallback_relay',
          ctx: const <String, Object?>{},
        );
        proxied = null; // → bascule sur le relais HLS du téléphone
      }

      if (proxied != null) {
        urlToCast = proxied;
        mime = 'video/mp2t';
        castPath = 'cast_proxy';
      } else {
        // REPLI — RELAIS HLS DU TÉLÉPHONE. Le téléphone tire le flux (client
        // natif, ni CORS ni contenu mixte), le DÉCOUPE en vrais segments
        // (~3 s, TsHlsSegmenter) et sert une playlist HLS LIVE GLISSANTE que
        // le Default Media Receiver lit nativement. (L'ancienne playlist à
        // « segment unique infini » était structurellement illisible par le
        // récepteur CAF moderne — cause du 8/8 d'échecs SHIELD 2026-07-09.)
        // registerRelay renvoie null si la TV n'est pas
        // joignable depuis l'IP LAN du téléphone (réseaux séparés / isolation
        // AP) → on remonte alors une erreur claire.
        final DlnaProfile profile =
            DlnaProfiles.select(url: streamUrl, finalMime: null);
        // `upstream` = URL PORTAIL D'ORIGINE nettoyée (calculée plus
        // haut), PAS l'URL déjà résolue : les tokens Xtream sont
        // par-connexion — celui de `streamUrl` a déjà été consommé par
        // le probe. La session relais re-suit la redirection à CHAQUE
        // (re)connexion → token frais (cause probable des 2 échecs
        // résiduels SHIELD du 2026-07-09 : M6, EURO CRIME).
        final String? hlsRelay = await LocalCastServer.instance.registerRelay(
          upstreamUrl: upstream,
          profile: profile,
          receiverHost: device.host,
          wrapInHls: true,
        );
        if (hlsRelay != null) {
          urlToCast = hlsRelay;
          mime = 'application/x-mpegURL';
          castPath = 'local_hls_relay';
          lastRelayUrl = hlsRelay;
        } else {
          throw Exception(
            'Le cast vers cette TV est indisponible (réseau incompatible). '
            'Réessaie sur le même Wi-Fi, ou utilise une TV DLNA (LG/Samsung).',
          );
        }
      }
    }

    // 3) RECEIVER ADAPTÉ AU CHEMIN (CAST_HANDOFF §6.2). Le natif change
    //    l'App ID de session à la volée (CastContext.setReceiverApplicationId) ;
    //    si une session tournait sur l'AUTRE receiver, il la termine et
    //    re-sélectionne la même TV tout seul (résultat 'switching').
    final String desiredReceiver = receiverAppIdForCastPath(castPath);
    final String switchOutcome = kCastUseCustomReceiver
        ? await api.setReceiverApplicationId(desiredReceiver)
        : 'skipped';
    StructuredLogger.instance.info(
      domain: 'cast',
      event: 'google.receiver_select',
      ctx: <String, Object?>{
        'path': castPath,
        'appId': desiredReceiver,
        'outcome': switchOutcome,
      },
    );

    // 4) SESSION sur le bon receiver.
    bool hasSession;
    if (switchOutcome == 'switching') {
      // L'ancienne session (autre receiver) se ferme ; le natif ré-ouvre la
      // même TV sur le nouveau receiver. On attend cette reconnexion AVANT
      // de déranger l'utilisateur avec le picker.
      hasSession = await _waitForSessionOn(
        api,
        desiredReceiver,
        const Duration(seconds: 12),
      );
    } else {
      hasSession = await api.hasActiveSession();
    }

    // Pas de session → on demande au SDK d'ouvrir SON dialog natif.
    // L'utilisateur sélectionne sa TV. Le SDK gère la négociation,
    // le pairing, etc. — c'est exactement le flow Netflix / YouTube.
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

    lastCastPath = castPath;
    lastCastUrlRedacted = _redactCastToken(redactStreamUrl(urlToCast));

    final bool loaded = await api.loadMedia(
      streamUrl: urlToCast,
      title: title,
      mime: mime,
      imageUrl: imageUrl,
      debug: kCastDebugOverlay,
    );
    if (!loaded) {
      throw Exception('La TV a refusé le flux.');
    }

    // VERITE TERRAIN (2026-06-06) : loadMedia=true signifie seulement
    // que le recepteur a ACCEPTE la commande, PAS que la video joue.
    // Sur un .ts non decodable on voyait l'icone "cast" bleue sans
    // image, mais le diagnostic affichait "succes". On attend donc la
    // lecture REELLE (etat PLAYING) avant de declarer le succes.
    try {
      await _awaitRealPlayback(api);
    } on Exception catch (e) {
      // Sur le chemin relais, enrichit l'erreur avec l'etat REEL de la
      // session HLS (codec vu en PMT + compteurs de requetes du
      // recepteur) : « codec/format non supporte » avec 0 segment servi
      // = probleme RESEAU, pas codec — indispensable pour trancher a
      // distance (diag SHIELD 2026-07-09 : 2 chaines encore en echec).
      if (castPath == 'local_hls_relay' && lastRelayUrl != null) {
        final String? info =
            LocalCastServer.instance.hlsSessionDebugInfo(lastRelayUrl!);
        if (info != null) {
          final String base =
              e.toString().replaceFirst('Exception: ', '');
          throw Exception('$base [relais: $info]');
        }
      }
      rethrow;
    }
  }

  /// Attend que le recepteur passe REELLEMENT en lecture.
  /// - PLAYING -> succes.
  /// - IDLE + idleReason "error" -> la TV a rejete le flux.
  /// - timeout (25 s) -> la lecture n'a jamais demarre (format non lu).
  ///   25 s (et non 18) : le transmux mpegts.js du custom receiver peut
  ///   mettre quelques secondes a produire le 1er segment fMP4.
  Future<void> _awaitRealPlayback(GoogleCastApi api) async {
    final Completer<void> done = Completer<void>();
    final Timer timer = Timer(const Duration(seconds: 25), () {
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
    // Le SDK natif remonte AUSSI le verdict du LOAD (RemoteMediaClient.load) :
    // `load_failed(code)` = la commande LOAD elle-même a été rejetée (URL
    // injoignable depuis la TV, MediaInfo invalide, récepteur custom KO…),
    // DISTINCT d'un passage PLAYING→IDLE:error (codec/conteneur non décodable).
    // On inclut le code natif pour trancher entre « LOAD échoué » et « rejet
    // codec » à la simple lecture du message d'erreur.
    final StreamSubscription<CastNativeSessionEvent> evSub =
        api.sessionEventStream.listen((CastNativeSessionEvent e) {
      if (e.kind == 'load_failed' && !done.isCompleted) {
        done.completeError(Exception(
          'La TV a refusé la commande de lecture (LOAD échoué, code '
          '${e.errorCode}) — flux injoignable depuis la TV ou récepteur '
          'indisponible, distinct d\'un rejet codec.',
        ));
      }
    });
    try {
      await done.future;
    } finally {
      timer.cancel();
      await sub.cancel();
      await evSub.cancel();
    }
  }

  /// Receiver à charger sur la TV selon le chemin de routage (§6.2) :
  /// le relais HLS du téléphone est en HTTP → la page receiver custom
  /// (HTTPS, fetch mpegts.js) ne peut PAS le lire (mixed content) → il
  /// passe par le Default Media Receiver qui lit le HLS nativement.
  /// Tous les autres chemins gardent le receiver custom (prioritaire :
  /// TS décodé sur la TV, téléphone éteint possible).
  @visibleForTesting
  static String receiverAppIdForCastPath(String castPath) =>
      castPath == 'local_hls_relay'
          ? kCastDefaultReceiverAppId
          : kCastCustomReceiverAppId;

  /// Attend qu'une session soit CONNECTÉE sur le receiver [appId] après une
  /// bascule ('switching') : l'ancienne session peut encore apparaître
  /// active pendant sa fermeture, d'où la double condition session + App ID.
  /// `null` (métadonnées pas encore remontées) est toléré : l'App ID du
  /// contexte vient d'être changé, toute NOUVELLE session est la bonne.
  static Future<bool> _waitForSessionOn(
    GoogleCastApi api,
    String appId,
    Duration timeout,
  ) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await api.hasActiveSession()) {
        final String? current = await api.currentReceiverApplicationId();
        if (current == null || current == appId) return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  /// Vérifie que /cast-proxy DÉLIVRE réellement le flux (le Worker peut être
  /// bloqué par le fournisseur IPTV — cf. docs/CAST_HANDOFF.md §3). On lit le
  /// status puis on coupe : on NE télécharge PAS le flux. `true` = 2xx.
  static Future<bool> _proxyDelivers(String proxyUrl) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);
    try {
      final HttpClientRequest req = await client
          .getUrl(Uri.parse(proxyUrl))
          .timeout(const Duration(seconds: 6));
      req.headers.add(HttpHeaders.acceptHeader, '*/*');
      final HttpClientResponse resp =
          await req.close().timeout(const Duration(seconds: 8));
      final int status = resp.statusCode;
      // X-Upstream-Status = le VRAI code du fournisseur vu par le Worker
      // (456/403 = IP datacenter refusée) — précieux dans les diagnostics.
      final String upstream = resp.headers.value('x-upstream-status') ?? '';
      StructuredLogger.instance.info(
        domain: 'cast',
        event: 'proxy.verify',
        ctx: <String, Object?>{'status': status, 'upstream': upstream},
      );
      return status >= 200 && status < 300;
    } on Exception {
      return false; // injoignable → on considère le proxy KO
    } finally {
      client.close(force: true); // coupe le GET sans vider le flux
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

  /// Demande au Worker une URL `/cast-proxy` SIGNÉE pour [upstreamUrl] : le
  /// secret HMAC reste côté serveur (jamais dans l'app). Renvoie l'URL HTTPS de
  /// même origine que le récepteur à lui envoyer, ou `null` si la signature
  /// échoue (→ repli relais HLS du téléphone). Best-effort, ne jette jamais.
  /// DIAGNOSTIC RÉSEAU — expose la MÊME fonction que [playStream] utilise pour
  /// décider proxy vs relais (check 6 du diagnostic réseau). Retourne l'URL
  /// /cast-proxy signée, ou null si /cast-sign n'a pas répondu {ok:true} → dans
  /// ce cas playStream retombe sur le relais HLS. Ne jette jamais.
  static Future<String?> diagnosticSignedCastProxyUrl(String upstreamUrl) =>
      _signedCastProxyUrl(upstreamUrl);

  static Future<String?> _signedCastProxyUrl(String upstreamUrl) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);
    try {
      final Uri uri = Uri.parse('$_kCastProxyBase/cast-sign')
          .replace(queryParameters: <String, String>{'u': upstreamUrl});
      final HttpClientRequest req =
          await client.getUrl(uri).timeout(const Duration(seconds: 6));
      req.headers.add(HttpHeaders.acceptHeader, 'application/json');
      final HttpClientResponse resp =
          await req.close().timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        return null;
      }
      final String body = await resp.transform(utf8.decoder).join();
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> &&
          decoded['ok'] == true &&
          decoded['url'] is String) {
        return decoded['url'] as String;
      }
      return null;
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('[Cast] cast-sign KO: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Masque le parametre `t=` (token signe du proxy) dans une URL deja
  /// passee par redactStreamUrl (qui ne masque que password/token/pass/pwd).
  static String _redactCastToken(String url) {
    return url.replaceAll(RegExp(r'([?&]t=)[^&]*'), r'$1***');
  }
}
