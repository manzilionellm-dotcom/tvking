// =========================================================
//  cast_network_diagnostic.dart — Diagnostic RÉSEAU du cast (sans caster)
// =========================================================
//  Objectif : distinguer « /cast-sign échoue depuis le téléphone » (réseau /
//  DNS / secret Worker manquant) de « le code route mal ». On n'interagit
//  JAMAIS avec la TV : ce sont 6 checks HTTP purs, en séquence, qui produisent
//  un rapport JSON copiable (même esprit que l'export du batch runner).
//
//  Le check CLÉ est le n°3 (/cast-sign) : s'il renvoie 503
//  {ok:false, error:'proxy_unconfigured'}, c'est que le secret Worker
//  CAST_PROXY_SECRET n'est pas posé → _signedCastProxyUrl renvoie null →
//  playStream retombe en local_hls_relay. Le n°6 appelle LA MÊME fonction que
//  playStream (_signedCastProxyUrl, exposée via diagnosticSignedCastProxyUrl)
//  pour trancher net entre réseau et routage.
// =========================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

import '../../channels/domain/channel.dart';
import '../../playlists/data/playlist_repository.dart';
import 'cast_diagnostics.dart' show kBuildCommit;
import 'cast_session_diagnostic.dart' show redactStreamUrl;
import 'google_cast_transport.dart';
import 'stream_probe.dart';

class CastNetworkDiagnostic {
  CastNetworkDiagnostic._();

  static const String _host = 'app.7themotion.com';
  static const String _base = 'https://app.7themotion.com';
  static const String _testUpstream = 'http://example.com/test.ts';

  /// Exécute les 6 checks EN SÉQUENCE, SANS caster, et renvoie un rapport JSON
  /// indenté (copiable). Ne jette jamais : toute erreur est capturée dans le
  /// check correspondant (exception complète + stack).
  static Future<String> run() async {
    final List<Map<String, dynamic>> checks = <Map<String, dynamic>>[];

    // 1. DNS
    checks.add(await _dnsCheck());
    // 2. HTTPS /cast-receiver
    checks.add(await _httpsCheck());
    // 3. CAST-SIGN (URL bidon) — LE check clé.
    final _SignResult signTest = await _castSignCheck(
      _testUpstream,
      checkName: 'cast-sign (url test)',
    );
    checks.add(signTest.json);

    // 4. CAST-SIGN RÉEL — finalUrl d'une vraie chaîne de la playlist.
    String? realUpstream;
    _SignResult? signReal;
    final Map<String, dynamic> realHeader = <String, dynamic>{
      'check': 'cast-sign (chaîne réelle)',
    };
    try {
      final Channel? ch = _firstChannel();
      if (ch == null) {
        realHeader['success'] = false;
        realHeader['error'] = 'Aucune chaîne dans la playlist courante';
        checks.add(realHeader);
      } else {
        realHeader['channel'] = ch.name;
        final StreamProbeResult probe =
            await StreamProbe.instance.probe(ch.streamUrl);
        realUpstream = probe.success ? probe.finalUrl : ch.streamUrl;
        realHeader['probeSuccess'] = probe.success;
        realHeader['finalUrl'] = redactStreamUrl(realUpstream);
        signReal = await _castSignCheck(
          realUpstream,
          checkName: 'cast-sign (chaîne réelle)',
          extra: realHeader,
        );
        checks.add(signReal.json);
      }
    } catch (e, st) {
      realHeader['success'] = false;
      realHeader['error'] = e.toString();
      realHeader['stack'] = _shortStack(st);
      checks.add(realHeader);
    }

    // 5. CAST-PROXY — fetch de l'URL signée du check 4 (64 Ko max, timeout 10 s).
    checks.add(await _castProxyCheck(signReal?.proxyUrl));

    // 6. CODE PATH — la MÊME fonction que playStream (_signedCastProxyUrl).
    checks.add(await _codePathCheck(realUpstream ?? _testUpstream));

    final Map<String, dynamic> report = <String, dynamic>{
      'meta': <String, dynamic>{
        'kind': 'cast-network-diagnostic',
        'generatedAt': DateTime.now().toIso8601String(),
        'buildCommit': kBuildCommit,
        'wifiSsid': await _wifiSsid(),
        'base': _base,
        'kCastUseCustomReceiver': kCastUseCustomReceiver,
        'kCastDebugOverlay': kCastDebugOverlay,
      },
      'checks': checks,
    };
    return const JsonEncoder.withIndent('  ').convert(report);
  }

