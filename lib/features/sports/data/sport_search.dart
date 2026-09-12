// =========================================================
//  sport_search.dart — taper « Chelsea » et voir OÙ REGARDER
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (12/09/2026), devant sa box :
//
//    « je voulais regarder le match de Chelsea, j'ai écrit Chelsea, ça
//      devait vraiment me montrer les chaînes en direct qui passent le
//      match — mais ça ne marche plus. »
//
//  CE QUI SE PASSAIT, ET IL FAUT LE DIRE HONNÊTEMENT : ça n'avait jamais
//  marché. La recherche de la box cherchait trois choses — le NOM des
//  chaînes, le TITRE des émissions à l'antenne dans le guide, et les
//  films/séries. « Chelsea » ne tombe dans aucune :
//
//    • aucune chaîne ne s'APPELLE Chelsea ;
//    • le guide du client ne couvre presque rien (mesuré : une douzaine
//      de chaînes sur neuf cents), donc chercher un titre d'émission ne
//      pouvait pas trouver le match ;
//    • « Cheaters », « Cheap… » sont des films : c'est tout ce que la
//      recherche avait à offrir, et c'est ce qu'elle a affiché.
//
//  Pendant ce temps l'application SAVAIT pourtant répondre. Deux briques
//  existaient déjà, écrites pour le coin Sport, et personne ne les avait
//  branchées sur la recherche :
//
//    • SportsRepository.search() — trouver l'équipe par son nom ;
//    • MatchChannelFinder       — « sur QUELLE CHAÎNE ce match passe ».
//
//  Ce fichier est le fil manquant entre les deux. Il n'invente aucune
//  règle nouvelle : il appelle celles qui existent, dans le bon ordre.
//
//  ---------------------------------------------------------
//  CE QU'ON MONTRE QUAND ON NE TROUVE PAS LA CHAÎNE
//  ---------------------------------------------------------
//  Le guide du client est pauvre : très souvent on connaîtra le match
//  sans savoir qui le diffuse. On affiche quand même le match, avec son
//  heure, et [SportSearchHit.channel] reste `null`.
//
//  C'est un choix, pas une facilité. « Chelsea – Arsenal, ce soir 21 h,
//  chaîne inconnue » répond déjà à la moitié de la question. Ne rien
//  afficher laisse le client croire qu'il n'y a pas de match — et c'est
//  exactement le malentendu qu'on répare.
//
//  ---------------------------------------------------------
//  LES RÈGLES SONT PURES, DONC TESTABLES
//  ---------------------------------------------------------
//  Le tri et la fenêtre de temps ne touchent ni la base ni le réseau :
//  voir test/features/sports/sport_search_test.dart. Seul
//  [SportSearch.rechercher] parle au monde extérieur.
// =========================================================

import 'package:flutter/foundation.dart';

import '../../channels/domain/channel.dart';
import '../domain/sport_models.dart';
import 'match_channel_finder.dart';
import 'sports_repository.dart';

/// Un match trouvé par la recherche, et la chaîne qui le diffuse.
@immutable
class SportSearchHit {
  const SportSearchHit({
    required this.event,
    required this.teamName,
    this.channel,
  });

  final SportEvent event;

  /// L'équipe par laquelle on est arrivé jusqu'à ce match. Sert à dire au
  /// client POURQUOI ce match lui est proposé quand il a tapé un nom
  /// partiel : « CHE » peut aussi bien ramener Chelsea que Chelmsford.
  final String teamName;

  /// La chaîne du client qui le diffuse, ou `null` : « on a cherché dans
  /// ton guide, on n'a pas trouvé ». Ce n'est pas une erreur — c'est le
  /// cas le plus fréquent quand le guide est incomplet.
  final Channel? channel;
}

class SportSearch {
  SportSearch._();

  /// Combien d'équipes on interroge pour une frappe.
  ///
  /// Chaque équipe coûte UN appel réseau. « CHE » ramène des dizaines
  /// d'équipes ; les interroger toutes ferait une rafale de requêtes à
  /// chaque touche pour, au mieux, remplir l'écran de matchs sans
  /// rapport. Trois couvrent le cas réel (une équipe cherchée, ses
  /// homonymes proches) sans transformer le clavier en sonde réseau.
  static const int kMaxEquipes = 3;

  /// Combien de matchs on affiche au total.
  static const int kMaxMatchs = 10;

  /// DEPUIS QUAND un match reste affiché après son coup d'envoi.
  ///
  /// Trois heures : un match de football dure deux heures avec la
  /// mi-temps, un match de tennis ou de NBA davantage. Le client qui
  /// cherche « Chelsea » à la 80e minute veut évidemment voir le match en
  /// cours — c'est même le moment où il en a le plus besoin.
  static const Duration kDepuis = Duration(hours: 3);

  /// JUSQU'À QUAND on regarde devant.
  ///
  /// Sept jours : le calendrier renvoyé par le serveur couvre les
  /// prochaines journées. Au-delà, ce ne sont plus des matchs « à
  /// regarder » mais un calendrier — ce n'est pas ce qu'on cherche ici,
  /// et ça noierait le match de ce soir.
  static const Duration kJusqua = Duration(days: 7);

