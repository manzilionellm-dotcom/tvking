// =========================================================
//  remote_platform.dart — De la touche au système Android
// =========================================================
//  Les flèches, OK, Retour et Chaîne sont de VRAIES touches
//  envoyées à NOTRE activité (pas à une autre application : on
//  n'a pas le droit « injecter des touches », et on ne le demande
//  pas). L'app les reçoit comme si la télécommande physique avait
//  été pressée : tous les écrans déjà écrits pour le D-pad
//  fonctionnent sans être réécrits.
//
//  Le VOLUME ne passe PAS par une touche du lecteur. On demande à
//  Android de monter ou baisser d'UN cran le volume média du
//  système (la barre que l'utilisateur connaît). On ne touche ni
//  au son du carrousel, ni au lecteur vidéo.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/remote_command.dart';

/// Même canal que l'identité de l'appareil : le plugin Android
/// `tvking_device` répond à `remoteKey` et `remoteVolume`.
const MethodChannel _channel = MethodChannel('com.manzilionellm.tvking/device');

/// Codes Android (KeyEvent). Volontairement PAS de touche volume :
/// le volume système a son propre appel.
int androidKeyCodeFor(RemoteButton button) {
  switch (button) {
    case RemoteButton.up:
      return 19; // KEYCODE_DPAD_UP
    case RemoteButton.down:
      return 20; // KEYCODE_DPAD_DOWN
    case RemoteButton.left:
      return 21; // KEYCODE_DPAD_LEFT
    case RemoteButton.right:
      return 22; // KEYCODE_DPAD_RIGHT
    case RemoteButton.ok:
      return 23; // KEYCODE_DPAD_CENTER
    case RemoteButton.back:
      return 4; // KEYCODE_BACK
    case RemoteButton.channelUp:
      return 166; // KEYCODE_CHANNEL_UP
    case RemoteButton.channelDown:
      return 167; // KEYCODE_CHANNEL_DOWN
    case RemoteButton.volumeUp:
    case RemoteButton.volumeDown:
      return -1;
  }
}

class RemotePlatform {
  const RemotePlatform._();

  static Future<void> press(RemoteButton button) async {
    if (button == RemoteButton.volumeUp) {
      await _volume(1);
      return;
    }
    if (button == RemoteButton.volumeDown) {
      await _volume(-1);
      return;
    }
    final int code = androidKeyCodeFor(button);
    if (code < 0) return;
    try {
      await _channel.invokeMethod<void>('remoteKey', <String, Object>{
        'code': code,
      });
    } catch (e) {
      debugPrint('[remote] touche non délivrée');
    }
  }

  static Future<void> _volume(int dir) async {
    try {
      await _channel.invokeMethod<void>('remoteVolume', <String, Object>{
        'dir': dir,
      });
    } catch (e) {
      debugPrint('[remote] volume non délivré');
    }
  }
}
