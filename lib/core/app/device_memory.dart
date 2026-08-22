// =========================================================
//  device_memory.dart — Palier de RAM de l'appareil (anti-OOM)
// =========================================================
//  SOURCE UNIQUE de la « classe mémoire » de l'appareil. On lit UNE fois
//  la RAM réelle via le plugin natif (MethodChannel
//  `com.manzilionellm.tvking/device`, méthode `getMemoryInfo`) puis on la
//  met en cache. Deux consommateurs l'utilisent pour ADAPTER leur empreinte :
//
//    1) le cache d'images Flutter (cf. guarded_main.dart) ;
//    2) le PLAFOND de chaînes gardées en RAM (cf. PlaylistRepository).
//
//  POURQUOI un palier : une box Fire TV / Android TV à 1 Go n'a pas le même
//  budget qu'une box 4 Go. Un plafond FIXE (50 000 chaînes) tient sur une
//  grosse box mais fait planter (kill mémoire natif = signal 9, NON
//  rattrapable) une petite box dès qu'on charge une grosse playlist. On
//  borne donc le plafond selon la RAM réelle.
//
// ISOLATS : ces champs statiques ne sont PAS partagés entre isolats
//  (le parsing M3U tourne dans un isolate `compute`). Là-bas, `isLoaded`
//  vaut `false` → on retombe sur le défaut prudent. Pour un plafond exact
//  côté isolate, PASSER la valeur en argument de `compute` (cf. parser).
// =========================================================
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Tient la « classe mémoire » de l'appareil (RAM totale + low-RAM Android).
abstract final class DeviceMemory {
  static const MethodChannel _channel =
      MethodChannel('com.manzilionellm.tvking/device');

  static int _totalMb = 0;
  static bool _lowRam = false;
  static bool _loaded = false;

  /// RAM totale en Mo (0 = inconnue).
  static int get totalMb => _totalMb;

  /// `true` si Android signale l'appareil comme « low RAM » (Go TV, vieux Fire).
  static bool get lowRam => _lowRam;

  /// `true` une fois la RAM lue (ou la tentative épuisée). Voir note isolats.
  static bool get isLoaded => _loaded;

  // =========================================================
  //  PALIERS PARTAGÉS (demande client du 22/08 : « ça doit marcher même
  //  sur un petit Android à 256 Mo — passe-partout »)
  // =========================================================
  //  Avant, chaque endroit ré-écrivait sa propre condition (« lowRam ou
  //  ≤1024 »), avec deux défauts : (a) beaucoup de téléphones bon marché
  //  ne DÉCLARENT pas `isLowRamDevice` alors qu'ils ont 512 Mo ou moins —
  //  ils passaient donc dans le profil confortable ; (b) rien ne
  //  distinguait un 256 Mo d'un 768 Mo. Deux paliers nommés, utilisés
  //  partout, corrigent les deux.

  /// APPAREIL MINUSCULE (≤ 512 Mo) : chaque mégaoctet compte, l'OS tue
  /// l'app à la moindre pointe. Profil le plus serré de l'app.
  /// Tant que la RAM est inconnue on répond `false` : on ne dégrade jamais
  /// un appareil correct sur une simple incertitude (le palier [isSmall],
  /// lui, reste prudent par défaut).
  static bool get isTiny => _loaded && _totalMb > 0 && _totalMb <= 512;

  /// PETIT APPAREIL (≤ 1 Go, ou signalé « low RAM » par Android) : profil
  /// économe — c'est le seuil historique, désormais nommé une seule fois.
  static bool get isSmall =>
      _lowRam || isTiny || (_loaded && _totalMb > 0 && _totalMb <= 1024);

