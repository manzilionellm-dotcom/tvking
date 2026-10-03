// =========================================================
//  home_source_pair.dart — La box déclare son code court
// =========================================================
//  L'accueil TV montre un QR. Avant de l'afficher avec le code,
//  on l'enregistre : POST /api/source-pair, avec le secret de la
//  box. Le Worker n'en garde que l'empreinte, pendant 20 minutes.
//
//  Si l'appel échoue (réseau, box pas encore enrôlée côté serveur
//  qui refuse, etc.), on renvoie quand même le lien avec la MAC
//  seule. Les appareils qui n'ont pas de secret enregistré
//  peuvent encore recevoir une source. On ne journalise ni le
//  code, ni l'adresse.
// =========================================================

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../device/data/device_secret.dart';
import '../../subscription/data/subscription_backend.dart';
import '../domain/home_source_link.dart';

/// Résultat prêt pour le QR. [code] est null quand le Worker n'a
/// pas accepté le code : le lien ne contient alors que la MAC.
class HomeSourceLink {
  const HomeSourceLink({required this.url, this.code});

  final String url;
  final String? code;
}

/// POST injecté par les tests. Le code de production utilise http.
typedef HomeSourcePairPost = Future<int> Function(
  Uri uri,
  Map<String, String> headers,
  String body,
);

/// Déclare un code neuf et renvoie le lien du QR.
///
/// `null` seulement si la MAC n'est pas de la forme attendue (l'écran
/// affiche encore « … » au premier cadre).
Future<HomeSourceLink?> publishHomeSourceLink({
  required String mac,
  String baseUrl = kSubscriptionBaseUrl,
  Random? random,
  HomeSourcePairPost? post,
}) async {
  final String? bare = homeSourcePortalUrl(baseUrl: baseUrl, mac: mac);
  if (bare == null) return null;

  final String code = mintHomeSourcePairCode(random ?? Random.secure());
  final String root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final Uri uri = Uri.parse('$root/api/source-pair');
  final String body = jsonEncode(<String, String>{
    'mac': mac.trim().toUpperCase(),
    'code': code,
  });

  Map<String, String> headers = <String, String>{
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };
  try {
    headers = await DeviceSecret.instance.headers(jsonBody: true);
  } catch (_) {
    // Sans secret local, on tente quand même : une box pas encore
    // enrôlée peut déclarer le code avec la MAC seule.
    if (kDebugMode) debugPrint('[HomeSourcePair] secret illisible');
  }

  try {
    final int status = post != null
        ? await post(uri, headers, body)
        : (await http
                .post(uri, headers: headers, body: body)
                .timeout(const Duration(seconds: 8)))
            .statusCode;
    if (status == 200) {
      final String? withPair = homeSourcePortalUrl(
        baseUrl: baseUrl,
        mac: mac,
        pair: code,
      );
      if (withPair != null) {
        return HomeSourceLink(url: withPair, code: code);
      }
    }
  } catch (_) {
    if (kDebugMode) debugPrint('[HomeSourcePair] déclaration impossible');
  }
  return HomeSourceLink(url: bare);
}
