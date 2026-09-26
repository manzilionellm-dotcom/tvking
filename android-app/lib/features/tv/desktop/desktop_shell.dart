// =========================================================
//  desktop_shell.dart — Fenêtre et clavier de Zuno sur PC (Windows)
// =========================================================
//  Zuno PC = EXACTEMENT l'interface de la box (mêmes écrans, même design,
//  canevas 1280 mis à l'échelle). Ce fichier ajoute seulement ce qu'une
//  télécommande fait « gratuitement » sur Android et qu'un PC n'a pas :
//
//    • Échap / touche Retour du navigateur = bouton RETOUR de la
//      télécommande (un écran en arrière, comme sur la box) ;
//    • F11 et Alt+Entrée = plein écran ⇄ fenêtre ;
//    • démarrage PLEIN ÉCRAN (expérience TV), titre « Zuno ».
//
//  Flèches = D-pad, Entrée = OK : déjà gérés par les écrans TV. La souris
//  fonctionne aussi (clic = OK, molette = défilement).
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/blackbox/black_box.dart';

/// Fenêtre native (plein écran, titre, taille minimale).
abstract final class DesktopWindow {
  static Future<void> prepare() async {
    try {
      await windowManager.ensureInitialized();
      await windowManager.waitUntilReadyToShow(
        const WindowOptions(
          title: 'Zuno',
          minimumSize: Size(960, 540),
          backgroundColor: Colors.black,
        ),
        () async {
          await windowManager.show();
          await windowManager.focus();
          await windowManager.setFullScreen(true);
        },
      );
    } catch (e) {
      BlackBox.instance.warn('PC', 'fenêtre : $e');
    }
  }

  static Future<void> toggleFullscreen() async {
    try {
      await windowManager.setFullScreen(!await windowManager.isFullScreen());
    } catch (e) {
      BlackBox.instance.warn('PC', 'plein écran : $e');
    }
  }
}

class _BackIntent extends Intent {
  const _BackIntent();
}

class _FullscreenIntent extends Intent {
  const _FullscreenIntent();
}

/// Enveloppe l'app : raccourcis PC, sans toucher aux écrans.
class DesktopShell extends StatelessWidget {
  const DesktopShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): _BackIntent(),
        SingleActivator(LogicalKeyboardKey.browserBack): _BackIntent(),
        SingleActivator(LogicalKeyboardKey.f11): _FullscreenIntent(),
        SingleActivator(LogicalKeyboardKey.enter, alt: true): _FullscreenIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          // Même effet que le bouton Retour Android : l'écran courant recule
          // d'UN pas (PopScope respecté → boîte « Quitter » à l'accueil). Les
          // lecteurs gèrent Échap eux-mêmes (la touche ne remonte pas ici).
          _BackIntent: CallbackAction<_BackIntent>(
            onInvoke: (_) {
              final BuildContext? ctx = FocusManager.instance.primaryFocus?.context;
              if (ctx != null) unawaited(Navigator.maybeOf(ctx)?.maybePop());
              return null;
            },
          ),
          _FullscreenIntent: CallbackAction<_FullscreenIntent>(
            onInvoke: (_) {
              unawaited(DesktopWindow.toggleFullscreen());
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}
