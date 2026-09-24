// =========================================================
//  cast_device.dart — Modèle "Récepteur de casting"
// =========================================================
//  Un récepteur DLNA / UPnP MediaRenderer découvert sur le
//  réseau local. Construit à partir d'une réponse SSDP +
//  description UPnP XML.
// =========================================================

import 'package:flutter/foundation.dart';

enum CastDeviceKind {
  /// MediaRenderer DLNA / UPnP (Fire TV via AirReceiver, Smart TV...)
  dlna,

  /// Google Cast — Chromecast natif, Google TV, Android TV avec
  /// Chromecast intégré (Sony, Philips, TCL, Hisense), Vizio
  /// SmartCast. Découvert via mDNS (`_googlecast._tcp.local`).
  chromecast,

  /// Roku TV ou dongle Roku. Découvert via SSDP avec ST
  /// `roku:ecp`. Pilotage via External Control Protocol (HTTP).
  roku,

  /// Alias historique — équivalent à [chromecast]. Conservé pour
  /// compatibilité du code existant.
  googleCast,
}

@immutable
class CastDevice {
  const CastDevice({
    required this.id,
    required this.name,
    required this.kind,
    required this.host,
    required this.port,
    required this.controlUrl,
    this.manufacturer,
    this.model,
  });

  /// Identifiant unique (USN SSDP ou UDN).
  final String id;

  /// Nom affichable ("Salon", "Fire TV", "TV Samsung").
  final String name;

  final CastDeviceKind kind;

  /// IP du device sur le LAN.
  final String host;
  final int port;

  /// URL absolue du service AVTransport (pour les commandes SOAP).
  final String controlUrl;

  final String? manufacturer;
  final String? model;

  /// Nom court "premium" pour l'UI — on retire les artefacts techy
  /// que les TVs balancent dans leur friendlyName SSDP/mDNS :
  ///   "[LG] webOS TV QNED816QA" → "LG webOS TV"
  ///   "Samsung TV UE55Q60T (Salon)" → "Samsung TV (Salon)"
  ///   "Salon" → "Salon"
  ///
  /// On garde [name] brut intact pour le diagnostic JSON et les logs ;
  /// uniquement les widgets UI affichent [displayName].
  String get displayName {
    String s = name;
    // 1) Retire les `[XX] ` ou `[XX]` en début (brackets brand)
    s = s.replaceFirst(RegExp(r'^\s*\[[^\]]+\]\s*'), '');
    // 2) Retire un suffixe modèle alphanumérique trapu en fin :
    //    "...QNED816QA", "...UE55Q60T", "...XR-65A95K" — pattern :
    //    un dernier mot d'au moins 6 char qui mélange majuscules+chiffres.
    s = s.replaceFirst(
      RegExp(r'\s+[A-Z]{2,}[-_]?[A-Z0-9]*[0-9]+[A-Z0-9]*\s*$'),
      '',
    );
    s = s.trim();
    // Garde-fou : si on a tout mangé, on revient au brut.
    return s.length < 2 ? name : s;
  }

  /// Marque reconnue de la TV (parmi les 10 plus répandues), ou `null` si
  /// inconnue. Détectée depuis le fabricant + le nom annoncés en SSDP/mDNS.
  /// Sert à l'AFFICHAGE (nom propre dans le sélecteur) et au DIAGNOSTIC
  /// (savoir tout de suite quelle marque échoue pour ajouter SON réglage
  /// ciblé). Ne change RIEN au protocole de cast : purement informatif.
  String? get brand => detectCastBrand(name, manufacturer);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is CastDevice && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

/// Détecte la marque de TV parmi les plus répandues mondialement à partir du
/// fabricant et/ou du nom convivial (SSDP friendlyName, mDNS). Renvoie une
/// étiquette normalisée (« Samsung », « LG », « Sony »…) ou `null` si aucune
/// ne correspond. Pur + sans effet de bord → testable et réutilisable.
///
/// IMPORTANT : ceci ne fait que NOMMER/RECONNAÎTRE la marque. Le réglage
/// SPÉCIFIQUE d'une marque (User-Agent, profil/MIME particulier) reste ajouté
/// au cas par cas à partir d'un diagnostic réel — on ne devine pas à l'aveugle
/// au risque de casser une TV qui marche déjà.
String? detectCastBrand(String name, String? manufacturer) {
  final String hay = '${manufacturer ?? ''} $name'.toLowerCase();
  // Table des 10 marques les plus vendues + alias/OS connus. Ordre : on
  // teste les indices les plus spécifiques d'abord (OS propriétaires).
  const List<List<String>> brands = <List<String>>[
    <String>['Samsung', 'samsung', 'tizen'],
    <String>['LG', 'lg electronics', 'webos', 'netcast', '[lg]'],
    <String>['Sony', 'sony', 'bravia'],
    <String>['TCL', 'tcl'],
    <String>['Hisense', 'hisense', 'vidaa'],
    <String>['Vizio', 'vizio', 'smartcast'],
    <String>['Philips', 'philips'],
    <String>['Panasonic', 'panasonic', 'viera'],
    <String>['Sharp', 'sharp', 'aquos'],
    <String>['Toshiba', 'toshiba', 'regza'],
  ];
  for (final List<String> entry in brands) {
    final String label = entry.first;
    for (final String token in entry.skip(1)) {
      if (hay.contains(token)) return label;
    }
  }
  return null;
}
