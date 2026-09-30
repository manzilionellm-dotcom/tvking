// =========================================================
//  voice_navigation.dart — Ouvrir la recherche sans gêner le direct
// =========================================================
//  Point unique : touche micro, phrase déjà reconnue par la box,
//  bouton « Recherche » de l'accueil.
//
//  Règle : si une chaîne (ou le direct avec aperçu) est ouverte,
//  TvActivity.isBusy est vrai. On NE navigue PAS et on NE lance PAS
//  le micro. Une phrase déjà reconnue est mise de côté et proposée
//  quand la lecture est finie. Le flux en cours n'est pas touché.
// =========================================================

import 'package:flutter/widgets.dart';

import '../../tv/core/tv_activity.dart';

/// Ce que l'écran de recherche branche pendant qu'il est visible.
class VoiceSearchHooks {
  const VoiceSearchHooks({required this.onText, required this.onListen});

  final void Function(String text) onText;
  final VoidCallback onListen;
}

abstract final class VoiceNavigation {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'zunoVoiceNav');

  /// Posé par [VoiceHotkey] : pousse réellement l'écran.
  static void Function(String query, {required bool autoListen})? pushSearch;

  static VoiceSearchHooks? _hooks;

  static String _pending = '';

  static void attach(VoiceSearchHooks hooks) {
    _hooks = hooks;
  }

  static void detach(VoiceSearchHooks hooks) {
    if (identical(_hooks, hooks)) _hooks = null;
  }

  static void stash(String text) {
    final String q = text.trim();
    if (q.isNotEmpty) _pending = q;
  }

  static String takePending() {
    final String q = _pending;
    _pending = '';
    return q;
  }

  /// Phrase reconnue, ou demande d'ouvrir la recherche.
  static void openSearch({String query = '', bool autoListen = false}) {
    final String q = query.trim();
    if (TvActivity.isBusy) {
      if (q.isNotEmpty) stash(q);
      return;
    }
    final VoiceSearchHooks? hooks = _hooks;
    if (hooks != null) {
      if (q.isNotEmpty) {
        hooks.onText(q);
      } else if (autoListen) {
        hooks.onListen();
      }
      return;
    }
    final void Function(String query, {required bool autoListen})? push =
        pushSearch;
    if (push == null) {
      if (q.isNotEmpty) stash(q);
      return;
    }
    push(q, autoListen: autoListen && q.isEmpty);
  }
}
