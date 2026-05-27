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

  /// Handler des appels natif → Dart. Pour l'instant un seul
  /// event : `onPipModeChanged` quand l'état PiP change. Au futur :
  /// `onMediaActionTriggered` pour les boutons play/pause dans
  /// la mini-fenêtre PiP (Android offre des contrôles natifs).
  Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
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
