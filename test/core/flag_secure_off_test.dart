// =========================================================
//  flag_secure_off_test.dart — l'image DOIT sortir
// =========================================================
//  17/09/2026. Le propriétaire, sur une box en clientèle :
//
//    « Même l'application TV ne fonctionne pas. Il sort seulement
//      le son. »
//
//  Son sans image : c'est la signature de FLAG_SECURE. Une fenêtre
//  Android marquée « secure » n'est pas composée vers une sortie
//  non sécurisée. Sur une box HDMI, la bande-son continue et l'écran
//  reste noir. Le client ne peut rien y faire.
//
//  CE DRAPEAU A ÉTÉ POSÉ, RETIRÉ, REPOSÉ HUIT FOIS en deux jours —
//  l'historique le montre commit après commit : « bloquer les
//  captures », « FLAG_SECURE tuait l'image sur les box », « restaurer
//  le rendu d'avant », « REC marche, image noire », « pas de capture
//  ET image visible »… Chaque tentative pariait qu'un rendu par
//  texture y échapperait. Le terrain a tranché à chaque fois, et la
//  dernière version partie en production était ALLUMÉE.
//
//  L'arbitrage n'est pas serré : bloquer les captures d'écran est un
//  confort, une box qui ne montre plus rien est un client perdu.
//
//  Ce test lit les fichiers RÉELS. Il ne teste pas un comportement —
//  il empêche une reprise de ce bras de fer sans que personne s'en
//  aperçoive. Si le drapeau doit revenir un jour, ça se valide sur une
//  VRAIE box avant de partir, et c'est ce texte qu'on met à jour.
// =========================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final File overlay = File('android_overlay/google_cast/MainActivity.kt');

  test('le fichier natif est là où on le croit', () {
    // Un test qui lit un fichier absent passerait tout vert sans rien
    // vérifier. On échoue franchement plutôt que de rassurer à tort.
    expect(overlay.existsSync(), isTrue, reason: 'chemin : ${overlay.path}');
  });

  test('la MainActivity embarquée ÉTEINT FLAG_SECURE', () {
    final String code = overlay.readAsStringSync();
    expect(
      code.contains('clearFlags(WindowManager.LayoutParams.FLAG_SECURE)'),
      isTrue,
      reason: 'on éteint EXPLICITEMENT : le drapeau peut être hérité d\'un '
          'thème ou d\'une lib, « ne pas le poser » ne suffit pas',
    );
    expect(
      code.contains('setFlags('),
      isFalse,
      reason: 'FLAG_SECURE rallumé → son sans image sur les box. '
          'Si c\'est voulu, valide-le sur une VRAIE box et mets à jour '
          'l\'en-tête de ce test.',
    );
  });

  test('aucun build ne rallume le drapeau', () {
    // Le drapeau était aussi posé à la COMPILATION, par un script.
    // Le retirer du fichier natif sans regarder les workflows aurait
    // laissé la moitié du problème en place.
    for (final String nom in <String>[
      'build-seventv.yml', // box TV / Google TV
      'build-android.yml', // téléphone
      'build-prive.yml', // build privé
    ]) {
      final File wf = File('.github/workflows/$nom');
      if (!wf.existsSync()) continue;
      final String y = wf.readAsStringSync();
      expect(y.contains('set_secure_flag'), isFalse,
          reason: '$nom rallume FLAG_SECURE à la compilation');
    }
  });

  test('le script qui allumait n\'existe plus', () {
    // Tant qu'il traîne, quelqu'un le rebranchera « pour bien faire ».
    expect(File('ci/set_secure_flag.py').existsSync(), isFalse);
    // Celui qui ÉTEINT, lui, doit rester : les workflows l'appellent.
    expect(File('ci/clear_secure_flag.py').existsSync(), isTrue);
  });
}
