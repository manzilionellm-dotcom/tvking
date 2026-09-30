// =========================================================
//  lan_ipv4.dart — Quelle adresse montrer dans le QR
// =========================================================
//  Le téléphone ouvre une page servie PAR LA BOX, en HTTP simple,
//  sur le réseau de la maison. On ne retient qu'une IPv4 PRIVÉE
//  (celles des box et des téléphones : 192.168.x, 10.x, 172.16–31).
//
//  On écarte :
//    • l'adresse publique (la box ne doit pas être joignable d'Internet
//      même si le routeur transfère un port : le test d'adresse du
//      client, côté serveur, recoupe ça) ;
//    • la boucle locale 127.0.0.1 (inutile : le téléphone n'est pas
//      DANS la box) ;
//    • les interfaces virtuelles (VPN, Docker, 4G `rmnet`) : un VPN
//      en 10.x n'est pas le Wi-Fi du salon.
//
//  S'il y a le Wi-Fi ET le câble, on préfère le Wi-Fi : c'est le
//  réseau où se trouve le téléphone. S'il n'y a que le câble (cas
//  le plus courant d'une box), on prend le câble — le téléphone,
//  en Wi-Fi sur le MÊME routeur, l'atteint quand même.
// =========================================================

import 'dart:io' show InternetAddress, InternetAddressType;

class LanIface {
  const LanIface(this.name, this.addresses);
  final String name;
  final List<String> addresses;
}

/// Vrai pour 10.0.0.0/8, 172.16.0.0/12 et 192.168.0.0/16.
/// Faux pour le reste, y compris 127.0.0.1, 169.254.x (lien local)
/// et 100.64.x (réseau opérateur).
bool isPrivateLanIpv4(String host) {
  final List<String> parts = host.split('.');
  if (parts.length != 4) return false;
  final List<int> n = <int>[];
  for (final String part in parts) {
    if (part.isEmpty || part.length > 3) return false;
    final int? v = int.tryParse(part);
    if (v == null || v < 0 || v > 255) return false;
    n.add(v);
  }
  if (n[0] == 10) return true;
  if (n[0] == 192 && n[1] == 168) return true;
  if (n[0] == 172 && n[1] >= 16 && n[1] <= 31) return true;
  return false;
}

/// Le client TCP a-t-il le droit de parler à la télécommande ?
///
/// En production [allowLoopback] est faux : seule une adresse privée
/// (le téléphone sur le Wi-Fi) passe. Un client venu d'Internet
/// (adresse publique) est refusé, même s'il a deviné le port.
/// Les tests passent [allowLoopback] à vrai pour parler à 127.0.0.1.
bool remoteClientAllowed(InternetAddress address,
    {required bool allowLoopback}) {
  if (address.type != InternetAddressType.IPv4) return false;
  if (address.isLoopback) return allowLoopback;
  return isPrivateLanIpv4(address.address);
}

/// Meilleure IPv4 privée, ou null s'il n'y en a pas (box hors réseau :
/// on N'AFFICHE PAS de QR, on ne démarre pas de serveur).
String? pickLanIpv4(Iterable<LanIface> ifaces) {
  String? best;
  int bestScore = -1;
  for (final LanIface iface in ifaces) {
    final int score = _ifaceScore(iface.name);
    if (score < 0) continue;
    for (final String raw in iface.addresses) {
      if (!isPrivateLanIpv4(raw)) continue;
      if (score > bestScore) {
        bestScore = score;
        best = raw;
      }
    }
  }
  return best;
}

/// -1 = à ignorer. 30 = Wi-Fi. 20 = câble. 0 = autre interface privée
/// (partage de connexion de la box, par exemple).
int _ifaceScore(String name) {
  final String n = name.toLowerCase();
  if (_skipped(n)) return -1;
  if (n.contains('wlan') || n.contains('wifi') || n.contains('wl')) return 30;
  if (n.contains('eth') || n.contains('ethernet') || n.startsWith('en')) {
    return 20;
  }
  return 0;
}

bool _skipped(String n) {
  const List<String> bad = <String>[
    'lo',
    'docker',
    'br-',
    'bridge',
    'veth',
    'virbr',
    'tun',
    'tap',
    'ppp',
    'vpn',
    'wg',
    'rmnet',
    'dummy',
    'ccmni',
    'wwan',
    'awdl',
    'utun',
    'ipsec',
    'vbox',
    'vmnet',
    'p2p',
    'ifb',
    'gre',
  ];
  for (final String b in bad) {
    if (n == b || n.startsWith(b) || n.contains(b)) return true;
  }
  return false;
}
