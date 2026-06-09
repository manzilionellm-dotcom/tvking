// =========================================================
//  native_http.dart — Accès au pont réseau natif (correctif « 884 »)
// =========================================================
//  Façade Dart au-dessus du MethodChannel
//  "com.manzilionellm.tvking/native_http" implémenté côté Android par
//  `android_overlay/google_cast/NativeHttpBridge.kt`.
//
//  POURQUOI : certains fronts anti-bot IPTV bloquent notre app avec un
//  code maison « HTTP 884 » à cause de l'empreinte TLS atypique de la
//  pile `dart:io`. Ce pont refait la requête avec `HttpURLConnection`
//  (pile TLS SYSTÈME Android = Conscrypt = la même que le navigateur et
//  IBO Player) → l'empreinte redevient « normale » et le front laisse
//  passer. Détails : docs/DIAGNOSTIC_HTTP_884.md.
//
//  Usage : `M3uFetcher` et `XtreamClient` essaient ce pont EN PREMIER,
//  puis retombent sur `dart:io` s'il est indisponible (iOS, vieil APK
//  sans l'overlay…) ou s'il échoue. Donc AUCUNE régression possible.
// =========================================================

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Réponse renvoyée par le pont natif.
class NativeHttpResponse {
  const NativeHttpResponse({
    required this.statusCode,
    required this.bodyBytes,
    this.finalUrl,
    this.contentType,
  });

  /// Code HTTP final (après redirections). Peut être un code « maison »
  /// non standard (ex. 884) si le serveur en renvoie un.
  final int statusCode;

  /// Corps brut de la réponse (déjà dé-gzippé par HttpURLConnection).
  final Uint8List bodyBytes;

  /// URL finale après les éventuelles redirections suivies nativement.
  final String? finalUrl;

  /// En-tête `Content-Type` de la réponse, si présent.
  final String? contentType;
}

abstract final class NativeHttp {
  static const MethodChannel _channel =
      MethodChannel('com.manzilionellm.tvking/native_http');

  /// Passe à `true` dès qu'on constate que le pont est ABSENT
  /// (MissingPluginException : iOS, build sans l'overlay natif…). On
  /// mémorise pour ne pas re-tenter — et pour que l'appelant saute
  /// directement à `dart:io`.
  static bool _unavailable = false;

  /// `false` une fois qu'on sait le pont natif indisponible sur ce build.
  static bool get isAvailable => !_unavailable;

  /// GET via la pile réseau SYSTÈME Android (contourne le « 884 »).
  ///
  /// Retourne `null` (sans lever) quand le pont est indisponible ou qu'une
  /// erreur réseau NATIVE survient — l'appelant doit alors retomber sur
  /// `dart:io`. Retourne une [NativeHttpResponse] dès qu'on a un code HTTP
  /// (même un code d'erreur comme 884, à charge de l'appelant de décider).
  static Future<NativeHttpResponse?> get(
    String url, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    if (_unavailable) return null;
    try {
      final Map<Object?, Object?>? res =
          await _channel.invokeMethod<Map<Object?, Object?>>(
        'get',
        <String, Object?>{'url': url, 'headers': headers},
      );
      if (res == null) return null;

      final int status = (res['status'] as int?) ?? -1;
      final Uint8List body = (res['body'] as Uint8List?) ?? Uint8List(0);
      final String? error = res['error'] as String?;

      // status < 0 = exception réseau côté natif (pas un blocage
      // applicatif) → on laisse l'appelant tenter dart:io.
      if (status < 0) {
        if (kDebugMode) {
          debugPrint('[NativeHttp] erreur réseau native: $error');
        }
        return null;
      }

      return NativeHttpResponse(
        statusCode: status,
        bodyBytes: body,
        finalUrl: res['finalUrl'] as String?,
        contentType: res['contentType'] as String?,
      );
    } on MissingPluginException {
      // Pas de pont natif (iOS, APK sans overlay) → indisponible pour de bon.
      _unavailable = true;
      if (kDebugMode) {
        debugPrint('[NativeHttp] pont natif absent → fallback dart:io');
      }
      return null;
    } catch (e) {
      // Toute autre erreur d'invocation → on retombe sur dart:io sans
      // marquer le pont indisponible (ça peut être ponctuel).
      if (kDebugMode) debugPrint('[NativeHttp] échec invoke: $e');
      return null;
    }
  }
}
