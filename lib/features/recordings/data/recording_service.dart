// =========================================================
//  recording_service.dart — Wrapper du ForegroundService natif
// =========================================================
//  Quand l'utilisateur lance un enregistrement IPTV puis quitte
//  l'app pour lire un SMS / prendre un appel, Android peut tuer
//  notre process pour libérer de la mémoire — ce qui couperait
//  l'enregistrement libmpv en cours.
//
//  En démarrant un Foreground Service côté natif (Kotlin), on dit
//  à Android "ne me tue pas, je fais quelque chose d'important".
//  En contrepartie une notification persistante apparaît dans la
//  barre de statut tant que l'enregistrement dure.
//
//  Méthodes exposées (impl Kotlin dans RecordingServiceBridge.kt) :
//    - start(title) : true si le service a démarré
//    - stop()       : true (ferme le service + retire la notif)
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class RecordingService {
  RecordingService._();
  static final RecordingService instance = RecordingService._();

  static const MethodChannel _channel =
      MethodChannel('com.manzilionellm.tvking/recording_service');

  /// Démarre le ForegroundService natif avec [title] affiché dans
  /// la notification "Enregistrement en cours – $title".
  /// Best effort : ne throw jamais ; si le service ne démarre pas,
  /// l'enregistrement continue quand même mais sans la garantie
  /// anti-kill (l'OS peut le couper si on quitte l'app).
  ///
  /// Si [url] ET [filePath] sont fournis, le service enregistre
  /// NATIVEMENT (le téléchargement vit dans le service Android) : il
  /// survit donc à la fermeture de l'app par l'utilisateur (swipe),
  /// pendant des heures. Sans url/filePath, le service ne fait que
  /// maintenir le process en vie.
  Future<bool> start({
    required String title,
    String? url,
    String? filePath,
  }) async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'start',
        <String, dynamic>{
          'title': title,
          if (url != null) 'url': url,
          if (filePath != null) 'file': filePath,
        },
      );
      return ok ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[RecService] start error: ${e.message}');
      }
      return false;
    } on MissingPluginException {
      // Channel pas câblé côté natif (iOS, ou build sans overlay)
      return false;
    }
  }

  /// Octets écrits par l'enregistrement natif en cours (0 si inactif
  /// ou non supporté). Best effort.
  Future<int> bytes() async {
    try {
      final int? n = await _channel.invokeMethod<int>('bytes');
      return n ?? 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  /// Arrête le ForegroundService et retire la notification.
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<bool>('stop');
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[RecService] stop error: ${e.message}');
      }
    } on MissingPluginException {
      // ignore
    }
  }
}