  /// Lit la RAM réelle UNE fois et met en cache. Idempotent et best-effort :
  /// si l'info n'est pas dispo (échec plugin), on garde le défaut prudent.
  /// À `await` tôt au démarrage, AVANT le 1er import (pour un plafond exact).
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final Object? raw =
          await _channel.invokeMethod<Object?>('getMemoryInfo');
      if (raw is Map) {
        _totalMb = (raw['totalMb'] as num?)?.toInt() ?? 0;
        _lowRam = raw['lowRam'] == true;
      }
    } catch (_) {
      // RAM inconnue → on garde les défauts (prudents).
    }
    _loaded = true;
    if (kDebugMode) {
      debugPrint('[DeviceMemory] totalMb=$_totalMb lowRam=$_lowRam '
          '→ plafond chaînes=$channelCap');
    }
  }

  /// Plafond de chaînes MATÉRIALISÉES EN RAM, par palier de RAM.
  ///
  /// Coût mémoire approximatif d'UN objet `Channel` une fois chargé : l'objet
  /// Dart + ses chaînes (id, name, category, streamUrl ~100+ car., logoUrl) ≈
  /// **0,4–0,8 Ko**. On retient ~0,6 Ko/chaîne pour le dimensionnement.
  ///
  /// PALIERS RELEVÉS (« prends tout comme ça vient », proportionnel à la RAM) :
  ///   • ≤ 1 Go / low-RAM →    5 000  (marge minuscule : on protège d'abord)
  ///   • ≤ 2 Go           →   25 000
  ///   • ≤ 3 Go           →   80 000
  ///   • ≤ 4 Go           →  200 000  (~120 Mo d'objets Channel)
  ///   • ≤ 6 Go           →  450 000
  ///   • > 6 Go           →  800 000  (~480 Mo — box haut de gamme)
  ///
  /// Les petites box restent PROTÉGÉES (le crash OOM en boucle est
  /// irrécupérable) ; les grosses box encaissent des centaines de milliers de
  /// chaînes. Tant que la RAM n'est pas connue (`!isLoaded`, ex. isolate), on
  /// renvoie un plafond PRUDENT. Les chaînes au-delà du plafond restent EN
  /// BASE (rien n'est perdu), juste pas tenues en mémoire en même temps.
  static int get channelCap {
    if (!_loaded) return 8000;
    // 256-512 Mo (demande client « passe-partout ») : une liste de 5 000
    // chaînes en mémoire, c'est déjà plus que ce que l'OS laisse à l'app
    // entière. On tient 1 500 chaînes vivantes — le reste attend en base,
    // rien n'est perdu (recherche et navigation les retrouvent).
    if (isTiny) return 1500;
    if (isSmall) return 5000;
    if (_totalMb <= 2048) return 25000;
    if (_totalMb <= 3072) return 80000;
    if (_totalMb <= 4096) return 200000;
    if (_totalMb <= 6144) return 450000;
    return 800000;
  }

  /// Largeur de DÉCODAGE d'une affiche (memCacheWidth) pour une largeur
  /// LOGIQUE d'affichage donnée. Un bitmap décodé coûte largeur×hauteur×4
  /// octets : décoder à ×2 (netteté sur écrans denses) QUADRUPLE la RAM
  /// par rapport à ×1. Terrain 21/08 (« l'app doit marcher même sur un
  /// téléphone à 512 Mo ») : sur les petits appareils — dont l'écran est
  /// d'ailleurs rarement dense — on décode à ×1,25 : le Cinéma affiche
  /// des dizaines d'affiches sans pousser l'app vers le kill mémoire.
  static int posterCacheWidth(double logicalWidth) {
    // ≤512 Mo : décodage à la taille EXACTE d'affichage (×1). L'affiche est
    // un peu moins nette sur un écran dense — mais sur ces téléphones,
    // l'écran ne l'est pas, et c'est ce qui évite le kill mémoire.
    if (isTiny) return logicalWidth.round();
    return (logicalWidth * (isSmall ? 1.25 : 2.0)).round();
  }

  /// Plafond d'OCTETS téléchargés à l'import (M3U), par palier de RAM. Le
  /// fetcher STREAME (il ne matérialise pas le corps entier) et coupe au-delà,
  /// donc ce plafond borne surtout la taille de source ACCEPTÉE — relevé pour
  /// les grosses box afin de laisser passer des playlists de centaines de
  /// milliers de chaînes, tout en gardant les petites box prudentes.
  static int get m3uByteCap {
    if (!_loaded) return 60 * 1024 * 1024;
    if (_lowRam || _totalMb <= 1024) return 60 * 1024 * 1024;
    if (_totalMb <= 2048) return 120 * 1024 * 1024;
    if (_totalMb <= 4096) return 300 * 1024 * 1024;
    return 700 * 1024 * 1024;
  }

  /// Idem pour une réponse JSON Xtream (plus lourde que le M3U équivalent).
  static int get xtreamJsonByteCap {
    if (!_loaded) return 80 * 1024 * 1024;
    if (_lowRam || _totalMb <= 1024) return 80 * 1024 * 1024;
    if (_totalMb <= 2048) return 160 * 1024 * 1024;
    if (_totalMb <= 4096) return 400 * 1024 * 1024;
    return 900 * 1024 * 1024;
  }
}
