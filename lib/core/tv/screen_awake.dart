// =========================================================
//  screen_awake.dart — L'écran d'une TV ne doit JAMAIS s'endormir
// =========================================================
//  POURQUOI CE FICHIER EXISTE (28/08/2026).
//
//  Signalement du propriétaire : « l'application TV Box part en veille
//  après 15 minutes ».
//
//  Cause trouvée, et elle est simple : l'application TV ne posait
//  AUCUN verrou d'écran, nulle part. Le seul `WakelockPlus` du projet
//  vivait dans le lecteur MOBILE
//  (features/player/presentation/video_player_screen.dart) et dans le
//  casting — deux chemins que l'entrée TV n'emprunte jamais.
//
//  Sans ce verrou, la box applique son délai d'inactivité système : au
//  bout de 15 minutes sans appui sur la télécommande, l'économiseur
//  d'écran démarre ou la sortie HDMI s'éteint. Et regarder la
//  télévision, c'est précisément rester sans toucher à la télécommande
//  pendant plus de 15 minutes.
//
//  ---------------------------------------------------------
//  CE QU'IL MANQUAIT ENCORE (18/09/2026) — LE VERROU POSÉ UNE FOIS
//  ---------------------------------------------------------
//  Signalement : « Après 30 minutes, l'écran devient noir, comme si ça
//  entrait en pause. Il faut le faire tourner 48 heures sur 48. »
//
//  Le verrou était bien branché — vérifié ligne à ligne dans
//  `main_tv.dart`. Mais il n'était posé QU'UNE SEULE FOIS, au
//  démarrage, ET LE CODE CROYAIT SUR PAROLE QUE ÇA AVAIT MARCHÉ :
//
//    • `_apply` écrivait `_wanted = true` AVANT d'appeler la
//      plateforme, puis avalait l'erreur éventuelle ;
//    • la garde « on n'appelle que si l'état CHANGE » regardait ce même
//      `_wanted`. Une fois à `true`, plus jamais aucun appel ne
//      repartait — même si le tout premier avait échoué.
//
//  Donc si `WakelockPlus.enable()` échouait au démarrage — canal de
//  plateforme pas encore rattaché à l'activité, ce qui arrive sur les
//  box lentes puisqu'on l'appelle AVANT le premier rendu — le verrou
//  n'était jamais posé, et PLUS RIEN ne réessayait. La box appliquait
//  alors tranquillement son délai d'inactivité. Aucune erreur visible :
//  l'objet répondait « oui, éveillé » à qui le lui demandait.
//
//  C'est le défaut qui revient le plus souvent dans ce dépôt : un
//  journal — ou ici un booléen — qui AFFIRME PLUS QU'IL N'A MESURÉ.
//
//  CE QUI CHANGE, ET RIEN D'AUTRE :
//   1. On RELIT la plateforme (`WakelockPlus.enabled`) au lieu de
//      supposer. `_confirme` ne vaut `true` que si elle a dit oui.
//   2. Une RELANCE toutes les 5 minutes tant que l'app est devant. Cinq
//      minutes, c'est bien en dessous des 15 et des 30 minutes des
//      délais système : une pose ratée est rattrapée avant que le
//      client voie quoi que ce soit.
//   3. Ça s'ÉCRIT DANS LA BOÎTE NOIRE. Après 48 h, la boîte noire dit
//      laquelle des trois histoires est la vraie — au lieu qu'on
//      continue à deviner :
//        • `ecran.verrou.refuse`   → la box refuse le verrou. C'est
//          notre problème, et on saurait enfin qu'il existe.
//        • `ecran.verrou.retabli`  → la box LÂCHE le verrou en cours de
//          route ; on vient de le remettre. Le client ne voit rien.
//        • ni l'un ni l'autre, et l'écran noircit quand même → le
//          verrou tient, l'extinction vient d'ailleurs (réglage
//          « Économiseur d'écran » / « Veille » de la box elle-même,
//          ou HDMI-CEC du téléviseur) et AUCUN code d'application ne
//          peut l'empêcher. Ça se règle dans les réglages de la box.
//
//  ---------------------------------------------------------
//  POURQUOI TOUTE L'APPLICATION, ET PAS SEULEMENT LA LECTURE
//  ---------------------------------------------------------
//  La tentation est de n'éveiller l'écran que pendant la vidéo. C'est
//  ce que fait le mobile, et c'est juste là-bas : un téléphone dans une
//  poche doit s'éteindre.
//
//  Une TV, non. Le client parcourt le guide, lit un synopsis, laisse
//  l'accueil affiché en fond — et sur une TV, l'écran qui s'éteint tout
//  seul pendant qu'on lit est vécu comme une panne de l'application,
//  pas comme un réglage du système. On tient donc le verrou tant que
//  l'application est au premier plan, point.
//
//  ---------------------------------------------------------
//  CE QUE ÇA COÛTE, ET POURQUOI C'EST ACCEPTABLE ICI
//  ---------------------------------------------------------
//  `WakelockPlus` pose `FLAG_KEEP_SCREEN_ON` sur la fenêtre. Ce n'est
//  PAS un verrou processeur : ça n'empêche pas la box de dormir une
//  fois l'application quittée, et ça ne demande AUCUNE permission
//  Android (contrairement à un vrai WAKE_LOCK). C'est le mécanisme que
//  tous les lecteurs vidéo utilisent.
//
//  ⚠ ET C'EST POUR ÇA QUE LA LIBÉRATION COMPTE. Un drapeau posé et
//  jamais retiré empêcherait l'écran de s'éteindre alors que
//  l'application est passée en arrière-plan. Sur une box branchée au
//  secteur c'est surtout de l'usure d'écran ; sur une tablette ou un
//  téléphone Android TV, c'est la batterie qui part. On suit donc le
//  CYCLE DE VIE : éveillé au premier plan, relâché dès qu'on n'y est
//  plus. La relance, elle, ne tourne QUE quand on veut le verrou —
//  éteint, ce fichier ne coûte pas un seul réveil.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../observability/structured_logger.dart';

