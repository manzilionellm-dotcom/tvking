// =========================================================
//  tv_remote_map.dart — Une touche, une action, toutes les box
// =========================================================
//  Les télécommandes n'envoient pas les mêmes codes :
//    • Android TV : D-pad, OK = DPAD_CENTER ou ENTER
//    • boîtier infrarouge bon marché : souvent NUMPAD_ENTER,
//      PAGE_UP ou CHANNEL_UP à la place des flèches
//    • manette : BUTTON_A valide, BUTTON_B revient
//    • Fire TV, Mi Box, Shield, Formuler, style MAG :
//      INFO, GUIDE, MENU, média lecture / retour / avance
//    • clavier Bluetooth : les mêmes touches logiques
//
//  Flutter nomme déjà beaucoup de ces touches. Celles qu'il
//  laisse dans le plan Android (code brut) sont lues ici aussi,
//  avec les numéros de KeyEvent d'Android. Aucune touche n'est
//  inventée : si on ne la connaît pas, on renvoie null et
//  l'écran décide (souvent : on laisse passer).
// =========================================================

import 'package:flutter/services.dart';

/// Ce que la touche doit faire, quel que soit le boîtier.
enum TvRemoteAction {
  select,
  back,
  up,
  down,
  left,
  right,
  pageUp,
  pageDown,
  channelUp,
  channelDown,
  playPause,
  play,
  pause,
  rewind,
  fastForward,
  stop,
  menu,
  info,
  guide,
  digit,
}

class TvRemoteEvent {
  const TvRemoteEvent(this.action, {this.digit});

  final TvRemoteAction action;

  /// 0–9 quand [action] est [TvRemoteAction.digit].
  final int? digit;
}

/// Plan des touches Android dans [LogicalKeyboardKey.keyId].
const int _kAndroidPlane = 0x01100000000;
const int _kPlaneMask = 0x0FF00000000;

/// Code KeyEvent Android, ou null si la touche n'est pas de ce plan.
int? tvAndroidKeyCode(LogicalKeyboardKey key) {
  if ((key.keyId & _kPlaneMask) != _kAndroidPlane) return null;
  final int code = key.keyId & 0xFFFFFFFF;
  if (code <= 0 || code > 0xFFFF) return null;
  return code;
}

/// Lecture unique. Les touches nommées passent d'abord : un test
/// sur ordinateur et une box parlent alors le même langage.
TvRemoteEvent? readTvRemoteKey(LogicalKeyboardKey key) {
  final TvRemoteEvent? named = _named(key);
  if (named != null) return named;
  final int? code = tvAndroidKeyCode(key);
  if (code == null) return null;
  return _android(code);
}

