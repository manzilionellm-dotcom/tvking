// =========================================================
//  verrou_ecran_relance_test.dart — l'écran noir au bout de 30 min
// =========================================================
//  SIGNALEMENT DU PROPRIÉTAIRE (18/09/2026) :
//
//    « Il faut regarder le problème dans les TV box. Après 30 minutes,
//      l'écran devient noir, comme si ça entrait en pause. Il faut le
//      faire tourner 48 heures sur 48 heures. »
//
//  LE VERROU ÉTAIT BRANCHÉ. `main_tv.dart` appelle bien
//  `ScreenAwake.instance.install()` — vérifié avant de toucher à quoi
//  que ce soit. Mais il n'était posé QU'UNE FOIS, au démarrage, et le
//  code CROYAIT SUR PAROLE que ça avait marché :
//
//    • `_apply` écrivait l'intention AVANT d'appeler la plateforme ;
//    • la garde « on n'appelle que si l'état change » relisait cette
//      même intention.
//
//  Donc une première pose ratée — canal pas encore rattaché à
//  l'activité, ce qui arrive sur les box lentes puisqu'on l'appelle
//  AVANT le premier rendu — et plus RIEN ne réessayait de la vie de
//  l'application. La box appliquait alors son délai d'inactivité, et
//  l'objet continuait de répondre « oui, éveillé » à qui l'interrogeait.
//
//  C'EST CE DEUXIÈME TEST QUI COMPTE (« une première pose ratée est
//  rattrapée »). Les autres protègent ce qu'on ne veut pas casser en
//  le corrigeant.
//
//  CE QUE CES TESTS NE PROUVENT PAS, ET IL FAUT LE DIRE : ils ne
//  prouvent pas que c'était LA cause de l'écran noir de Lionel. Ils
//  prouvent qu'un défaut réel, capable de produire exactement ce
//  symptôme, est fermé — et que si l'écran noircit encore, la boîte
//  noire dira enfin laquelle des trois histoires est la vraie
//  (cf. l'en-tête de `screen_awake.dart`).
// =========================================================

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/tv/screen_awake.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// Une fausse box, pilotable : elle peut poser le verrou, le REFUSER,
/// ou ne pas savoir dire s'il est posé. Les trois arrivent en vrai.
class _FausseBox extends WakelockPlusPlatformInterface {
  bool pose = false;

  /// La box refuse de poser le verrou (canal absent, plugin pas encore
  /// rattaché à l'activité…). C'est le cas du démarrage lent.
  bool refuse = false;

  /// La box ne sait pas dire si le verrou est posé.
  bool illisible = false;

  int posesDemandees = 0;

  @override
  Future<void> toggle({required bool enable}) async {
    posesDemandees++;
    if (refuse) {
      throw PlatformException(code: 'unavailable', message: 'canal absent');
    }
    pose = enable;
  }

