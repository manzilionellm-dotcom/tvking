// =========================================================
//  vpn_status.dart — Détection « connexion protégée » (VPN actif)
// =========================================================
//  BUT (confidentialité) : dire à l'utilisateur si sa connexion passe par
//  un VPN. Quand un VPN est actif, son fournisseur d'accès Internet (FAI)
//  ne peut PAS voir ce qu'il regarde : tout le trafic est chiffré dans un
//  tunnel.
//
//  COMMENT — 100 % Dart pur, AUCUNE dépendance ajoutée :
//  un VPN crée toujours une interface réseau « tunnel » virtuelle
//  (tun0, ppp0, wg0, ipsec0, utun…). On liste les interfaces réseau de
//  l'appareil via `dart:io` et on regarde si l'une porte un nom typique
//  de VPN. C'est l'approche standard, sans plugin natif.
//
//  HONNÊTETÉ TECHNIQUE : c'est une HEURISTIQUE, fiable dans l'immense
//  majorité des cas (OpenVPN, WireGuard, IPSec, et toutes les apps VPN
//  Android — qui passent par `VpnService` — créent une interface « tun »).
//  Elle peut, rarement, ne pas reconnaître un VPN exotique. On s'en sert
//  donc UNIQUEMENT pour informer et guider l'utilisateur, jamais pour
//  bloquer quoi que ce soit.
// =========================================================
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

class VpnStatus {
  VpnStatus._();
  static final VpnStatus instance = VpnStatus._();

  /// État courant, observable par l'UI :
  ///   • `true`  = VPN détecté → connexion protégée
  ///   • `false` = aucun VPN détecté → connexion en clair pour le FAI
  ///   • `null`  = encore inconnu / impossible à déterminer
  final ValueNotifier<bool?> active = ValueNotifier<bool?>(null);

  Timer? _timer;

  /// Préfixes de noms d'interfaces réseau créés par les VPN courants.
  /// (on compare en minuscules avec `startsWith`).
  static const List<String> _vpnPrefixes = <String>[
    'tun', // OpenVPN + la plupart des apps VPN Android (VpnService)
    'tap', // OpenVPN en mode pont
    'ppp', // PPTP et divers
    'pptp',
    'l2tp',
    'ipsec', // IKEv2 / IPSec
    'utun', // iOS / macOS
    'wg', // WireGuard
    'nordlynx', // NordVPN (WireGuard)
    'proton', // ProtonVPN
  ];

  /// Vérifie MAINTENANT si un VPN est actif et met [active] à jour.
  /// Renvoie aussi le résultat pour un usage ponctuel.
  Future<bool> check() async {
    try {
      final List<NetworkInterface> ifaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: true,
        type: InternetAddressType.any,
      );
      final bool on = ifaces.any((NetworkInterface i) {
        final String name = i.name.toLowerCase();
        return _vpnPrefixes.any((String p) => name.startsWith(p));
      });
      active.value = on;
      return on;
    } catch (e) {
      // Certaines box refusent l'énumération réseau : on reste sur « inconnu »
      // plutôt que d'affirmer à tort que rien n'est protégé.
      debugPrint('VpnStatus.check: énumération réseau impossible ($e)');
      active.value = null;
      return false;
    }
  }

  /// Démarre une vérification PÉRIODIQUE (4 s par défaut) : l'écran
  /// « Connexion protégée » réagit ainsi en direct quand l'utilisateur
  /// active/désactive son VPN sans quitter l'app.
  void start({Duration interval = const Duration(seconds: 4)}) {
    check();
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => check());
  }

  /// Arrête la vérification périodique (à appeler au dispose de l'écran).
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
