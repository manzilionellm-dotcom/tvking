// =========================================================
//  tv_assistance_executeur.dart — la box obéit aux gestes du support
// =========================================================
//  Le consentement vit dans `core/assistance/` : quand ce fichier est
//  appelé, le client a DÉJÀ dit oui et la session est vivante. Ici, on
//  ne décide rien — on exécute, ou on refuse franchement.
//
//  ---------------------------------------------------------
//  UNE LISTE D'ÉCRANS, ET PAS UN CHEMIN LIBRE
//  ---------------------------------------------------------
//  Le support n'envoie pas « ouvre tel widget » : il envoie un NOM
//  ('favoris', 'chaines', 'reglages'…) que ce fichier traduit. Un nom
//  inconnu est refusé, jamais approché.
//
//  C'est volontaire. Si le panel pouvait désigner n'importe quel
//  écran, chaque écran ajouté demain deviendrait atteignable à
//  distance sans que personne l'ait décidé — y compris ceux qui ne
//  devraient pas l'être. Ici, ouvrir un écran au support est un geste
//  délibéré : on l'inscrit dans cette liste, ou il n'existe pas.
//
//  ---------------------------------------------------------
//  « ÇA A MARCHÉ » SE MESURE, ET « ÇA A RATÉ » SE NOMME
//  ---------------------------------------------------------
//  Chaque méthode rend `null` seulement si le geste a EU LIEU. Sinon
//  elle rend une RAISON courte — pas un `false` muet.
//
//  Le 19/09/2026, le propriétaire a lu trois fois « refusé
//  (refuse_ou_echoue) » sur son panel. Techniquement exact ; sans
//  aucune valeur. Il ne pouvait pas savoir s'il fallait rappeler le
//  client, lui faire rouvrir l'app, ou simplement changer de bouton.
//  C'est le défaut que ce dépôt traque depuis des mois : un message
//  qui en dit moins que ce qu'on a mesuré.
//
//  Un support qui croit avoir cliqué alors que rien n'a bougé appuie
//  dix fois — et le client voit son app partir dans tous les sens
//  pendant qu'on lui explique que « c'est normal ».
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/assistance/assistance_controller.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/remote_source_repository.dart';
import '../../subscription/data/subscription_state.dart';
import '../presentation/tv_about_screen.dart';
import '../presentation/tv_app.dart';
import '../presentation/tv_black_box_screen.dart';
import '../presentation/tv_channels_screen.dart';
import '../presentation/tv_settings_screen.dart';
import '../presentation/tv_shell.dart';

/// Les écrans qu'un support peut ouvrir à distance, et EUX SEULS.
///
///  Les noms sont STABLES : le panel les envoie tels quels. Les
///  renommer casserait les boutons d'un panel plus ancien — ce sont
///  des identifiants, pas des libellés d'interface.
final Map<String, Widget Function()> _ecrans = <String, Widget Function()>{
  // Le cas exact du propriétaire : « un client me dit qu'il ne trouve
  // pas les favoris ». Les favoris vivent DANS l'écran des chaînes.
  'chaines': () => const TvShell(child: TvChannelsScreen()),
  'favoris': () => const TvShell(child: TvChannelsScreen()),
  'reglages': () => const TvShell(child: TvSettingsScreen()),
  'apropos': () => const TvShell(child: TvAboutScreen()),
  // La boîte noire : pour qu'on puisse LA REGARDER avec le client au
  // téléphone, au lieu de lui demander de la photographier.
  'diagnostic': () => const TvShell(child: TvBlackBoxScreen()),
};

/// Les noms d'écrans connus — le panel s'en sert pour ne proposer que
/// ce qui existe vraiment.
List<String> get ecransGuidables => _ecrans.keys.toList(growable: false);

class TvAssistanceExecuteur implements AssistanceExecuteur {
  /// Dernier écran ouvert par le support, pour le rapporter au panel.
  /// Vide = on n'a rien ouvert depuis le début de la session : le
  /// client est là où il était, et on ne PRÉTEND PAS savoir où.
  String _dernier = '';

  @override
  Future<String?> ouvrirEcran(String nom) async {
    final Widget Function()? builder = _ecrans[nom.trim().toLowerCase()];
    if (builder == null) return 'ecran_inconnu';
    final NavigatorState? nav = tvNavigatorKey.currentState;
    //  PAS DE NAVIGATEUR = l'app n'est pas à l'écran (en arrière-plan,
    //  ou pas encore montée). C'est la cause la plus fréquente, et la
    //  seule que le support peut régler tout seul : il demande au
    //  client de revenir dans 7 MOTION. D'où un nom explicite.
    if (nav == null) return 'app_en_arriere_plan';
    await nav.push(MaterialPageRoute<void>(builder: (_) => builder()));
    _dernier = nom;
    return null;
  }

