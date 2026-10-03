// =========================================================
//  audio_mode_guard.dart — Demande le mode normal (téléphone)
// =========================================================
//  Le lecteur du téléphone est mpv (media_kit), pas la vue TV.
//  Cette fonction est le seul pont : elle parle à Android
//  SEULEMENT si l'interrupteur est allumé.
//
//  Coupé (le défaut) : on revient tout de suite. Aucun canal,
//  aucun setMode, aucun haut-parleur d'appel touché.
//
//  Allumé : avant d'ouvrir le flux, on demande le mode normal.
//  La phrase de retour part dans le journal (logcat), pas au panel.
// =========================================================

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:native_video_player/native_video_player.dart';

abstract final class AudioModeGuardClient {
  static const MethodChannel _channel = MethodChannel(
    'com.manzilionellm.native_video_player/audio_mode',
  );

  /// Même drapeau que la vue TV. Faux tant que personne ne l'allume.
  static bool get enabled => NativeVideoController.normalizeAudioMode;

  /// Null si l'interrupteur est coupé ou si on n'est pas sur Android.
  static Future<String?> applyIfEnabled() async {
    if (!enabled) return null;
    try {
      if (!Platform.isAndroid) return null;
    } catch (_) {
      return null;
    }
    try {
      final String? line = await _channel
          .invokeMethod<String>('apply', true)
          .timeout(const Duration(seconds: 2));
      if (line != null && line.isNotEmpty) {
        debugPrint('[Garde mode] $line');
      }
      return line;
    } catch (e) {
      debugPrint('[Garde mode] appel non fait : $e');
      return null;
    }
  }
}
