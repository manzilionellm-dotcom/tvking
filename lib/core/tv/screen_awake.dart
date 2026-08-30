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
//  plus.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class ScreenAwake with WidgetsBindingObserver {
  ScreenAwake._();
  static final ScreenAwake instance = ScreenAwake._();

  bool _installed = false;
  bool _wanted = false;

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
    // On n'appelle la plateforme que si l'état CHANGE. Le cycle de vie
    // émet plusieurs fois le même état sur certaines box ; sans cette
    // garde on ferait des allers-retours inutiles sur le canal.
    if (wanted == _wanted && _installed) return;
    _wanted = wanted;
    try {
      if (wanted) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (e) {
      //  JAMAIS BLOQUANT. Certaines box exotiques ne fournissent pas le
      //  canal ; l'écran s'éteindra au bout de 15 min, ce qui est
      //  exactement le comportement d'avant — mais l'application, elle,
      //  doit démarrer.
      if (kDebugMode) debugPrint('[ScreenAwake] verrou indisponible: $e');
    }
  }

  @visibleForTesting
  bool get debugWanted => _wanted;

  @visibleForTesting
  bool get debugInstalled => _installed;
}
