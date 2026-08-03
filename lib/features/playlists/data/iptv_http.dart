// =========================================================
//  iptv_http.dart — Client HTTP pour les SERVEURS IPTV des fournisseurs
// =========================================================
//  Les panels/serveurs IPTV en https:// ont très souvent un certificat
//  auto-signé, expiré ou émis pour un autre nom d'hôte. Le HttpClient
//  par défaut les rejette (HandshakeException) AVANT même d'envoyer la
//  requête → toutes les signatures de lecteur échouent → « le serveur a
//  refusé les N signatures » pour une source pourtant valide. Les
//  lecteurs du marché (IBO, Smarters, TiviMate, VLC) acceptent ces
//  certificats — on s'aligne.
//
//  PÉRIMÈTRE STRICT : ce client ne sert QUE pour parler aux serveurs
//  IPTV fournis par l'utilisateur/le revendeur (téléchargement M3U,
//  API Xtream, health-check). Les appels vers NOTRE backend/Worker
//  gardent la validation TLS standard — ne jamais l'utiliser là-bas.
// =========================================================

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../../core/net/doh_resolver.dart';

/// Crée un client HTTP tolérant aux certificats invalides, destiné aux
/// serveurs IPTV tiers uniquement. À fermer (`close()`) après usage,
/// comme tout `http.Client`.
///
/// RÉSOLUTION DoH : les domaines wildcard des panels bloqués par le DNS
/// opérateur (terrain 2026-07-08) sont résolus par l'app elle-même en
/// DNS-over-HTTPS quand le DNS système échoue — cf. `installDohResolution`.
http.Client createIptvHttpClient() {
  final HttpClient inner = HttpClient()
    ..badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
  installDohResolution(inner, acceptInvalidCertificate: true);
  return IOClient(inner);
}
