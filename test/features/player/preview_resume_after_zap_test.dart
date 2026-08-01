// =========================================================
//  preview_resume_after_zap_test.dart — « l'image ne vient plus »
// =========================================================
//  BUG TERRAIN (photos box client, 2026-08-01) : le grand cadre
//  d'aperçu (accueil Modèle B, colonne « Aperçu » de En direct) restait
//  VIDE au lieu de montrer la chaîne en direct.
//
//  CAUSE : l'aperçu met le lecteur en PAUSE pendant un changement de
//  chaîne (optimisation : ne pas décoder une vidéo cachée sous le logo),
//  puis charge la nouvelle chaîne avec setUrl. Or `pause()` pose
//  `playWhenReady = false` côté ExoPlayer et `setUrl` ne le relevait
//  PAS : le média se préparait sans jamais démarrer → aucune première
//  image → cadre figé, à vie.
//
//  CONTRAT VÉRIFIÉ ICI : charger une URL veut TOUJOURS dire la jouer.
//  Après pause() puis setUrl(), un ordre « play » part vers le natif.
// =========================================================
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const int kViewId = 42;
  const MethodChannel channel = MethodChannel('native_video_player/$kViewId');
  late List<String> calls;

  setUp(() {
    calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call.method);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('zap : pause() puis setUrl() → la lecture REPART (ordre « play »)',
      () async {
    final NativeVideoController c = NativeVideoController(preview: true);
    c.attachForTest(kViewId);
    await Future<void>.delayed(Duration.zero);

    // L'aperçu met en pause pendant la navigation (comportement existant).
    c.pause();
    calls.clear();

    // Puis il charge la chaîne suivante.
    c.setUrl('http://panel.example/live/u/p/chaine2.ts');
    await Future<void>.delayed(Duration.zero);

    expect(calls, contains('setUrl'));
    expect(calls, contains('play'),
        reason: 'sans cet ordre, le média reste préparé mais JAMAIS joué : '
            'aucune 1re image, cadre d\'aperçu figé (bug terrain)');
    // L'ordre compte : on joue APRÈS avoir chargé.
    expect(calls.indexOf('play'), greaterThan(calls.indexOf('setUrl')));
    c.dispose();
  });

  test('URL demandée AVANT rattachement : rejouée ET lancée au rattachement',
      () async {
    final NativeVideoController c = NativeVideoController(preview: true);
    // Cas réel de l'aperçu : setUrl part pendant la création de la vue.
    c.setUrl('http://panel.example/live/u/p/chaine1.ts');
    c.attachForTest(kViewId);
    await Future<void>.delayed(Duration.zero);

    expect(calls, contains('setUrl'));
    expect(calls, contains('play'),
        reason: 'une vue toute neuve ne doit pas naître en pause');
    c.dispose();
  });

  test('setUrl remet firstFrame à false (le logo reprend la main au zap)', () {
    final NativeVideoController c = NativeVideoController(preview: true);
    c.attachForTest(kViewId);
    c.firstFrame = true; // état « vidéo affichée » de la chaîne précédente
    c.setUrl('http://panel.example/live/u/p/chaine3.ts');
    expect(c.firstFrame, isFalse,
        reason: 'sinon l\'ancienne image resterait affichée pour la nouvelle '
            'chaîne');
    c.dispose();
  });
}
