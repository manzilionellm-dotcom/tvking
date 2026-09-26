// =========================================================
//  tv_back_guard.dart — Un appui sur « Retour » = UN SEUL pas en arrière
// =========================================================
//  Bug constaté (26/09/2026) : en regardant une chaîne, « Retour » ramenait
//  au MENU PRINCIPAL au lieu de la liste Direct.
//
//  Cause : un même appui Retour arrive DEUX fois dans l'app.
//    1. comme touche (KeyEvent « goBack ») — les lecteurs la gèrent eux-
//       mêmes pour être sûrs de ne jamais rester coincés, et ferment l'écran ;
//    2. comme « retour système » Android (popRoute), qui ferme alors l'écran
//       SUIVANT (Direct) → on atterrit sur l'accueil.
//
//  Correctif : quand un écran a déjà traité la touche Retour, il appelle
//  [TvBackGuard.markHandled] ; le « retour système » qui suit dans la foulée
//  (même appui) est ignoré. Un NOUVEL appui (plus tard) fonctionne
//  normalement. Aucun écran ne change d'apparence.
//
//  Doit être installé AVANT runApp : Flutter consulte les observateurs dans
//  l'ordre d'inscription, celui-ci passe donc avant le Navigator.
// =========================================================
import 'package:flutter/widgets.dart';

class TvBackGuard with WidgetsBindingObserver {
  TvBackGuard._();
  static final TvBackGuard _instance = TvBackGuard._();
  static bool _installed = false;

  /// Fenêtre pendant laquelle un « retour système » est considéré comme
  /// l'écho du même appui (un double appui humain volontaire est plus lent).
  static const Duration _window = Duration(milliseconds: 600);
  static DateTime _handledAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// À appeler une fois, avant runApp.
  static void install() {
    if (_installed) return;
    _installed = true;
    WidgetsBinding.instance.addObserver(_instance);
  }

  /// Un écran vient de traiter lui-même la touche Retour.
  static void markHandled() => _handledAt = DateTime.now();

  @override
  Future<bool> didPopRoute() async {
    if (DateTime.now().difference(_handledAt) < _window) {
      _handledAt = DateTime.fromMillisecondsSinceEpoch(0);
      return true; // écho du même appui : déjà traité, on n'enlève rien
    }
    return false; // vrai nouvel appui : le Navigator fait son travail
  }
}