TvRemoteEvent? _named(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.gameButtonA ||
      key == LogicalKeyboardKey.gameButtonSelect ||
      key == LogicalKeyboardKey.space) {
    return const TvRemoteEvent(TvRemoteAction.select);
  }
  if (key == LogicalKeyboardKey.goBack ||
      key == LogicalKeyboardKey.escape ||
      key == LogicalKeyboardKey.browserBack ||
      key == LogicalKeyboardKey.exit ||
      key == LogicalKeyboardKey.gameButtonB) {
    return const TvRemoteEvent(TvRemoteAction.back);
  }
  if (key == LogicalKeyboardKey.arrowUp) {
    return const TvRemoteEvent(TvRemoteAction.up);
  }
  if (key == LogicalKeyboardKey.arrowDown) {
    return const TvRemoteEvent(TvRemoteAction.down);
  }
  if (key == LogicalKeyboardKey.arrowLeft) {
    return const TvRemoteEvent(TvRemoteAction.left);
  }
  if (key == LogicalKeyboardKey.arrowRight) {
    return const TvRemoteEvent(TvRemoteAction.right);
  }
  if (key == LogicalKeyboardKey.pageUp) {
    return const TvRemoteEvent(TvRemoteAction.pageUp);
  }
  if (key == LogicalKeyboardKey.pageDown) {
    return const TvRemoteEvent(TvRemoteAction.pageDown);
  }
  if (key == LogicalKeyboardKey.channelUp ||
      key == LogicalKeyboardKey.mediaTrackPrevious) {
    return const TvRemoteEvent(TvRemoteAction.channelUp);
  }
  if (key == LogicalKeyboardKey.channelDown ||
      key == LogicalKeyboardKey.mediaTrackNext) {
    return const TvRemoteEvent(TvRemoteAction.channelDown);
  }
  if (key == LogicalKeyboardKey.mediaPlayPause) {
    return const TvRemoteEvent(TvRemoteAction.playPause);
  }
  if (key == LogicalKeyboardKey.mediaPlay) {
    return const TvRemoteEvent(TvRemoteAction.play);
  }
  if (key == LogicalKeyboardKey.mediaPause) {
    return const TvRemoteEvent(TvRemoteAction.pause);
  }
  if (key == LogicalKeyboardKey.mediaRewind) {
    return const TvRemoteEvent(TvRemoteAction.rewind);
  }
  if (key == LogicalKeyboardKey.mediaFastForward) {
    return const TvRemoteEvent(TvRemoteAction.fastForward);
  }
  if (key == LogicalKeyboardKey.mediaStop) {
    return const TvRemoteEvent(TvRemoteAction.stop);
  }
  if (key == LogicalKeyboardKey.contextMenu) {
    return const TvRemoteEvent(TvRemoteAction.menu);
  }
  if (key == LogicalKeyboardKey.info) {
    return const TvRemoteEvent(TvRemoteAction.info);
  }
  if (key == LogicalKeyboardKey.guide) {
    return const TvRemoteEvent(TvRemoteAction.guide);
  }
  const List<LogicalKeyboardKey> digits = <LogicalKeyboardKey>[
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  const List<LogicalKeyboardKey> pad = <LogicalKeyboardKey>[
    LogicalKeyboardKey.numpad0,
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];
  final int row = digits.indexOf(key);
  if (row >= 0) return TvRemoteEvent(TvRemoteAction.digit, digit: row);
  final int num = pad.indexOf(key);
  if (num >= 0) return TvRemoteEvent(TvRemoteAction.digit, digit: num);
  return null;
}

/// Numéros KeyEvent Android (AOSP). Les boîtiers qui n'ont pas de
/// nom Flutter tombent ici : Formuler, MAG, infrarouge générique.
TvRemoteEvent? _android(int code) {
  switch (code) {
    case 23: // DPAD_CENTER
    case 66: // ENTER
    case 160: // NUMPAD_ENTER
    case 96: // BUTTON_A
    case 109: // BUTTON_SELECT
      return const TvRemoteEvent(TvRemoteAction.select);
    case 4: // BACK
    case 111: // ESCAPE
    case 97: // BUTTON_B
      return const TvRemoteEvent(TvRemoteAction.back);
    case 19:
      return const TvRemoteEvent(TvRemoteAction.up);
    case 20:
      return const TvRemoteEvent(TvRemoteAction.down);
    case 21:
      return const TvRemoteEvent(TvRemoteAction.left);
    case 22:
      return const TvRemoteEvent(TvRemoteAction.right);
    case 92:
      return const TvRemoteEvent(TvRemoteAction.pageUp);
    case 93:
      return const TvRemoteEvent(TvRemoteAction.pageDown);
    case 166: // CHANNEL_UP
    case 88: // MEDIA_PREVIOUS
      return const TvRemoteEvent(TvRemoteAction.channelUp);
    case 167:
    case 87: // MEDIA_NEXT
      return const TvRemoteEvent(TvRemoteAction.channelDown);
    case 85:
      return const TvRemoteEvent(TvRemoteAction.playPause);
    case 126:
      return const TvRemoteEvent(TvRemoteAction.play);
    case 127:
      return const TvRemoteEvent(TvRemoteAction.pause);
    case 89:
      return const TvRemoteEvent(TvRemoteAction.rewind);
    case 90:
      return const TvRemoteEvent(TvRemoteAction.fastForward);
    case 86:
      return const TvRemoteEvent(TvRemoteAction.stop);
    case 82: // MENU
      return const TvRemoteEvent(TvRemoteAction.menu);
    case 165: // INFO
      return const TvRemoteEvent(TvRemoteAction.info);
    case 172: // GUIDE
      return const TvRemoteEvent(TvRemoteAction.guide);
    default:
      if (code >= 7 && code <= 16) {
        return TvRemoteEvent(TvRemoteAction.digit, digit: code - 7);
      }
      if (code >= 144 && code <= 153) {
        return TvRemoteEvent(TvRemoteAction.digit, digit: code - 144);
      }
      return null;
  }
}
