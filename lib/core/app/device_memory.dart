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
//  ⚠️ ISOLATS : ces champs statiques ne sont PAS partagés entre isolats
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
  /// **0,4–0,8 Ko**. On retient ~0,6 Ko/chaîne pour le dimensionnement :
  ///
  ///   • ≤ 1 Go  →   5 000 chaînes  (box 1 Go : Flutter + ExoPlayer + logos +
  ///                 SQLite + cache images laissent TRÈS peu de marge ; 10 000
  ///                 objets Dart pouvaient encore déclencher le kill natif)
  ///   • ≤ 2 Go  →  15 000 chaînes
  ///   • > 2 Go  →  50 000 chaînes
  ///
  /// Tant que la RAM n'est pas connue (`!isLoaded`, ex. dans un isolate), on
  /// renvoie un plafond PRUDENT (8 000) : on protège d'abord les petites box.
  /// Les chaînes au-delà du plafond restent en base (rien n'est perdu), elles
  /// ne sont juste pas tenues en mémoire en même temps.
  static int get channelCap {
    if (!_loaded) return 8000;
    if (_lowRam || (_totalMb > 0 && _totalMb <= 1024)) return 5000;
    if (_totalMb <= 2048) return 15000;
    return 50000;
  }
}
