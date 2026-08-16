// ============================================================================
//  pairing_service.dart — Appairage « ZÉRO FRAPPE » (QR), côté TV.
//
//  Le point noir de toutes les apps IPTV : saisir un serveur Xtream et ses
//  identifiants À LA TÉLÉCOMMANDE (20 min, des fautes de frappe, des appels
//  au support). Ici la TV ouvre une session d'appairage, affiche un QR + un
//  code à 6 chiffres ; le client remplit le formulaire sur SON TÉLÉPHONE
//  (vrai clavier), et la TV récupère les identifiants toute seule.
//
//  SÉCURITÉ (deux jetons distincts, cf. worker.js) :
//   • `code` (6 chiffres, affiché) → sert seulement à ÉCRIRE (le téléphone
//     dépose) ;
//   • `token` (secret, jamais affiché) → sert seulement à LIRE (la TV
//     relève). Deviner le code ne permet donc PAS de lire les identifiants
//     de quelqu'un d'autre. Session à usage unique, expirée après 10 min.
// ============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../subscription/data/subscription_backend.dart'
    show kSubscriptionBaseUrl;

/// Session ouverte par la TV : ce qu'on affiche + le jeton de relève.
class PairingSession {
  const PairingSession({
    required this.code,
    required this.token,
    required this.url,
    required this.expiresIn,
  });

  /// Code à 6 chiffres — AFFICHABLE (écriture seule côté téléphone).
  final String code;

  /// Jeton SECRET de relève — ne jamais afficher ni journaliser.
  final String token;

  /// URL encodée dans le QR (page téléphone).
  final String url;

  final Duration expiresIn;
}

/// Identifiants déposés par le téléphone.
class PairedSource {
  const PairedSource({
    required this.isXtream,
    required this.name,
    this.server,
    this.username,
    this.password,
    this.m3uUrl,
  });

  final bool isXtream;
  final String name;
  final String? server;
  final String? username;
  final String? password;
  final String? m3uUrl;

  static PairedSource? fromJson(Map<String, dynamic> j) {
    final String kind = j['kind']?.toString() ?? '';
    final String name = (j['name']?.toString() ?? '').trim();
    if (kind == 'xtream') {
      final String s = (j['server']?.toString() ?? '').trim();
      final String u = (j['username']?.toString() ?? '').trim();
      final String p = (j['password']?.toString() ?? '').trim();
      if (s.isEmpty || u.isEmpty || p.isEmpty) return null;
      return PairedSource(
        isXtream: true,
        name: name.isEmpty ? 'Ma source' : name,
        server: s,
        username: u,
        password: p,
      );
    }
    if (kind == 'm3u') {
      final String u = (j['url']?.toString() ?? '').trim();
      if (u.isEmpty) return null;
      return PairedSource(
        isXtream: false,
        name: name.isEmpty ? 'Ma source' : name,
        m3uUrl: u,
      );
    }
    return null;
  }
}

enum PairingStatus { pending, ready, expired }

class PairingPoll {
  const PairingPoll(this.status, [this.source]);
  final PairingStatus status;
  final PairedSource? source;
}

class PairingService {
  PairingService._();
  static final PairingService instance = PairingService._();

  static const Duration _timeout = Duration(seconds: 12);

  /// Ouvre une session. Retourne null si le backend est injoignable —
  /// l'écran bascule alors sur la saisie manuelle (jamais de cul-de-sac).
  Future<PairingSession?> open() async {
    try {
      final http.Response r = await http
          .post(Uri.parse('$kSubscriptionBaseUrl/api/pair/new'))
          .timeout(_timeout);
      if (r.statusCode != 200) return null;
      final dynamic j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map<String, dynamic>) return null;
      final String code = j['code']?.toString() ?? '';
      final String token = j['token']?.toString() ?? '';
      final String url = j['url']?.toString() ?? '';
      if (code.isEmpty || token.isEmpty || url.isEmpty) return null;
      final int secs = j['expiresInSec'] is int ? j['expiresInSec'] as int : 600;
      return PairingSession(
        code: code,
        token: token,
        url: url,
        expiresIn: Duration(seconds: secs),
      );
    } catch (_) {
      return null;
    }
  }

  /// Relève le dépôt. Une erreur réseau ponctuelle renvoie `pending` (et
  /// non `expired`) : un Wi-Fi qui hoquette ne doit pas annuler
  /// l'appairage sous les yeux du client.
  Future<PairingPoll> poll(String token) async {
    try {
      final http.Response r = await http
          .get(Uri.parse(
              '$kSubscriptionBaseUrl/api/pair/poll?token=${Uri.encodeQueryComponent(token)}'))
          .timeout(_timeout);
      if (r.statusCode != 200) return const PairingPoll(PairingStatus.pending);
      final dynamic j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map<String, dynamic>) {
        return const PairingPoll(PairingStatus.pending);
      }
      switch (j['status']?.toString()) {
        case 'ready':
          final dynamic src = j['source'];
          final PairedSource? parsed = src is Map<String, dynamic>
              ? PairedSource.fromJson(src)
              : null;
          return parsed == null
              ? const PairingPoll(PairingStatus.expired)
              : PairingPoll(PairingStatus.ready, parsed);
        case 'expired':
          return const PairingPoll(PairingStatus.expired);
        default:
          return const PairingPoll(PairingStatus.pending);
      }
    } catch (_) {
      return const PairingPoll(PairingStatus.pending);
    }
  }
}