  // ---- Check 1 : DNS ----------------------------------------------------
  static Future<Map<String, dynamic>> _dnsCheck() async {
    final Stopwatch sw = Stopwatch()..start();
    try {
      final List<InternetAddress> addrs = await InternetAddress.lookup(_host)
          .timeout(const Duration(seconds: 8));
      return <String, dynamic>{
        'check': 'dns',
        'success': addrs.isNotEmpty,
        'durationMs': sw.elapsedMilliseconds,
        'host': _host,
        'ips': addrs.map((InternetAddress a) => a.address).toList(),
      };
    } catch (e, st) {
      return _fail('dns', sw, e, st, extra: <String, dynamic>{'host': _host});
    }
  }

  // ---- Check 2 : HTTPS /cast-receiver -----------------------------------
  static Future<Map<String, dynamic>> _httpsCheck() async {
    final Stopwatch sw = Stopwatch()..start();
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final HttpClientRequest req = await client
          .getUrl(Uri.parse('$_base/cast-receiver'))
          .timeout(const Duration(seconds: 8));
      final HttpClientResponse resp =
          await req.close().timeout(const Duration(seconds: 8));
      final String body =
          await resp.transform(utf8.decoder).join().timeout(
                const Duration(seconds: 8),
              );
      return <String, dynamic>{
        'check': 'https-cast-receiver',
        'success': resp.statusCode == 200,
        'durationMs': sw.elapsedMilliseconds,
        'status': resp.statusCode,
        'bytes': body.length,
        'contentType': resp.headers.contentType?.toString(),
      };
    } catch (e, st) {
      return _fail('https-cast-receiver', sw, e, st);
    } finally {
      client.close(force: true);
    }
  }

  // ---- Checks 3 & 4 : /cast-sign ----------------------------------------
  static Future<_SignResult> _castSignCheck(
    String upstreamUrl, {
    required String checkName,
    Map<String, dynamic>? extra,
  }) async {
    final Stopwatch sw = Stopwatch()..start();
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    final Map<String, dynamic> out = <String, dynamic>{'check': checkName};
    if (extra != null) out.addAll(extra);
    try {
      final Uri uri = Uri.parse('$_base/cast-sign')
          .replace(queryParameters: <String, String>{'u': upstreamUrl});
      final HttpClientRequest req =
          await client.getUrl(uri).timeout(const Duration(seconds: 8));
      req.headers.add(HttpHeaders.acceptHeader, 'application/json');
      final HttpClientResponse resp =
          await req.close().timeout(const Duration(seconds: 8));
      final String raw =
          await resp.transform(utf8.decoder).join().timeout(
                const Duration(seconds: 8),
              );
      String? proxyUrl;
      Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        decoded = null;
      }
      // Corps JSON complet, avec l'URL signée redactée (token + crédentiels).
      Object? bodyForReport = decoded;
      if (decoded is Map<String, dynamic>) {
        if (decoded['url'] is String) {
          proxyUrl = decoded['url'] as String;
          final Map<String, dynamic> copy =
              Map<String, dynamic>.from(decoded);
          copy['url'] = _redactProxyUrl(proxyUrl);
          bodyForReport = copy;
        }
      } else {
        bodyForReport = raw.length > 500 ? raw.substring(0, 500) : raw;
      }
      out.addAll(<String, dynamic>{
        'success': resp.statusCode == 200 &&
            decoded is Map<String, dynamic> &&
            decoded['ok'] == true,
        'durationMs': sw.elapsedMilliseconds,
        'status': resp.statusCode,
        'body': bodyForReport,
      });
      return _SignResult(out, proxyUrl);
    } catch (e, st) {
      out.addAll(<String, dynamic>{
        'success': false,
        'durationMs': sw.elapsedMilliseconds,
        'error': e.toString(),
        'stack': _shortStack(st),
      });
      return _SignResult(out, null);
    } finally {
      client.close(force: true);
    }
  }

  // ---- Check 5 : /cast-proxy (64 Ko, timeout 10 s) ----------------------
  static Future<Map<String, dynamic>> _castProxyCheck(String? proxyUrl) async {
    if (proxyUrl == null) {
      return <String, dynamic>{
        'check': 'cast-proxy',
        'success': false,
        'skipped': true,
        'reason': 'Pas d\'URL signée (check 4 a échoué)',
      };
    }
    final Stopwatch sw = Stopwatch()..start();
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final HttpClientRequest req = await client
          .getUrl(Uri.parse(proxyUrl))
          .timeout(const Duration(seconds: 10));
      final HttpClientResponse resp =
          await req.close().timeout(const Duration(seconds: 10));
      int bytes = 0;
      final Completer<void> done = Completer<void>();
      final StreamSubscription<List<int>> sub = resp.listen(
        (List<int> chunk) {
          bytes += chunk.length;
          if (bytes >= 64 * 1024 && !done.isCompleted) done.complete();
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (Object e) {
          if (!done.isCompleted) done.completeError(e);
        },
        cancelOnError: true,
      );
      try {
        await done.future.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        // On a lu ce qu'on a pu ; le timeout n'est pas un échec en soi
        // (flux live infini) tant qu'on a reçu des octets.
      } finally {
        await sub.cancel();
      }
      return <String, dynamic>{
        'check': 'cast-proxy',
        'success': resp.statusCode == 200 && bytes > 0,
        'durationMs': sw.elapsedMilliseconds,
        'status': resp.statusCode,
        'contentType': resp.headers.contentType?.toString(),
        'bytesReceived': bytes,
        'url': _redactProxyUrl(proxyUrl),
      };
    } catch (e, st) {
      return _fail('cast-proxy', sw, e, st,
          extra: <String, dynamic>{'url': _redactProxyUrl(proxyUrl)});
    } finally {
      client.close(force: true);
    }
  }

  // ---- Check 6 : CODE PATH (même fonction que playStream) ---------------
  static Future<Map<String, dynamic>> _codePathCheck(String upstreamUrl) async {
    final Stopwatch sw = Stopwatch()..start();
    try {
      final String? signed =
          await GoogleCastTransport.diagnosticSignedCastProxyUrl(upstreamUrl);
      return <String, dynamic>{
        'check': 'code-path (_signedCastProxyUrl)',
        'success': signed != null,
        'durationMs': sw.elapsedMilliseconds,
        'returned': signed == null ? 'null' : 'url',
        // C'est CE que playStream verrait : url → cast_proxy ; null → relais.
        'playStreamWouldRoute':
            signed == null ? 'local_hls_relay (fallback)' : 'cast_proxy',
        if (signed != null) 'signedUrl': _redactProxyUrl(signed),
        'upstream': redactStreamUrl(upstreamUrl),
      };
    } catch (e, st) {
      return _fail('code-path (_signedCastProxyUrl)', sw, e, st);
    }
  }

  // ---- Helpers ----------------------------------------------------------
  static Channel? _firstChannel() {
    final List<Channel> all = PlaylistRepository.instance.currentChannels;
    for (final Channel c in all) {
      if (c.streamUrl.trim().isNotEmpty) return c;
    }
    return null;
  }

  static Future<String?> _wifiSsid() async {
    try {
      final String? ssid = await NetworkInfo().getWifiName();
      return ssid;
    } catch (e) {
      // Permission localisation refusée / non dispo → best-effort.
      return 'indisponible ($e)';
    }
  }

  static Map<String, dynamic> _fail(
    String check,
    Stopwatch sw,
    Object e,
    StackTrace st, {
    Map<String, dynamic>? extra,
  }) {
    final Map<String, dynamic> out = <String, dynamic>{
      'check': check,
      'success': false,
      'durationMs': sw.elapsedMilliseconds,
      'error': e.toString(),
      'stack': _shortStack(st),
    };
    if (extra != null) out.addAll(extra);
    return out;
  }

  /// Quelques premières lignes de la stack (assez pour situer, pas un pavé).
  static String _shortStack(StackTrace st) {
    final List<String> lines = st.toString().split('\n');
    return lines.take(6).join('\n');
  }

  /// Masque `t=` (token HMAC) et redacte le `u=` (upstream encodé, crédentiels).
  static String _redactProxyUrl(String url) {
    final Uri? u = Uri.tryParse(url);
    if (u == null) return '<url invalide>';
    final Map<String, String> q = Map<String, String>.from(u.queryParameters);
    if (!q.containsKey('u') && !q.containsKey('t')) return redactStreamUrl(url);
    if (q.containsKey('t')) q['t'] = '***';
    if (q.containsKey('u')) q['u'] = redactStreamUrl(q['u']!);
    return u.replace(queryParameters: q).toString();
  }
}

/// Résultat d'un check /cast-sign : le JSON du check + l'URL proxy signée
/// (pour chaîner vers le check /cast-proxy). [proxyUrl] est brute (non
/// redactée) car réutilisée pour le fetch réel du check 5.
class _SignResult {
  _SignResult(this.json, this.proxyUrl);
  final Map<String, dynamic> json;
  final String? proxyUrl;
}
