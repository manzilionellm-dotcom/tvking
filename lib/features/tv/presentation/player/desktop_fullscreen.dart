// =========================================================
//  desktop_fullscreen.dart — le plein écran d'une fenêtre PC
// =========================================================
//  Sur la box, le plein écran ne se demande pas : une app Android TV
//  occupe l'écran, point. Sur un PC, l'application vit dans une FENÊTRE,
//  avec une barre de titre, une bordure, et la barre des tâches en
//  dessous. Un match regardé là-dedans reste « une fenêtre de logiciel »
//  — c'est exactement ce que le propriétaire a demandé de faire
//  disparaître : « un bouton plein écran qui couvre tout comme une télé ».
//
//  Flutter ne sait pas le faire seul. `SystemChrome.setEnabledSystemUIMode`
//  — celui qu'on emploie côté Android — est Android/iOS uniquement et ne
//  fait littéralement RIEN sur Windows. Il faut parler à la fenêtre
//  NATIVE, ce que fait le paquet window_manager (voir pubspec.yaml).
//
//  POURQUOI UN FICHIER À PART. C'est le seul endroit du projet qui importe
//  window_manager, exactement comme desktop_player_screen.dart est le seul
//  à importer media_kit. Ce fichier n'est atteint que depuis le chemin
//  Windows (main_windows.dart) : la fermeture de compilation du build
//  Android TV ne le voit jamais, donc le paquet ne peut pas casser un
//  build qui ne s'en sert pas.
//
//  TOUT EST BEST-EFFORT. Une fenêtre qui refuse de passer en plein écran
//  n'est pas une raison d'interrompre un match : chaque appel avale son
//  erreur et rend l'état qu'il connaît. Le pire cas, c'est un bouton qui
//  ne fait rien — pas une application qui s'arrête.
// =========================================================
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Le plein écran de la fenêtre Windows, en trois gestes.
class DesktopFullscreen {
  const DesktopFullscreen._();

  /// À appeler UNE FOIS au démarrage, avant `runApp`.
  ///
  /// Sans elle, les appels suivants tombent dans le vide : le canal natif
  /// n'existe pas encore. C'est le genre de panne silencieuse dont on
  /// conclut « le bouton ne marche pas » alors que le bouton va très bien.
  static Future<void> preparer() async {
    try {
      await windowManager.ensureInitialized();
    } catch (e) {
      debugPrint('[plein écran] initialisation impossible : $e');
    }
  }

  /// La fenêtre est-elle déjà en plein écran ?
  static Future<bool> actif() async {
    try {
      return await windowManager.isFullScreen();
    } catch (_) {
      return false;
    }
  }

  /// Bascule, et rend l'état RÉELLEMENT obtenu.
  ///
  /// On relit la fenêtre au lieu de supposer que la demande a abouti :
  /// c'est ce qui garde l'icône du bouton d'accord avec ce que le client
  /// voit à l'écran, même si le système a refusé.
  static Future<bool> basculer() async {
    try {
      final bool avant = await windowManager.isFullScreen();
      await windowManager.setFullScreen(!avant);
      // `return await` et non `return` : sans le `await`, la Future sort du
      // bloc `try` avant de se résoudre et son échec échapperait au `catch`
      // juste en dessous. La garde ne servirait alors plus à rien.
      return await windowManager.isFullScreen();
    } catch (e) {
      debugPrint('[plein écran] bascule impossible : $e');
      return actif();
    }
  }

  /// Revenir à la fenêtre normale.
  ///
  /// Appelée en quittant le lecteur : sortir d'une chaîne pour se
  /// retrouver dans un menu qui occupe encore tout l'écran, sans barre de
  /// titre ni croix de fermeture, c'est se sentir enfermé dans son propre
  /// ordinateur.
  static Future<void> quitter() async {
    try {
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
      }
    } catch (e) {
      debugPrint('[plein écran] sortie impossible : $e');
    }
  }
}