  @override
  Future<String?> ouvrirCategorie(String nom) async {
    //  PAS ENCORE BRANCHÉ, ET ON LE DIT. Ouvrir une catégorie précise
    //  demande d'entrer dans l'état interne de l'écran des chaînes ;
    //  tant que ce n'est pas fait proprement, on refuse au lieu de
    //  « faire à peu près » — ouvrir le mauvais dossier chez un client
    //  est pire que ne rien ouvrir.
    return 'pas_encore_branche';
  }

  @override
  Future<String?> ouvrirChaine(String id) async {
    // Même raison que ci-dessus : le lecteur TV a son propre cycle
    // (créneau de lecture, relais). On ne s'y branche pas à la hâte.
    return 'pas_encore_branche';
  }

  @override
  Future<String?> basculerFavori(String id) async {
    final String clef = id.trim();
    if (clef.isEmpty) return 'identifiant_vide';
    //  CELUI-LÀ EST RÉEL. `toggle` est exactement ce qu'appelle le
    //  bouton cœur de l'écran des chaînes : le support fait le même
    //  geste que le client, pas un geste parallèle qui pourrait
    //  diverger.
    await FavoritesRepository.instance.toggle(clef);
    return null;
  }

  @override
  Future<String?> retour() async {
    final NavigatorState? nav = tvNavigatorKey.currentState;
    if (nav == null) return 'app_en_arriere_plan';
    //  `maybePop` et pas `pop` : sur l'accueil il n'y a rien à
    //  dépiler, et `pop` fermerait l'APPLICATION. Le client verrait sa
    //  télé revenir au menu de la box pendant qu'on l'aide.
    final bool depile = await nav.maybePop();
    //  RIEN À DÉPILER N'EST PAS UNE PANNE : le client est déjà à
    //  l'accueil. Le support doit lire ça, pas « refusé ».
    return depile ? null : 'deja_a_l_accueil';
  }

  @override
  Future<String?> redemarrer() async {
    //  ON RELANCE L'APP, PAS LA BOX. `RestartWidget` est posé à la
    //  racine de l'app TV (tv_app.dart) : il reconstruit tout l'arbre
    //  avec une clé neuve et re-synchronise. C'est le MÊME mécanisme
    //  que le bouton « Redémarrer » de l'écran de sortie — le support
    //  fait exactement ce que le client ferait à la télécommande, pas
    //  un chemin parallèle.
    //  `restartGlobal()` ET PAS `restart(contexte)` : le contexte du
    //  navigateur est AU-DESSUS du RestartWidget, donc la recherche
    //  d'ancêtre ne le trouvait jamais — le panel répondait « fait »
    //  sans que rien ne redémarre. La clé globale vise directement le
    //  bon widget.
    if (!RestartWidget.restartGlobal()) return 'app_en_arriere_plan';
    _dernier = '';
    return null;
  }

  @override
  Future<String?> resynchroniser() async {
    //  EXACTEMENT ce que fait le redémarrage côté données, mais SANS
    //  reconstruire l'écran : pour « je ne vois pas la liste que tu
    //  viens de me pousser », on re-tire licence + listes tout de
    //  suite, et le client reste où il est.
    //
    //  LES DEUX SONT INDÉPENDANTES. Si la licence échoue (réseau,
    //  fournisseur), on veut quand même tirer les listes, et
    //  inversement. Avant, une exception sur la première empêchait la
    //  seconde et faisait remonter « exception » alors qu'une moitié
    //  aurait pu réussir.
    bool licenceOk = true;
    bool listesOk = true;
    try {
      await SubscriptionState.instance.syncWithBackend();
    } catch (_) {
      licenceOk = false;
    }
    try {
      await RemoteSourceRepository.sync();
    } catch (_) {
      listesOk = false;
    }
    // Tout raté = on le DIT ; sinon c'est un succès (au moins partiel,
    // et le plus utile — les listes — a le plus de chances de passer).
    if (!licenceOk && !listesOk) return 'resync_echouee';
    return null;
  }

  @override
  String ecranCourant() => _dernier;
}