  @override
  Future<bool> get enabled async {
    if (illisible) {
      throw PlatformException(code: 'unavailable', message: 'illisible');
    }
    return pose;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final ScreenAwake ecran = ScreenAwake.instance;
  late _FausseBox box;

  setUp(() async {
    box = _FausseBox();
    wakelockPlusPlatformInstance = box;
  });

  tearDown(() async {
    await ecran.uninstall();
  });

  test('au démarrage, le verrou est posé ET confirmé par la box', () async {
    await ecran.install();
    expect(box.pose, isTrue, reason: 'la plateforme doit avoir été appelée');
    expect(ecran.debugConfirme, isTrue,
        reason: 'confirmé = la box a RÉPONDU oui, pas « on espère »');
    expect(ecran.debugRelanceArmee, isTrue);
  });

  test('UNE PREMIÈRE POSE RATÉE EST RATTRAPÉE — le bug du 18/09', () async {
    // Le démarrage échoue : c'est le scénario de la box lente.
    box.refuse = true;
    await ecran.install();

    expect(ecran.debugWanted, isTrue, reason: 'on veut toujours le verrou');
    expect(ecran.debugConfirme, isFalse,
        reason: 'et on ne prétend PAS l\'avoir : rien n\'a été confirmé');
    expect(box.pose, isFalse);
    expect(ecran.debugRelanceArmee, isTrue,
        reason: 'sans relance armée, personne ne réessaiera jamais');

    // Le canal devient disponible (l'activité est rattachée). Un tour de
    // relance — cinq minutes en vrai — et le verrou est enfin posé.
    box.refuse = false;
    await ecran.verifier();

    expect(box.pose, isTrue, reason: 'C\'EST TOUT LE CORRECTIF : on réessaie');
    expect(ecran.debugConfirme, isTrue);
  });

  test('si la box LÂCHE le verrou en route, on le remet', () async {
    await ecran.install();
    expect(box.pose, isTrue);

    // La box relâche `FLAG_KEEP_SCREEN_ON` toute seule — c'est
    // précisément ce qui produirait un écran noir au bout de 30 min.
    box.pose = false;

    await ecran.verifier();
    expect(box.pose, isTrue, reason: 'reposé avant que le client voie noir');
    expect(ecran.debugConfirme, isTrue);
  });

  test('box qui ne sait pas RELIRE : on repose quand même, sans mentir',
      () async {
    box.illisible = true;
    await ecran.install();

    // On a demandé la pose ; on ne peut pas la confirmer. On ne
    // prétend rien de plus que ce qu'on a mesuré.
    expect(box.posesDemandees, 1);
    expect(ecran.debugWanted, isTrue);

    await ecran.verifier();
    expect(box.posesDemandees, 2,
        reason: 'reposer un verrou déjà posé ne coûte rien ; ne pas le '
            'reposer coûte un écran noir');
  });

  test('en arrière-plan : on relâche ET la relance s\'arrête (coût zéro)',
      () async {
    await ecran.install();
    expect(ecran.debugRelanceArmee, isTrue);

    ecran.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);

    expect(ecran.debugWanted, isFalse);
    expect(ecran.debugRelanceArmee, isFalse,
        reason: 'une minuterie qui tourne pour rien réveille la box en '
            'arrière-plan — exactement ce que le verrou évite');
    expect(box.pose, isFalse);

    ecran.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(ecran.debugWanted, isTrue);
    expect(ecran.debugRelanceArmee, isTrue);
  });

  test('un tour de relance ne fait RIEN quand on ne veut pas le verrou',
      () async {
    await ecran.install();
    ecran.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);

    final int avant = box.posesDemandees;
    await ecran.verifier();
    expect(box.posesDemandees, avant,
        reason: 'relâché veut dire relâché : la relance ne doit pas '
            'rallumer l\'écran d\'une box posée dans un salon vide');
  });

  test('après désinstallation, plus aucune minuterie ne court', () async {
    await ecran.install();
    await ecran.uninstall();
    expect(ecran.debugRelanceArmee, isFalse);
    expect(ecran.debugWanted, isFalse);
  });

  group('le code source lui-même', () {
    test('la garde de _apply regarde ce que la PLATEFORME a confirmé', () {
      // C'était LA ligne du bug : elle ne comparait que l'intention.
      // Une intention « posée » dont la pose avait échoué bloquait
      // toute nouvelle tentative — à vie.
      final File f = File('lib/core/tv/screen_awake.dart');
      expect(f.existsSync(), isTrue, reason: f.path);
      expect(
        f.readAsStringSync().contains('_confirme == wanted'),
        isTrue,
        reason: 'sans `_confirme` dans la garde, une pose ratée au '
            'démarrage n\'est plus jamais retentée',
      );
    });

    test('main_tv.dart pose toujours le verrou au démarrage', () {
      // Si quelqu'un débranchait ça en croyant « finir le travail »,
      // l'écran se couperait de nouveau — cette fois pour de vrai, et
      // personne ne ferait le lien.
      final File f = File('lib/main_tv.dart');
      expect(f.existsSync(), isTrue);
      expect(
        f.readAsStringSync().contains('ScreenAwake.instance.install()'),
        isTrue,
      );
    });
  });
}
