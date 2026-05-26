// =========================================================
//  google_cast_api.dart — Bridge vers le Google Cast SDK natif
// =========================================================
//  Wrapper Dart au-dessus d'un MethodChannel custom qui parle
//  au code Kotlin (GoogleCastApi.kt) qui lui utilise les vraies
//  classes `CastContext`, `SessionManager`, `RemoteMediaClient`
//  du Google Cast SDK Android.
//
//  Pourquoi pas un plugin Flutter existant ?
//    - `floating: ^4` nous a explosé un build sur un mismatch JVM
//      (1.8 vs 11). On reste prudent.
//    - Les plugins community Cast sont peu maintenus.
//    - Le SDK Cast est stable, l'API tient en ~5 méthodes essentielles.
//      Tout faire à la main en MethodChannel = ZÉRO dépendance fragile.
//
//  Méthodes exposées (côté Kotlin, signatures identiques) :
//    - isCastAvailable() : bool  → vrai si Google Play Services présents
//    - showRoutePicker() : void  → ouvre le picker natif Cast
//    - loadMedia(streamUrl, title, mime?) : bool  → joue le flux
//    - play() / pause() / stop() : void
//    - disconnect() : void
//    - hasActiveSession() : bool
//
//  Les erreurs côté Kotlin sont remontées via `PlatformException` ;
//  on les transforme en `Exception(message)` côté Dart pour rester
//  compatible avec le `CastTransport` interface.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class GoogleCastApi {
  GoogleCastApi._();
  static final GoogleCastApi instance = GoogleCastApi._();

  /// Nom du channel — doit être IDENTIQUE côté Kotlin
  /// (GoogleCastApi.kt utilise le même).
  static const MethodChannel _channel =
      MethodChannel('com.manzilionellm.tvking/cast');

  /// `true` si Google Play Services + Cast Framework sont
  /// disponibles sur le device. Sur les phones sans Google
  /// Services (Huawei récents, custom ROMs sans GMS) ça renvoie
  /// `false` — l'app retombe alors sur le fallback navigateur.
  Future<bool> isCastAvailable() async {
    try {
      final bool? result =
          await _channel.invokeMethod<bool>('isCastAvailable');
      return result ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[GoogleCast] isCastAvailable: ${e.message}');
      return false;
    } on MissingPluginException {
      // Channel pas câblé côté natif (ex. iOS sans implémentation)
      return false;
    }
  }

  /// Ouvre le dialog natif de sélection de récepteur Cast
  /// (la "ChromeCast route picker dialog" qu'on connaît dans
  /// YouTube / Netflix). L'utilisateur tape sur sa TV, le SDK
  /// négocie la session. Pas de retour direct — on observe
  /// `hasActiveSession()` ensuite.
  Future<void> showRoutePicker() async {
    try {
      await _channel.invokeMethod<void>('showRoutePicker');
    } on PlatformException catch (e) {
      throw Exception('Impossible d\'ouvrir le sélecteur Cast: ${e.message}');
    }
  }

  /// Y a-t-il une session Cast active maintenant ?
  /// (l'utilisateur a déjà sélectionné une TV et le SDK est connecté)
  Future<bool> hasActiveSession() async {
    try {
      final bool? result =
          await _channel.invokeMethod<bool>('hasActiveSession');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Charge un flux sur la TV actuellement connectée.
  /// [mime] par défaut = `video/mp2t` (le format IPTV le plus courant).
  /// Retourne `true` si l'ordre a été pris ; la lecture effective dépend
  /// du décodeur de la TV — on observera `hasActiveSession()` pour suivre.
  Future<bool> loadMedia({
    required String streamUrl,
    required String title,
    String mime = 'video/mp2t',
    String? subtitle,
    String? imageUrl,
  }) async {
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'loadMedia',
        <String, dynamic>{
          'streamUrl': streamUrl,
          'title': title,
          'mime': mime,
          if (subtitle != null) 'subtitle': subtitle,
          if (imageUrl != null) 'imageUrl': imageUrl,
        },
      );
      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception('Cast loadMedia: ${e.message}');
    }
  }

  Future<void> play() async {
    try {
      await _channel.invokeMethod<void>('play');
    } on PlatformException catch (e) {
      throw Exception('Cast play: ${e.message}');
    }
  }

  Future<void> pause() async {
    try {
      await _channel.invokeMethod<void>('pause');
    } on PlatformException catch (e) {
      throw Exception('Cast pause: ${e.message}');
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // best effort
    }
  }

  /// Ferme la session Cast active. Le SDK envoie un signal de
  /// déconnexion à la TV qui revient à son état précédent.
  Future<void> disconnect() async {
    try {
      await _channel.invokeMethod<void>('disconnect');
    } on PlatformException {
      // best effort
    }
  }
}