class ScreenAwake with WidgetsBindingObserver {
  ScreenAwake._();
  static final ScreenAwake instance = ScreenAwake._();

  /// Intervalle de RELANCE du verrou tant que l'app est au premier plan.
  ///
  ///  Choisi SOUS le plus court des délais système qu'on veut battre :
  ///  15 minutes (économiseur d'écran des box Android TV) et 30 minutes
  ///  (mise en veille). Une pose ratée est donc rattrapée deux à six
  ///  fois avant que le client puisse voir un écran noir.
  ///
  ///  Réglable UNIQUEMENT pour les tests : un test qui attendrait cinq
  ///  vraies minutes ne serait jamais écrit, donc jamais exécuté.
  @visibleForTesting
  static Duration periodeRelance = const Duration(minutes: 5);

  bool _installed = false;

  /// Ce qu'on VEUT (l'intention, dictée par le cycle de vie).
  bool _wanted = false;

  /// Ce que la PLATEFORME a confirmé. À ne jamais confondre avec
  /// [_wanted] : c'est exactement la confusion qui a laissé des box
  /// s'éteindre en silence.
  bool _confirme = false;

  /// Vrai quand la relecture n'est pas disponible sur cette box. On ne
  /// le journalise qu'UNE fois : sinon c'est une ligne toutes les cinq
  /// minutes pendant 48 h, et la boîte noire devient illisible — le
  /// bruit cache exactement ce qu'on est venu chercher.
  bool _relectureIllisibleDite = false;

  Timer? _relance;

  /// À appeler UNE fois au démarrage de l'application TV.
  ///
  /// Idempotent : un second appel ne pose pas un second observateur.
  /// Sans cette garde, un redémarrage à chaud en développement
  /// empilerait les observateurs et chacun réagirait au même
  /// événement.
  Future<void> install() async {
    if (_installed) return;
    _installed = true;
    WidgetsBinding.instance.addObserver(this);
    await _apply(true);
  }

