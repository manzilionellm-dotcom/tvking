// =========================================================
//  stream_probe.dart — Pré-vol d'un flux avant envoi au récepteur
// =========================================================
//  Objectif : ne JAMAIS envoyer une URL cassée au récepteur. Sinon
//  c'est la TV qui affiche le message d'erreur cryptique, et le
//  user n'a aucune façon de comprendre ce qui se passe.
//
//  Avant de caster, on fait un HEAD (avec fallback GET-Range:0-0
//  si HEAD est refusé) sur l'URL upstream pour :
//
//    1. Suivre les redirects 301/302/303/307/308 jusqu'à l'URL
//       finale réelle. Les récepteurs DLNA refusent souvent les
//       redirects (ils font un GET unique sans Location-follow).
//    2. Récupérer le MIME exact (Content-Type) — beaucoup d'IPTV
//       servent du `application/octet-stream` ; le `Content-Type`
//       du serveur peut différer de l'extension de l'URL.
//    3. Détecter si le serveur supporte les Range requests (utile
//       pour la VOD avec seek).
//    4. Mesurer la latence d'ouverture (TTFB). Si > 5s, on
//       préfère passer par la relay qui peut buffer.
//    5. Détecter une auth manquante (401/403) : on prévient
//       avant le timeout côté TV.
//
//  Si le probe échoue, on le sait AVANT de connecter le récepteur
//  et on propose une explication claire à l'utilisateur.
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/observability/structured_logger.dart';

/// Résultat d'un pré-vol. Tout `null` veut dire "non déterminé".
@immutable
class StreamProbeResult {
  const StreamProbeResult({
    required this.originalUrl,
    required this.finalUrl,
    required this.success,
    this.mime,
    this.contentLength,
    this.acceptsRanges = false,
    this.requiresAuth = false,
    this.redirectCount = 0,
    this.timeToFirstByte,
    this.errorCode,
    this.errorReason,
  });

  /// URL d'origine envoyée par l'app.
  final String originalUrl;

  /// URL après résolution de tous les redirects. Si pas de redirect,
  /// = [originalUrl].
  final String finalUrl;

  /// `true` si on a réussi à atteindre l'origine et qu'elle répond
  /// avec un statut 2xx (ou 206 sur Range). `false` = ne pas tenter
  /// le cast — surface une erreur friendly.
  final bool success;

  /// `Content-Type` final. Peut être `null` si serveur ne le renvoie pas.
  final String? mime;

  /// `Content-Length` final. `null` pour le LIVE.
  final int? contentLength;

  /// `true` si le serveur a renvoyé `Accept-Ranges: bytes`. Indispensable
  /// pour la VOD avec seek.
  final bool acceptsRanges;

  /// 401 / 403 sur le HEAD → le récepteur ne s'authentifiera pas tout
  /// seul, il faut passer par la relay qui injecte les bons headers.
  final bool requiresAuth;

  final int redirectCount;

  /// Temps en ms entre l'ouverture de la connexion et la 1ère ligne
  /// de réponse. > 5000 → on préfère la relay.
  final int? timeToFirstByte;

  /// Code HTTP en cas d'échec.
  final int? errorCode;

  /// Description courte en français.
  final String? errorReason;

  /// "true" si l'URL est LIVE (pas de Content-Length, ou MIME mpegurl,
  /// ou path contient /live/). Best-effort.
  bool get isLive {
    if (contentLength != null && contentLength! > 0) return false;
    final String lower = originalUrl.toLowerCase();
    if (lower.contains('/live/') || lower.contains('.m3u8')) return true;
    if (mime?.toLowerCase().contains('mpegurl') ?? false) return true;
    return true; // Par défaut on suppose LIVE — fait sens en IPTV.
  }

  /// "true" si on devrait passer par la relay au lieu de pousser
  /// l'URL directement au récepteur. Critères :
  ///   - On a fait des redirects (récepteur ne les suivra pas).
  ///   - Auth requise.
  ///   - TTFB élevé (la relay peut buffer).
  ///   - MIME ambigu (`application/octet-stream` notamment).
  bool get shouldUseRelay {
    if (redirectCount > 0) return true;
    if (requiresAuth) return true;
    if ((timeToFirstByte ?? 0) > 3000) return true;
    if (mime == null) return true;
    final String m = mime!.toLowerCase();
    if (m.contains('octet-stream') || m.contains('binary')) return true;
    return false;
  }
}

class StreamProbe {
  StreamProbe._();
  static final StreamProbe instance = StreamProbe._();

  /// User-Agent qu'on présente au serveur upstream — on imite un
  /// player connu pour ne pas se faire bloquer par les filtres anti-bot
  /// de certains serveurs Xtream Codes.
  static const String _kUserAgent =
      'VLC/3.0.20 LibVLC/3.0.20 (7 MOTION Cast Probe)';

