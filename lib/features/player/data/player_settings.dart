// =========================================================
//  player_settings.dart — Réglages utilisateur du lecteur
// =========================================================
//  Persistés avec shared_preferences pour rester d'une session
//  à l'autre. Utilisés par le `VideoPlayerScreen` pour
//  configurer le `media_kit.Player`.
// =========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mode d'affichage de la vidéo dans son conteneur.
enum AspectRatioMode {
  fit('Contenir', 'fit'),
  fill('Remplir', 'fill'),
  stretch('Étirer', 'stretch'),
  ratio169('16:9', '16_9'),
  ratio43('4:3', '4_3'),
  ratio219('2.39:1 (cinéma)', '2_39_1');

  const AspectRatioMode(this.label, this.code);

  final String label;
  final String code;

  static AspectRatioMode fromCode(String? code) {
    for (final AspectRatioMode m in values) {
      if (m.code == code) return m;
    }
    return AspectRatioMode.fit;
  }
}

/// Singleton des réglages player. Notifie ses observateurs
/// (Listenable) quand un réglage change → l'UI se rafraîchit.
class PlayerSettings extends ChangeNotifier {
  PlayerSettings._();
  static final PlayerSettings instance = PlayerSettings._();

  static const String _kBufferKey = 'player.buffer_seconds';
  static const String _kAspectKey = 'player.aspect_mode';
  static const String _kHwdecKey = 'player.hardware_decode';
  static const String _kStatsKey = 'player.show_stats';
  static const String _kSpeedKey = 'player.last_speed';

  /// Buffer en secondes (5 à 60). Plus c'est haut, plus
  /// la lecture résiste aux coupures réseau, mais plus
  /// la latence "live" augmente. 20s = bon compromis.
  int _bufferSeconds = 20;

  AspectRatioMode _aspectMode = AspectRatioMode.fit;

  /// Force le décodage hardware (recommandé pour 4K/8K).
  bool _hardwareDecode = true;

  /// Affiche l'overlay de statistiques (FPS, bitrate, etc.).
  bool _showStats = false;

  /// Dernière vitesse choisie (pour la restaurer entre flux).
  double _lastSpeed = 1.0;

  bool _loaded = false;

  // ----- Getters -----
  int get bufferSeconds => _bufferSeconds;
  AspectRatioMode get aspectMode => _aspectMode;
  bool get hardwareDecode => _hardwareDecode;
  bool get showStats => _showStats;
  double get lastSpeed => _lastSpeed;

  /// Taille du buffer en octets pour la config de media_kit.
  /// On vise ~1 Mo/s pour du HD, ~5 Mo/s pour du 4K, ~20 Mo/s
  /// pour du 8K. On prend large : 5 Mo/s pour rester safe.
  int get bufferBytes => _bufferSeconds * 5 * 1024 * 1024;

  // ----- Chargement initial -----

  Future<void> load() async {
    if (_loaded) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _bufferSeconds = prefs.getInt(_kBufferKey) ?? 20;
    _aspectMode = AspectRatioMode.fromCode(prefs.getString(_kAspectKey));
    _hardwareDecode = prefs.getBool(_kHwdecKey) ?? true;
    _showStats = prefs.getBool(_kStatsKey) ?? false;
    _lastSpeed = prefs.getDouble(_kSpeedKey) ?? 1.0;
    _loaded = true;
    notifyListeners();
  }

  // ----- Setters (persistance + notification) -----

  Future<void> setBufferSeconds(int value) async {
    final int clamped = value.clamp(5, 60);
    if (clamped == _bufferSeconds) return;
    _bufferSeconds = clamped;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBufferKey, clamped);
  }

  Future<void> setAspectMode(AspectRatioMode mode) async {
    if (mode == _aspectMode) return;
    _aspectMode = mode;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAspectKey, mode.code);
  }

  Future<void> setHardwareDecode(bool enabled) async {
    if (enabled == _hardwareDecode) return;
    _hardwareDecode = enabled;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHwdecKey, enabled);
  }

  Future<void> setShowStats(bool enabled) async {
    if (enabled == _showStats) return;
    _showStats = enabled;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kStatsKey, enabled);
  }

  Future<void> setLastSpeed(double speed) async {
    if (speed == _lastSpeed) return;
    _lastSpeed = speed;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kSpeedKey, speed);
  }
}