  /// Trouve les matchs à regarder pour la requête [q], et la chaîne de
  /// chacun quand le guide du client permet de la nommer.
  ///
  /// BEST-EFFORT INTÉGRAL : pas de réseau, pas de guide, serveur muet →
  /// liste vide, jamais d'exception. Cette méthode est appelée à chaque
  /// frappe sur un clavier de télévision ; elle n'a pas le droit de faire
  /// tomber l'écran de recherche.
  static Future<List<SportSearchHit>> rechercher(
    String q, {
    DateTime? now,
    int maxEquipes = kMaxEquipes,
    int maxMatchs = kMaxMatchs,
  }) async {
    final String requete = q.trim();
    // Sous trois lettres, une recherche d'équipe ramène le monde entier :
    // on attend d'en savoir un peu plus avant de déranger le réseau.
    if (requete.length < 3) return const <SportSearchHit>[];
    final DateTime maintenant = now ?? DateTime.now();
    try {
      final List<SportTeam> equipes =
          await SportsRepository.instance.search(requete);
      if (equipes.isEmpty) return const <SportSearchHit>[];

      final List<({SportEvent event, String teamName})> bruts =
          <({SportEvent event, String teamName})>[];
      for (final SportTeam t in equipes.take(maxEquipes)) {
        final SportsEvents ev = await SportsRepository.instance.eventsOf(t.id);
        for (final SportEvent e in <SportEvent>[...ev.next, ...ev.last]) {
          bruts.add((event: e, teamName: t.name));
        }
      }

      final List<({SportEvent event, String teamName})> retenus =
          classer(bruts, maintenant, maxMatchs: maxMatchs);

      // La chaîne, match par match. MatchChannelFinder garde ses propres
      // réponses en mémoire (y compris « rien trouvé »), donc refrapper
      // une lettre ne relance pas les requêtes SQLite.
      final List<SportSearchHit> sortie = <SportSearchHit>[];
      for (final ({SportEvent event, String teamName}) r in retenus) {
        Channel? ch;
        try {
          ch = await MatchChannelFinder.instance.find(r.event, now: maintenant);
        } catch (_) {
          ch = null; // Guide absent : on montre le match sans la chaîne.
        }
        sortie.add(SportSearchHit(
          event: r.event,
          teamName: r.teamName,
          channel: ch,
        ));
      }
      return sortie;
    } catch (e) {
      if (kDebugMode) debugPrint('[SportSearch] $e');
      return const <SportSearchHit>[];
    }
  }

  /// Choisit et ORDONNE les matchs à montrer. Fonction PURE.
  ///
  /// L'ordre est la décision qui compte, et il suit ce que le client
  /// attend en tapant un nom d'équipe :
  ///
  ///   1. CE QUI JOUE MAINTENANT d'abord. C'est la demande littérale
  ///      (« les chaînes en direct qui passent le match »), et c'est la
  ///      seule chose qu'il ne peut pas rattraper plus tard.
  ///   2. Puis le plus PROCHE dans le temps — à venir comme récent.
  ///
  /// Un même match revient deux fois quand les DEUX équipes sortent de la
  /// recherche (« CHE » → Chelsea, et l'adversaire) : on le dédoublonne
  /// par son identifiant, sinon le client verrait la même affiche côte à
  /// côte et croirait à deux rencontres.
  @visibleForTesting
  static List<({SportEvent event, String teamName})> classer(
    List<({SportEvent event, String teamName})> bruts,
    DateTime now, {
    int maxMatchs = kMaxMatchs,
  }) {
    final DateTime debut = now.subtract(kDepuis);
    final DateTime fin = now.add(kJusqua);

    final Map<String, ({SportEvent event, String teamName})> uniques =
        <String, ({SportEvent event, String teamName})>{};
    for (final ({SportEvent event, String teamName}) r in bruts) {
      final SportEvent e = r.event;
      if (e.id.isEmpty) continue;
      if (uniques.containsKey(e.id)) continue;
      // Un match DÉCLARÉ en direct entre toujours, même si son heure
      // annoncée est fantaisiste : la source qui dit « ça joue » en sait
      // plus que notre calcul de fenêtre.
      if (!e.isLive) {
        final DateTime? d = e.startsAt;
        if (d == null) continue;
        if (d.isBefore(debut) || d.isAfter(fin)) continue;
      }
      uniques[e.id] = r;
    }

    final List<({SportEvent event, String teamName})> liste =
        uniques.values.toList();
    liste.sort((({SportEvent event, String teamName}) a,
        ({SportEvent event, String teamName}) b) {
      final bool aLive = a.event.isLive;
      final bool bLive = b.event.isLive;
      if (aLive != bLive) return aLive ? -1 : 1;
      final DateTime da = a.event.startsAt ?? now;
      final DateTime db = b.event.startsAt ?? now;
      // Distance à MAINTENANT : « ce soir 21 h » doit passer devant
      // « dans six jours », et devant « il y a deux heures ».
      return da
          .difference(now)
          .abs()
          .compareTo(db.difference(now).abs());
    });
    return liste.take(maxMatchs).toList(growable: false);
  }
}
