// =========================================================
//  tv_update_watch.dart — la box PROPOSE la mise à jour
// =========================================================
//  Demande du propriétaire (10/09/2026), après avoir attendu une mise à
//  jour qui n'arrivait pas : « le bouton du TV doit détecter directement
//  qu'il y a une nouvelle mise à jour. Il peut même écrire un petit
//  message au client : s'il veut, il peut télécharger, il dit oui ou non.
//  Il faut coder ça une bonne fois pour toutes. »
//
//  ---------------------------------------------------------
//  CE QUI MANQUAIT, ET CE N'ÉTAIT PAS LE DIALOGUE
//  ---------------------------------------------------------
//  Tout existait déjà, SAUF le déclencheur :
//    - `UpdateService.checkDetailed()` sait interroger le canal ;
//    - `showTvUpdateDialog()` sait proposer, télécharger, installer ;
//    - le téléphone appelle tout ça TOUT SEUL — au démarrage, sur
//      minuteur, et au retour au premier plan.
//
//  La box, elle, n'ouvrait ce dialogue QUE si le client allait le
//  chercher dans Réglages. Un client TV ne pouvait donc pas apprendre
//  qu'une version existait : il fallait qu'il pense à vérifier.
//
//  Le plus parlant : le commentaire du code téléphone dit « comme la TV
//  Box ». La box était censée le faire depuis le début. Elle ne le
//  faisait pas.
//
//  ---------------------------------------------------------
//  TROIS RÈGLES DE POLITESSE, PARCE QUE C'EST UNE TÉLÉ
//  ---------------------------------------------------------
//  Une fenêtre qui surgit sur un téléphone est un désagrément. Sur une
//  télé, elle recouvre ce que la famille est en train de regarder. D'où :
//
//   1. JAMAIS PENDANT LA LECTURE. On ne coupe pas un match pour annoncer
//      une mise à jour. L'appelant ne lance le veilleur que depuis
//      l'accueil.
//   2. UN DÉLAI APRÈS L'OUVERTURE. La box met déjà quelques secondes à
//      charger ses chaînes ; une fenêtre par-dessus donnerait
//      l'impression que l'app est bloquée.
//   3. UNE SEULE FOIS PAR VERSION. Un client qui a répondu « non » ne
//      doit pas revoir la question à chaque allumage — sinon la réponse
//      suivante sera « non » par réflexe, et il ne mettra jamais à jour.
// =========================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/update/update_service.dart';
import '../presentation/tv_update_dialog.dart';

abstract final class TvUpdateWatch {
  /// Version pour laquelle le client a déjà vu la proposition. Tant que
  /// le canal ne bouge pas, on se tait.
  static const String _kSeen = 'tv.update.proposed.v1';

  /// Laisse l'accueil s'afficher et les chaînes arriver avant de parler.
  static const Duration _delaiOuverture = Duration(seconds: 12);

  static bool _enCours = false;

  /// À appeler depuis l'ACCUEIL, une fois l'écran posé.
  ///
  /// Ne rend jamais d'erreur et n'attend rien : au pire, il ne se passe
  /// rien et le bouton des Réglages reste disponible comme avant.
  static Future<void> maybeProposer(BuildContext context) async {
    if (_enCours) return;
    _enCours = true;
    try {
      await Future<void>.delayed(_delaiOuverture);
      if (!context.mounted) return;

      final UpdateCheckResult res =
          await UpdateService.instance.checkDetailed();
      if (res.status != UpdateAvailability.available) return;

      // Le nom de version distant sert de mémoire : c'est LUI qui change
      // quand on publie. Se souvenir d'un simple « déjà proposé » aurait
      // fait taire l'app pour toutes les versions suivantes.
      final String cible = res.versionName ?? '';
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (cible.isNotEmpty && prefs.getString(_kSeen) == cible) return;

      if (!context.mounted) return;
      // On note AVANT d'ouvrir : si le client éteint la télé pendant la
      // question, on ne la lui repose pas au prochain allumage.
      if (cible.isNotEmpty) await prefs.setString(_kSeen, cible);
      if (!context.mounted) return;
      await showTvUpdateDialog(context);
    } catch (_) {
      // Réseau coupé, canal injoignable, préférences illisibles : la
      // proposition est un CONFORT. Elle ne doit jamais empêcher de
      // regarder la télévision.
    } finally {
      _enCours = false;
    }
  }
}
