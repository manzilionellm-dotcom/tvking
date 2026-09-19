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
//  « ÇA A MARCHÉ » SE MESURE, ÇA NE SE SUPPOSE PAS
//  ---------------------------------------------------------
//  Chaque méthode rend `true` seulement si le geste a EU LIEU. Le
//  navigateur absent (app en arrière-plan, écran pas encore monté), un
//  nom inconnu, une chaîne introuvable : `false`, et le panel affiche
//  « refusé ».
//
//  Un support qui croit avoir cliqué alors que rien n'a bougé appuie
//  dix fois — et le client voit son app partir dans tous les sens
//  pendant qu'on lui explique que « c'est normal ».
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/assistance/assistance_controller.dart';
import '../../playlists/data/favorites_repository.dart';
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
  Future<bool> ouvrirEcran(String nom) async {
    final Widget Function()? builder = _ecrans[nom.trim().toLowerCase()];
    if (builder == null) return false;
    final NavigatorState? nav = tvNavigatorKey.currentState;
    if (nav == null) return false;
    await nav.push(MaterialPageRoute<void>(builder: (_) => builder()));
    _dernier = nom;
    return true;
  }

  @override
  Future<bool> ouvrirCategorie(String nom) async {
    //  PAS ENCORE BRANCHÉ, ET ON LE DIT. Ouvrir une catégorie précise
    //  demande d'entrer dans l'état interne de l'écran des chaînes ;
    //  tant que ce n'est pas fait proprement, on refuse au lieu de
    //  « faire à peu près » — ouvrir le mauvais dossier chez un client
    //  est pire que ne rien ouvrir.
    return false;
  }

  @override
  Future<bool> ouvrirChaine(String id) async {
    // Même raison que ci-dessus : le lecteur TV a son propre cycle
    // (créneau de lecture, relais). On ne s'y branche pas à la hâte.
    return false;
  }

  @override
  Future<bool> basculerFavori(String id) async {
    final String clef = id.trim();
    if (clef.isEmpty) return false;
    //  CELUI-LÀ EST RÉEL. `toggle` est exactement ce qu'appelle le
    //  bouton cœur de l'écran des chaînes : le support fait le même
    //  geste que le client, pas un geste parallèle qui pourrait
    //  diverger.
    await FavoritesRepository.instance.toggle(clef);
    return true;
  }

  @override
  Future<bool> retour() async {
    final NavigatorState? nav = tvNavigatorKey.currentState;
    if (nav == null) return false;
    //  `maybePop` et pas `pop` : sur l'accueil il n'y a rien à
    //  dépiler, et `pop` fermerait l'APPLICATION. Le client verrait sa
    //  télé revenir au menu de la box pendant qu'on l'aide.
    return nav.maybePop();
  }

  @override
  String ecranCourant() => _dernier;
}
