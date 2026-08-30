// =========================================================
//  screen_awake_test.dart — L'écran de la TV ne dort jamais
// =========================================================
//  Ce fichier verrouille un bug TERRAIN : l'application TV partait en
//  veille au bout de 15 minutes parce qu'elle ne posait aucun verrou
//  d'écran. Regarder la télévision, c'est justement ne pas toucher à la
//  télécommande pendant plus de 15 minutes.
//
//  Ce qui est testé ici est la LOGIQUE de cycle de vie, pas le canal de
//  plateforme (qui n'existe pas dans un test). C'est volontaire : la
//  partie fragile n'est pas « appeler enable() », c'est « le rappeler
//  au bon moment et le relâcher au bon moment ».
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/tv/screen_awake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final ScreenAwake s = ScreenAwake.instance;

  tearDown(() async {
    await s.uninstall();
  });

  test('à l\'installation, l\'écran est maintenu éveillé', () async {
    await s.install();
    expect(s.debugInstalled, isTrue);
    expect(s.debugWanted, isTrue);
  });

  test('installer DEUX fois ne pose qu\'un seul observateur', () async {
    // Sans cette garde, un redémarrage à chaud empilerait les
    // observateurs et chacun réagirait au même événement.
    await s.install();
    await s.install();
    expect(s.debugInstalled, isTrue);
    // Un seul retrait doit suffire à tout défaire.
    await s.uninstall();
    expect(s.debugInstalled, isFalse);
  });

  test('en arrière-plan on RELÂCHE, au retour on REPREND', () async {
    // Le point qui compte : un drapeau posé et jamais retiré
    // empêcherait l'écran de s'éteindre alors que l'app n'est plus
    // devant — sur une tablette Android TV, c'est la batterie qui part.
    await s.install();
    expect(s.debugWanted, isTrue);

    s.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(s.debugWanted, isFalse, reason: 'en arrière-plan : relâché');

    s.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(s.debugWanted, isTrue, reason: 'de retour devant : repris');
  });

  test('tout état AUTRE que « resumed » relâche le verrou', () async {
    await s.install();
    for (final AppLifecycleState st in <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
      AppLifecycleState.hidden,
    ]) {
      s.didChangeAppLifecycleState(AppLifecycleState.resumed);
      s.didChangeAppLifecycleState(st);
      expect(s.debugWanted, isFalse, reason: 'état $st');
    }
  });

  test('après désinstallation, le verrou est relâché', () async {
    await s.install();
    await s.uninstall();
    expect(s.debugWanted, isFalse);
    expect(s.debugInstalled, isFalse);
  });
}
