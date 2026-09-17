// =========================================================
//  L'IMAGE DOIT SORTIR — les trois verrous du 17/09/2026
// =========================================================
//  CE FICHIER A CHANGÉ DE CAMP, ET IL FAUT LE DIRE.
//
//  Il verrouillait l'inverse : « MainActivity BLOQUE les captures
//  (setFlags FLAG_SECURE) » et « CI pose FLAG_SECURE sur TV et
//  téléphone ». Le pari de l'époque était qu'un rendu par texture
//  laissait passer l'image malgré le drapeau.
//
//  Le terrain a tranché. Le propriétaire, sur une box en clientèle :
//  « ça se redémarre, et ça sort seulement le son ».
//
//  TROIS CHANGEMENTS, PRIS ENSEMBLE, FERMAIENT LA PORTE À CLÉ :
//
//   1. FLAG_SECURE posé sur la fenêtre. Sur une box HDMI, une fenêtre
//      « secure » n'est pas composée vers la sortie : le son continue,
//      l'écran reste noir. (Verrouillé dans test/core/flag_secure_off_test.dart.)
//
//   2. Le plugin FORÇAIT `render_mode = texture` sur chaque box
//      (`render_reset_v5`), effaçant le `surface` que le watchdog avait
//      mémorisé sur les box incapables de rendre en texture.
//
//   3. Le WATCHDOG qui aurait pu les ramener était désactivé
//      (`_switchedOnce = true` d'entrée, Timer supprimé).
//
//  2 + 3 = la box est remise du mauvais côté ET ne peut plus revenir.
//  Le son joue, l'image jamais, définitivement.
//
//  Ce fichier lit les fichiers RÉELS. Il ne teste pas un comportement —
//  il empêche une reprise de ce bras de fer sans que personne s'en
//  aperçoive. Huit commits en deux jours ont tourné en rond dessus.
// =========================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String code(File f) => f
      .readAsStringSync()
      .split('\n')
      .where((String l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  final File dart =
      File('packages/native_video_player/lib/native_video_player.dart');
  final File plugin = File(
    'packages/native_video_player/android/src/main/kotlin/'
    'com/manzilionellm/native_video_player/NativeVideoPlayerPlugin.kt',
  );
  final File vue = File(
    'packages/native_video_player/android/src/main/kotlin/'
    'com/manzilionellm/native_video_player/NativeVideoView.kt',
  );

  test('les fichiers du lecteur sont là où on les croit', () {
    // Un test qui lit un fichier absent passerait tout vert sans rien
    // vérifier. On échoue franchement plutôt que de rassurer à tort.
    for (final File f in <File>[dart, plugin, vue]) {
      expect(f.existsSync(), isTrue, reason: f.path);
    }
  });

  test('défaut rendu = texture', () {
    // Le vrai sujet historique du fichier, jamais remis en cause : le
    // chemin par DÉFAUT est la texture. Ce qui compte n'est pas ce
    // défaut — c'est de pouvoir en sortir (test suivant).
    expect(code(dart), contains('return texture'));
    expect(code(plugin), contains('"texture"'));
  });

  test('LE WATCHDOG EST ACTIF — c\'est lui qui sauve les box', () {
    final String c = code(dart);
    expect(
      c.contains('_switchedOnce = false'),
      isTrue,
      reason: 'avec `_switchedOnce = true` d\'entrée, _switchRenderPath() '
          'sort immédiatement : une box coincée sur le mauvais chemin de '
          'rendu ne peut plus JAMAIS en sortir → son sans image',
    );
    expect(
      c.contains('_watchdog = Timer.periodic'),
      isTrue,
      reason: 'sans ce Timer, personne ne détecte « le son joue, l\'image '
          'ne vient pas ». C\'est le SEUL mécanisme par lequel une box '
          'découvre le chemin qui marche chez elle.',
    );
  });

  test('le plugin NE FORCE PLUS le chemin de rendu', () {
    final String c = code(plugin);
    // On cherche l'ÉCRITURE forcée, pas le mot : le commentaire qui
    // raconte la décision cite forcément `render_reset_v5`, et un test
    // qui interdirait le mot interdirait aussi de l'expliquer. Même
    // leçon que la page de confidentialité.
    expect(
      c.contains('putString("render_mode", "texture")'),
      isFalse,
      reason: 'forcer le mode efface le `surface` appris par le watchdog '
          'sur les box qui en ont besoin',
    );
  });

  test('le plafond mémoire reste un plafond', () {
    final String c = code(vue);
    expect(
      c.contains('setPrioritizeTimeOverSizeThresholds(true)'),
      isFalse,
      reason: 'à true, setTargetBufferBytes n\'est plus une limite : le '
          'tampon déborde, l\'OS tue l\'app sur une box à 1 Go, et elle '
          'se relance en boucle — « ça se redémarre »',
    );
    expect(c.contains('setPrioritizeTimeOverSizeThresholds(false)'), isTrue);
  });
}