  /// Phase 1+ : detecte si une [StreamProbeResult] en echec est due a
  /// un probleme DNS (resolveur a renvoye NODATA/NXDOMAIN ou DNS server
  /// injoignable). Pattern typique observe : `errorReason` contient
  /// "No address associated with hostname" (Android),
  /// "nodename nor servname provided" (iOS/macOS),
  /// "Failed host lookup" (Dart cross-platform).
  ///
  /// Public + `@visibleForTesting` pour qu'on puisse tester la regle
  /// sans monter une stack reseau.
  @visibleForTesting
  static bool isDnsFailure(StreamProbeResult r) {
    if (r.success) return false;
    final String reason = (r.errorReason ?? '').toLowerCase();
    if (reason.isEmpty) return false;
    return reason.contains('hostname') ||
        reason.contains('no address') ||
        reason.contains('name resolution') ||
        reason.contains('failed host lookup') ||
        reason.contains('nodename') ||
        reason.contains('servname');
  }

  /// Phase 1+/B3 — Strip un eventuel `?` vide en fin d'URL et trim
  /// les espaces. Les playlists IPTV pirates incluent souvent un `?`
  /// orphelin a la fin des URLs `.ts`. C'est legal cote HTTP mais
  /// provoque des refus chez certains recepteurs DLNA stricts (LG
  /// notamment). Idempotent.
  ///
  /// Public + visibleForTesting parce que la regle est testable
  /// independamment et qu'on peut un jour vouloir l'appeler depuis
  /// d'autres call sites (relay, sanitisation cote recepteur, etc.).
  @visibleForTesting
  static String sanitizeStreamUrl(String url) {
    String s = url.trim();
    // Retire les ? de fin orphelins (pas de query apres). Boucle pour
    // gerer le cas degenere "url???".
    while (s.endsWith('?')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// Probe avec retry automatique sur les echecs DNS. Pourquoi :
  ///
  /// Diagnostic terrain du 2026-06-01 — 7 sessions cast d'affilee
  /// failent toutes en 11-15ms avec "No address associated with
  /// hostname", alors que Chrome teste 6 minutes plus tard resout
  /// le domaine correctement (ERR_CONNECTION_ABORTED indique IP
  /// resolue). Conclusion : DNS local hoquete brievement et le
  /// resolveur Android met le NODATA en cache negatif. Les sessions
  /// suivantes lisent le cache → echec instantane.
  ///
  /// Le retry avec delai (1.5s) laisse le cache negatif expirer
  /// dans la plupart des cas. Si la 2eme tentative echoue encore en
  /// DNS, c'est probablement une vraie panne DNS et on remonte
  /// l'erreur — l'utilisateur verra le message UX dedie ("Internet
  /// instable").
  ///
  /// Pas de retry sur les AUTRES echecs (timeout, 401, 500) — ils
  /// ont leur propre logique et le retry n'aiderait pas.
  Future<StreamProbeResult> probe(
    String url, {
    Duration timeout = const Duration(seconds: 6),
    int maxRedirects = 5,
    int dnsRetries = 1,
    Duration dnsRetryDelay = const Duration(milliseconds: 1500),
  }) async {
    StreamProbeResult result = await _probeOnce(
      url,
      timeout: timeout,
      maxRedirects: maxRedirects,
    );

    int retriesUsed = 0;
    while (retriesUsed < dnsRetries && isDnsFailure(result)) {
      retriesUsed++;
      StructuredLogger.instance.warn(
        domain: 'cast',
        event: 'probe.dns_retry',
        ctx: <String, Object?>{
          'attempt': retriesUsed,
          'maxRetries': dnsRetries,
          'errorReason': result.errorReason,
          'delayMs': dnsRetryDelay.inMilliseconds,
        },
      );
      await Future<void>.delayed(dnsRetryDelay);
      result = await _probeOnce(
        url,
        timeout: timeout,
        maxRedirects: maxRedirects,
      );
    }

    if (!result.success && isDnsFailure(result)) {
      // Echec definitif apres retries — probablement une vraie panne
      // DNS / filtrage / pas d'internet. On log au niveau ERROR pour
      // que ce pattern soit identifiable dans les rapports.
      StructuredLogger.instance.error(
        domain: 'cast',
        event: 'probe.dns_failure',
        ctx: <String, Object?>{
          'attempts': retriesUsed + 1,
          'errorReason': result.errorReason,
          // On log le HOSTNAME (pas l'URL complete avec credentials)
          // pour le diagnostic sans fuiter le token Xtream.
          'hostname': Uri.tryParse(url)?.host ?? '<invalide>',
        },
      );
    }

    return result;
  }

  Future<StreamProbeResult> _probeOnce(
    String url, {
    Duration timeout = const Duration(seconds: 6),
    int maxRedirects = 5,
  }) async {
    // Phase 1+/B3 (2026-06-01) : strip d'un eventuel `?` de fin
    // (cas observe sur les URLs Xtream "http://.../live/USER/PASS/ID.ts?").
    // Le `?` vide est techniquement legal mais provoque des bugs
    // chez certains recepteurs DLNA (LG QNED816QA notamment) qui
    // refusent la session. On normalise ici, le reste du pipeline
    // recoit une URL clean.
    url = sanitizeStreamUrl(url);
    final Stopwatch sw = Stopwatch()..start();
    final HttpClient client = HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = timeout
      ..userAgent = _kUserAgent
      // On gère les redirects à la main pour les COMPTER et les EXPOSER
      // dans le résultat (info essentielle pour `shouldUseRelay`).
      ..autoUncompress = false;

    String currentUrl = url;
    int redirects = 0;

    try {
      while (redirects <= maxRedirects) {
        final Uri uri = Uri.parse(currentUrl);

        // GET avec Range:0-0 plutôt que HEAD : universellement
        // supporté (HEAD est souvent 405 sur les serveurs IPTV) et
        // un seul aller-retour. Le serveur renvoie 206 Partial Content
        // ou 200 (s'il ignore le Range), dans les deux cas on lit
        // juste les headers puis on drain.
        final HttpClientRequest req =
            await client.getUrl(uri).timeout(timeout);
        req.followRedirects = false;
        req.headers.add(HttpHeaders.rangeHeader, 'bytes=0-0');
        req.headers.add(HttpHeaders.acceptHeader, '*/*');

        final HttpClientResponse resp = await req.close().timeout(timeout);

        // --- Redirect ? ---
        if (resp.statusCode >= 300 && resp.statusCode < 400) {
          final String? loc = resp.headers.value(HttpHeaders.locationHeader);
          // Vider le body pour libérer la connexion
          await resp.drain<void>();
          if (loc == null) {
            return StreamProbeResult(
              originalUrl: url,
              finalUrl: currentUrl,
              success: false,
              redirectCount: redirects,
              errorCode: resp.statusCode,
              errorReason: 'Redirection sans destination',
              timeToFirstByte: sw.elapsedMilliseconds,
            );
          }
          // Resolve relative vs absolute
          // Phase 1+/B3 etendu (2026-06-01) : sanitize aussi le URL
          // redirige. Cas observe LG QNED816QA : le backend Xtream
          // renvoie une Location avec `?` orphelin
          // (http://185.245.1.237/live/u/p/123?) qui se propage au
          // recepteur. La sanitization du probe initial ne le
          // couvrait pas — d'ou le strip ici aussi.
          currentUrl = sanitizeStreamUrl(uri.resolve(loc).toString());
          redirects++;
          continue;
        }

        // --- 4xx auth ? ---
        if (resp.statusCode == 401 || resp.statusCode == 403) {
          await resp.drain<void>();
          return StreamProbeResult(
            originalUrl: url,
            finalUrl: currentUrl,
            success: false,
            redirectCount: redirects,
            requiresAuth: true,
            errorCode: resp.statusCode,
            errorReason: 'Authentification requise — token expiré ?',
            timeToFirstByte: sw.elapsedMilliseconds,
            mime: resp.headers.contentType?.mimeType,
          );
        }

        // --- 4xx/5xx générique ---
        if (resp.statusCode >= 400) {
          await resp.drain<void>();
          return StreamProbeResult(
            originalUrl: url,
            finalUrl: currentUrl,
            success: false,
            redirectCount: redirects,
            errorCode: resp.statusCode,
            errorReason:
                'Serveur indisponible (${resp.statusCode}) — réessaie plus tard',
            timeToFirstByte: sw.elapsedMilliseconds,
            mime: resp.headers.contentType?.mimeType,
          );
        }

        // --- 2xx OK ---
        final String? mime = resp.headers.contentType?.mimeType;
        final int? len = resp.contentLength == -1 ? null : resp.contentLength;
        final bool ranges =
            (resp.headers.value(HttpHeaders.acceptRangesHeader) ?? '')
                    .toLowerCase()
                    .contains('bytes') ||
                resp.statusCode == 206;
        await resp.drain<void>();
        return StreamProbeResult(
          originalUrl: url,
          finalUrl: currentUrl,
          success: true,
          mime: mime,
          contentLength: len,
          acceptsRanges: ranges,
          redirectCount: redirects,
          timeToFirstByte: sw.elapsedMilliseconds,
        );
      }
      // Trop de redirects
      return StreamProbeResult(
        originalUrl: url,
        finalUrl: currentUrl,
        success: false,
        redirectCount: redirects,
        errorReason: 'Trop de redirections — flux mal configuré',
        timeToFirstByte: sw.elapsedMilliseconds,
      );
    } on TimeoutException {
      return StreamProbeResult(
        originalUrl: url,
        finalUrl: currentUrl,
        success: false,
        redirectCount: redirects,
        errorReason: 'Le serveur ne répond pas — réessaie',
        timeToFirstByte: sw.elapsedMilliseconds,
      );
    } on SocketException catch (e) {
      return StreamProbeResult(
        originalUrl: url,
        finalUrl: currentUrl,
        success: false,
        redirectCount: redirects,
        errorReason: 'Connexion impossible (${e.osError?.message ?? "réseau"})',
        timeToFirstByte: sw.elapsedMilliseconds,
      );
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('[StreamProbe] $e');
      return StreamProbeResult(
        originalUrl: url,
        finalUrl: currentUrl,
        success: false,
        redirectCount: redirects,
        errorReason: 'Flux invalide',
        timeToFirstByte: sw.elapsedMilliseconds,
      );
    } finally {
      client.close(force: true);
    }
  }
}
