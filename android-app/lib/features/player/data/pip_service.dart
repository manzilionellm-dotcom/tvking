// =========================================================
//  pip_service.dart — Pont Dart ↔ natif Android pour le PiP
// =========================================================
//  Wrapper fin au-dessus du MethodChannel
//  `com.manzilionellm.tvking/pip` câblé dans
//  android_overlay/google_cast/MainActivity.kt.
//
//  Pourquoi un service singleton :
//    - L'état "lecture en cours" doit être tenu UNE seule fois,
//      partout dans l'app (le natif Android n'a qu'une vue).
//    - Les events `onPipModeChanged` arrivent du natif et doivent
//      être routés vers le VideoPlayerScreen qui adapte son layout
//      (cache l'overlay, etc.).
//
//  Architecture :
//    Dart                       Natif (Kotlin)
//    ─────                      ──────────────
//    setPlaybackActive(true)  → playbackActive = true
//    setAspectRatio(16, 9)    → pipAspect = 16:9
//    enterPip()               → enterPictureInPictureMode(...)
//    [état du PiP]            ← onPipModeChanged(isInPip)
//
//  Sécurité : tous les appels natifs sont try/catch avec fallback,
//  pour qu'une vieille version Android (< 8 ou device sans PiP)
//  retombe gracieusement sur "rien ne se passe" au lieu de crasher.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// État du PiP côté natif. Stream pour permettre aux widgets de
/// rebuild quand on entre / sort du PiP.
class PipService extends ChangeNotifier {
  PipService._() {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  static final PipService instance = PipService._();

  /// MUST matcher EXACTEMENT le constant côté Kotlin
  /// (MainActivity.PIP_CHANNEL). Toute discordance = MissingPlugin
  /// silencieux côté natif.
  static const MethodChannel _channel =
      MethodChannel('com.manzilionellm.tvking/pip');

  bool _isInPipMode = false;
  bool _isSupported = false;
  bool _supportChecked = false;

  // Le service est unique : seul le propriétaire de sa notification Cast
  // reçoit l'arrêt utilisateur. Le jeton n'est ni une URL ni une préférence.
  String? _castStopSession;
  Future<void> Function()? _castStopHandler;

  /// True quand la fenêtre est actuellement en PiP. Lu par le
  /// VideoPlayerScreen pour cacher les overlays et fitter la vidéo.
  bool get isInPipMode => _isInPipMode;

  /// Cache du support PiP. Calculé une seule fois au premier
  /// `isSupported()` call (réseau / IO inutiles ensuite).
  Future<bool> isSupported() async {
    if (_supportChecked) return _isSupported;
    try {
      final bool? ok = await _channel.invokeMethod<bool>('isPipSupported');
      _isSupported = ok ?? false;
    } catch (e) {
      if (kDebugMode) debugPrint('[PiP] isSupported failed: $e');
      _isSupported = false;
    }
    _supportChecked = true;
    return _isSupported;
  }

  /// Signal "lecture en cours" au natif. Appelé à chaque play /
  /// pause / stop du lecteur. C'est le booléen que le natif lit
  /// dans `onUserLeaveHint` pour décider d'entrer ou non en PiP
  /// auto quand l'utilisateur appuie HOME.
  Future<void> setPlaybackActive(bool active) async {
    try {
      await _channel.invokeMethod<void>(
        'setPlaybackActive',
        <String, Object>{'active': active},
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[PiP] setPlaybackActive failed: $e');
    }
  }

  /// Ratio de la vidéo courante. 16:9 pour la majorité, 4:3 pour
  /// les vieilles diffusions, 21:9 pour le cinéma. Le natif clamp
  /// déjà les valeurs trop extrêmes (Android lève
  /// IllegalArgumentException pour < 0.4 ou > 2.39).
  Future<void> setAspectRatio({required int numerator, required int denominator}) async {
    try {
      await _channel.invokeMethod<void>(
        'setAspectRatio',
        <String, Object>{'num': numerator, 'den': denominator},
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[PiP] setAspectRatio failed: $e');
    }
  }

  /// Entre IMMÉDIATEMENT en PiP. Utilisé par le bouton manuel
  /// 'Mini-fenêtre' dans l'overlay du player. Retourne true si
  /// l'OS a pris l'appel, false sinon (device sans PiP, exception).
  Future<bool> enterPip() async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>('enterPip');
      return ok ?? false;
    } catch (e) {
      if (kDebugMode) debugPrint('[PiP] enterPip failed: $e');
      return false;
    }
  }

  // =========================================================
  //  Mode « Écouteurs » = AUDIO EN ARRIÈRE-PLAN (façon radio)
  // =========================================================
  //  Quand l'utilisateur tape « Écouteurs » dans le player, on :
  //    1. setAudioOnlyMode(true)  → le natif NE déclenche PLUS le PiP
  //       vidéo quand on quitte l'app (onUserLeaveHint l'ignore).
  //    2. startBackgroundAudio(title) → démarre un foreground service
  //       (PlaybackForegroundService) qui garde le process en vie +
  //       acquiert wakelock + wifilock → le son de media_kit/libmpv
  //       continue écran éteint / dans une autre app, avec une
  //       notification. À l'arrêt du mode (ou dispose) : stop.
  //  Tout est fail-open : sur un device sans le bridge, ça no-op et la
  //  lecture normale n'est pas affectée.

  /// Active/désactive le mode audio-seul côté natif. Quand `true`, le
  /// PiP vidéo est SUPPRIMÉ au passage en arrière-plan (c'est le service
  /// audio qui prend le relais).
  Future<void> setAudioOnlyMode(bool active) async {
    try {
      await _channel.invokeMethod<void>(
        'setAudioOnlyMode',
        <String, Object>{'active': active},
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[PiP] setAudioOnlyMode failed: $e');
    }
  }

  /// Démarre le service audio de fond (notification + locks). `title`
  /// s'affiche dans la notification (nom de la chaîne en cours).
  Future<void> startBackgroundAudio(
    String title, {
    String? castSessionId,
    String? castDescription,
    String? castStopLabel,
    Future<void> Function()? onCastStopRequested,
  }) async {
    if (castSessionId != null && onCastStopRequested != null) {
      // Poser le destinataire AVANT l'appel natif : l'utilisateur peut
      // toucher Arrêter avant même l'accusé de démarrage du service.
      _castStopSession = castSessionId;
      _castStopHandler = onCastStopRequested;
    }
    try {
      await _channel.invokeMethod<void>(
        'startBackgroundAudio',
        <String, Object>{
          'title': title,
          if (castSessionId != null) 'castSessionId': castSessionId,
          if (castDescription != null) 'castDescription': castDescription,
          if (castStopLabel != null) 'castStopLabel': castStopLabel,
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[PiP] startBackgroundAudio failed: $e');
    }
  }

  /// Arrête le service audio de fond (retire la notification + libère
  /// les locks). Idempotent.
  Future<void> stopBackgroundAudio({String? castSessionId}) async {
    if (castSessionId != null && castSessionId == _castStopSession) {
      _castStopSession = null;
      _castStopHandler = null;
    }
    try {
      await _channel.invokeMethod<void>(
        'stopBackgroundAudio',
        castSessionId == null ? null : <String, String>{'castSessionId': castSessionId},
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[PiP] stopBackgroundAudio failed: $e');
    }
  }

  /// Handler des appels natif → Dart. Le service NOVATUBE Play peut aussi
  /// demander l'arrêt de LA session Cast portée par sa notification. Au futur :
  /// `onMediaActionTriggered` pour les boutons play/pause dans
  /// la mini-fenêtre PiP (Android offre des contrôles natifs).
  Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'castStopRequested':
        final Object? arguments = call.arguments;
        if (arguments is! Map) return null;
        final Object? session = arguments['sessionId'];
        if (session is! String || session.isEmpty || session != _castStopSession) {
          return null;
        }
        final Future<void> Function()? stop = _castStopHandler;
        // Consommer avant await rend un doublon inoffensif. Un arrêt interne
        // ne crée jamais cet événement et ne peut donc pas reboucler ici.
        _castStopSession = null;
        _castStopHandler = null;
        await stop?.call();
        return null;
      case 'onPipModeChanged':
        final dynamic args = call.arguments;
        bool inPip = false;
        if (args is Map) {
          inPip = (args['inPip'] as bool?) ?? false;
        }
        if (_isInPipMode != inPip) {
          _isInPipMode = inPip;
          notifyListeners();
        }
        return null;
      default:
        return null;
    }
  }
}