  /// Symétrique d'[install]. N'est pas appelée en production — une
  /// application TV ne « désinstalle » pas son écran — mais elle existe
  /// pour les tests, et pour ne pas laisser un observateur orphelin si
  /// un jour on veut couper la fonction depuis les réglages.
  Future<void> uninstall() async {
    if (!_installed) return;
    _installed = false;
    WidgetsBinding.instance.removeObserver(this);
    await _apply(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    //  `resumed` = l'application est visible ET reçoit les événements.
    //  Tous les autres états (inactive, paused, detached, hidden)
    //  signifient qu'on n'est plus devant : on relâche.
    //
    //  `inactive` mérite un mot : sur Android il survient aussi pendant
    //  une boîte de dialogue système ou un changement de fenêtre très
    //  bref. Relâcher puis reposer le drapeau dans la seconde est sans
    //  conséquence — le compte à rebours d'inactivité de la box repart
    //  de zéro dès qu'on le repose.
    unawaited(_apply(state == AppLifecycleState.resumed));
  }

  Future<void> _apply(bool wanted) async {
    //  ON N'APPELLE LA PLATEFORME QUE SI QUELQUE CHOSE CLOCHE. Avant, la
    //  garde ne regardait que l'INTENTION — donc une intention « posée »
    //  dont la pose avait échoué bloquait toute nouvelle tentative pour
    //  le reste de la vie de l'application. On exige désormais aussi que
    //  la plateforme soit d'accord.
    if (wanted == _wanted && _confirme == wanted && _installed) return;
    _wanted = wanted;
    await _poser(wanted);
    _reglerRelance();
  }

  /// Pose (ou retire) le verrou, PUIS relit la plateforme.
  Future<void> _poser(bool voulu) async {
    try {
      if (voulu) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (e) {
      //  JAMAIS BLOQUANT. Certaines box exotiques ne fournissent pas le
      //  canal ; l'écran s'éteindra au bout de 15 min, ce qui est
      //  exactement le comportement d'avant — mais l'application, elle,
      //  doit démarrer. La DIFFÉRENCE avec avant : on le SAIT, c'est
      //  écrit, et la relance retentera dans cinq minutes.
      _confirme = false;
      if (kDebugMode) debugPrint('[ScreenAwake] verrou indisponible: $e');
      StructuredLogger.instance.error(
        domain: 'ecran',
        event: 'verrou.refuse',
        ctx: <String, Object?>{'voulu': voulu, 'err': e.toString()},
      );
      return;
    }

    final bool? lu = await _relire();
    if (lu == null) {
      //  Relecture impossible : on ne SAIT pas. On ne prétend donc ni
      //  succès ni échec — on note l'intention et on laisse la relance
      //  reposer le verrou périodiquement, ce qui ne coûte rien.
      _confirme = voulu;
      if (!_relectureIllisibleDite) {
        _relectureIllisibleDite = true;
        StructuredLogger.instance.warn(
          domain: 'ecran',
          event: 'verrou.illisible',
          ctx: <String, Object?>{
            'note': 'cette box ne dit pas si le verrou est posé ; on le '
                'repose quand meme toutes les ${periodeRelance.inMinutes} min',
          },
        );
      }
      return;
    }

    _confirme = lu == voulu;
    if (_confirme) {
      if (voulu) {
        StructuredLogger.instance.info(
          domain: 'ecran',
          event: 'verrou.pose',
          ctx: const <String, Object?>{'lu': true},
        );
      }
      return;
    }
    StructuredLogger.instance.error(
      domain: 'ecran',
      event: 'verrou.refuse',
      ctx: <String, Object?>{'voulu': voulu, 'lu': lu},
    );
  }

  /// `true`/`false` = la plateforme a répondu. `null` = elle n'a pas pu
  /// (canal absent, box exotique) — ce qui n'est PAS la même chose que
  /// « le verrou n'est pas posé », et ne doit jamais être écrit comme
  /// tel dans la boîte noire.
  Future<bool?> _relire() async {
    try {
      return await WakelockPlus.enabled;
    } catch (_) {
      return null;
    }
  }

  void _reglerRelance() {
    _relance?.cancel();
    _relance = null;
    //  Éteint, ce fichier ne coûte pas un seul réveil : pas de verrou
    //  voulu, pas de minuterie. Même règle que l'écran de veille et que
    //  l'aperçu vidéo.
    if (!_installed || !_wanted) return;
    _relance = Timer.periodic(periodeRelance, (_) => unawaited(verifier()));
  }

  /// Un tour de relance. Public pour que les tests puissent le
  /// déclencher sans attendre cinq vraies minutes.
  @visibleForTesting
  Future<void> verifier() async {
    if (!_installed || !_wanted) return;
    final bool? lu = await _relire();
    if (lu == true) {
      _confirme = true;
      return; // Tout va bien : on ne dit rien. Le silence est la norme.
    }
    if (lu == false) {
      //  LA LIGNE QUI TRANCHE LE DÉBAT. Si elle apparaît dans la boîte
      //  noire d'un client, la box lâche le verrou en cours de route —
      //  et on vient de le remettre avant qu'il voie l'écran noir.
      StructuredLogger.instance.warn(
        domain: 'ecran',
        event: 'verrou.retabli',
        ctx: const <String, Object?>{
          'note': 'la box avait relache FLAG_KEEP_SCREEN_ON ; repose',
        },
      );
    }
    //  `lu == null` (relecture illisible) : on repose sans rien
    //  affirmer. Reposer un verrou déjà posé ne coûte rien ; prétendre
    //  qu'il était tombé coûterait un mauvais diagnostic.
    _confirme = false;
    await _poser(true);
  }

  @visibleForTesting
  bool get debugWanted => _wanted;

  @visibleForTesting
  bool get debugInstalled => _installed;

  /// Ce que la PLATEFORME a confirmé — pas ce qu'on espère.
  @visibleForTesting
  bool get debugConfirme => _confirme;

  @visibleForTesting
  bool get debugRelanceArmee => _relance != null;
}
