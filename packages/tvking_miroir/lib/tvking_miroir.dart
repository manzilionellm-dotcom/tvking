// =========================================================
//  tvking_miroir — voir l'écran du client, avec son accord
// =========================================================
//  Façade Dart du plugin Android (MediaProjection). Voir pubspec.yaml
//  pour le POURQUOI ; ici, le COMMENT côté Flutter.
//
//  TROIS APPELS, DANS CET ORDRE :
//    1. [demander]  — Android pose SA question au client (« 7 MOTION va
//                     commencer à capturer l'écran »). Répond `true`
//                     quand il a accepté. Une fois par session.
//    2. [capturer]  — un JPEG de l'écran, ou `null` si rien de neuf.
//    3. [arreter]   — libère la projection à la fin de la session.
//
//  TOUT EST FAIL-SOFT : hors Android, plugin absent, box trop vieille,
//  refus du client — on répond `false` / `null`, jamais une exception.
//  L'appelant (assistance_overlay.dart) retombe alors sur la capture
//  Flutter, qui, elle, DIT pourquoi elle ne peut pas.
// =========================================================

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Nom du MethodChannel natif (Android).
const String kTvkingMiroirChannel = 'com.manzilionellm.tvking/miroir';

class TvkingMiroir {
  TvkingMiroir._();

  static const MethodChannel _canal = MethodChannel(kTvkingMiroirChannel);

  /// Combien de temps on laisse au client pour répondre à la boîte de
  /// dialogue d'Android. Passé ce délai on considère qu'il a dit non :
  /// une question qui traîne à l'écran pendant qu'il regarde la télé
  /// n'est pas une question, c'est une gêne.
  static const Duration attenteAccord = Duration(seconds: 45);

  static bool? _disponibleCache;

  /// L'appareil sait-il projeter son écran ? `false` hors Android et sur
  /// toute erreur — on ne suppose jamais qu'un natif absent est présent.
  static Future<bool> get disponible async {
    if (kIsWeb || !Platform.isAndroid) return false;
    final bool? c = _disponibleCache;
    if (c != null) return c;
    try {
      final bool ok = await _canal.invokeMethod<bool>('disponible') ?? false;
      _disponibleCache = ok;
      return ok;
    } on MissingPluginException {
      // Build sans le plugin (ancien APK, autre plateforme) : on le note
      // une fois et on n'insiste plus.
      _disponibleCache = false;
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[Miroir] disponible: $e');
      return false;
    }
  }

  /// Pose la question au client. `true` = il a accepté, la projection est
  /// ouverte et [capturer] peut commencer.
  static Future<bool> demander() async {
    if (!await disponible) return false;
    try {
      return await _canal
              .invokeMethod<bool>('demander')
              .timeout(attenteAccord, onTimeout: () => false) ??
          false;
    } catch (e) {
      if (kDebugMode) debugPrint('[Miroir] demander: $e');
      return false;
    }
  }

  /// Un JPEG de l'écran, ou `null`.
  static Future<Uint8List?> capturer() async {
    try {
      return await _canal.invokeMethod<Uint8List>('capturer');
    } catch (e) {
      if (kDebugMode) debugPrint('[Miroir] capturer: $e');
      return null;
    }
  }

  /// Libère tout. À appeler à la fin de la session, sans faute : une
  /// projection qui reste ouverte, c'est une notification « partage
  /// d'écran » qui reste affichée chez le client alors que personne ne
  /// regarde plus.
  static Future<void> arreter() async {
    try {
      await _canal.invokeMethod<void>('arreter');
    } catch (_) {
      // Rien à libérer : sans conséquence.
    }
  }
}
