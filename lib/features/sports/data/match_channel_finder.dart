// =========================================================
//  match_channel_finder.dart — « SUR QUELLE CHAÎNE ? »
// =========================================================
//  QUESTION DU PROPRIÉTAIRE (07/09/2026), devant l'écran Sport à
//  21 h 30 : « il n'y a pas de match en direct — quelle chaîne le
//  montre ? »
//
//  Les deux moitiés de sa phrase sont deux problèmes différents :
//
//    • « pas de match en direct » — ce n'est pas un bug. À 21 h 30, les
//      matchs affichés commencent à 22 h 00 et 23 h 00. Rien ne joue
//      encore. L'écran dit la vérité.
//
//    • « quelle chaîne le montre » — ÇA, ça manquait. On listait les
//      affiches sans jamais dire où les regarder, alors que le client a
//      justement une playlist et un guide dans la même application.
//
//  ---------------------------------------------------------
//  L'ERREUR QU'IL NE FALLAIT PAS REFAIRE
//  ---------------------------------------------------------
//  La fiche de match cherchait déjà une chaîne, mais avec
//  `searchAiringNow` : « qu'est-ce qui passe MAINTENANT ». Pour un match
//  à 22 h consulté à 21 h 30, la réponse est forcément « rien » — à cet
//  instant la chaîne diffuse encore le journal. On interroge donc le
//  guide À L'HEURE DU COUP D'ENVOI (+ quelques minutes, le temps que le
//  plateau d'avant-match laisse la place au coup d'envoi lui-même).
//
//  ---------------------------------------------------------
//  POURQUOI UN MODULE, ET PAS DU CODE DANS L'ÉCRAN
//  ---------------------------------------------------------
//  Deux appelants : la CARTE de la liste (« 📺 beIN SPORTS 1 » sous le
//  match) et la FICHE du match (le lecteur en haut). Le jour où l'un des
//  deux chercherait autrement, le client verrait une chaîne sur la liste
//  et une autre — ou aucune — en ouvrant. Une seule implémentation.
//
//  Et un CACHE mémoire par identifiant de match : la liste reconstruit
//  ses cartes à chaque défilement, on ne relance pas deux requêtes
//  SQLite par carte à chaque fois.
// =========================================================

import 'package:flutter/foundation.dart';

import '../../channels/domain/channel.dart';
import '../../epg/data/epg_repository.dart';
import '../../epg/domain/epg_program.dart';
import '../../playlists/data/playlist_repository.dart';
import '../domain/sport_models.dart';
import 'sport_country_prefs.dart';

class MatchChannelFinder {
  MatchChannelFinder._();
  static final MatchChannelFinder instance = MatchChannelFinder._();

  /// Résultat par identifiant de match. `null` EST une réponse : « on a
  /// cherché, il n'y a rien ». On la garde pour ne pas rechercher en
  /// boucle un match que le guide du client ne couvre pas.
  final Map<String, Channel?> _cache = <String, Channel?>{};

  /// Recherches en cours, pour que deux cartes affichées en même temps
  /// ne lancent pas deux fois la même requête.
  final Map<String, Future<Channel?>> _enVol = <String, Future<Channel?>>{};

  @visibleForTesting
  void debugReset() {
    _cache.clear();
    _enVol.clear();
  }

  /// Chaîne du client qui diffuse [e], ou null si on n'en trouve pas.
  ///
  /// BEST-EFFORT ABSOLU : sans guide importé, sans playlist, ou si la
  /// base n'est pas prête, on rend null sans bruit. Un écran Sport ne
  /// doit jamais tomber parce qu'un guide manque.
  Future<Channel?> find(SportEvent e, {DateTime? now}) {
    if (_cache.containsKey(e.id)) return Future<Channel?>.value(_cache[e.id]);
    final Future<Channel?>? enCours = _enVol[e.id];
    if (enCours != null) return enCours;
    final Future<Channel?> f = _chercher(e, now ?? DateTime.now());
    _enVol[e.id] = f;
    return f;
  }

  Future<Channel?> _chercher(SportEvent e, DateTime now) async {
    Channel? trouvee;
    try {
      final List<String> noms = searchTerms(e);
      if (noms.isNotEmpty) {
        final int instant = lookupInstant(e, now);
        final List<EpgProgram> candidats = <EpgProgram>[];
        for (final String n in noms) {
          candidats.addAll(await EpgRepository.instance
              .searchAiringAt(n, atMs: instant, limit: 20));
        }
        // UNE seule requête pour toutes les chaînes candidates. On les
        // résout AVANT de choisir, parce que le pays — le critère que
        // le client vient de régler — est porté par la chaîne, pas par
        // le programme.
        final List<String> ids = <String>{
          for (final EpgProgram p in candidats) p.channelId,
        }.toList(growable: false);
        final List<Channel> chs =
            await PlaylistRepository.instance.getChannelsByExternalIds(ids);
        final Map<String, Channel> byId = <String, Channel>{
          for (final Channel c in chs) c.id: c,
        };
        final List<({EpgProgram program, Channel channel})> paires =
            <({EpgProgram program, Channel channel})>[
          for (final EpgProgram p in candidats)
            if (byId[p.channelId] != null)
              (program: p, channel: byId[p.channelId]!),
        ];
        trouvee = pickBest(paires, noms, SportCountryPrefs.instance.code);
      }
    } catch (_) {
      trouvee = null;
    }
    _cache[e.id] = trouvee;
    _enVol.remove(e.id);
    return trouvee;
  }

  /// Vide le cache — à appeler quand le client CHANGE de pays, sinon il
  /// continuerait de voir les chaînes choisies avec l'ancien réglage et
  /// croirait que le réglage ne sert à rien.
  void invalidate() {
    _cache.clear();
  }

  // ---------------------------------------------------------
  //  Les trois décisions, isolées et testables sans base
  // ---------------------------------------------------------

  /// À QUEL INSTANT interroger le guide.
  ///
  /// Match en cours → maintenant. Match à venir ou passé → son coup
  /// d'envoi, décalé de 10 minutes : les guides font commencer la case
  /// à l'heure ronde alors que le direct démarre un peu après, et une
  /// requête pile à l'heure tombe parfois sur l'émission d'avant.
  ///
  /// Sans heure connue, on retombe sur maintenant : c'est tout ce qu'on
  /// peut faire, et ça reste juste pour un match qui joue.
  @visibleForTesting
  static int lookupInstant(SportEvent e, DateTime now) {
    if (e.isLive) return now.millisecondsSinceEpoch;
    final DateTime? debut = e.startsAt;
    if (debut == null) return now.millisecondsSinceEpoch;
    return debut.add(const Duration(minutes: 10)).millisecondsSinceEpoch;
  }

  /// Ce qu'on cherche dans les titres du guide.
  ///
  /// Les noms d'équipes, pas le titre du match : un guide écrit
  /// « Barracas Central / Argentinos Juniors », « Barracas - Argentinos »
  /// ou « Football : Barracas Central », jamais exactement la forme de
  /// TheSportsDB. Les noms courts (« PSG » suffit, mais « FC » non) sont
  /// écartés : sous trois lettres, un LIKE ramène n'importe quoi.
  @visibleForTesting
  static List<String> searchTerms(SportEvent e) {
    final List<String> out = <String>[];
    for (final String s in <String>[e.home, e.away]) {
      final String t = s.trim();
      if (t.length >= 3) out.add(t);
    }
    // Épreuve sans duel (course, tournoi) : le nom de l'épreuve est tout
    // ce qu'on a, et il figure souvent tel quel dans le guide.
    if (out.isEmpty && e.name.trim().length >= 4) out.add(e.name.trim());
    return out;
  }

  /// La MEILLEURE chaîne parmi les candidates.
  ///
  /// Deux critères, et l'ordre entre eux est la décision importante :
  ///
  ///   1. LE TITRE cite-t-il LES DEUX équipes ? « Barracas Central /
  ///      Argentinos Juniors » est le match ; une émission qui ne cite
  ///      que « Barracas » peut être un magazine, un résumé, ou le match
  ///      d'une autre équipe de la ville.
  ///   2. LA CHAÎNE est-elle du pays choisi par le client ? Trois
  ///      chaînes diffusent souvent le même match : le client veut la
  ///      sienne, dans sa langue.
  ///
  ///  LE TITRE PASSE AVANT LE PAYS, volontairement. Envoyer quelqu'un
  ///  sur le bon match commenté dans une autre langue reste utile ;
  ///  l'envoyer sur un magazine de sa langue pendant que le match joue
  ///  ailleurs, non. Le pays départage, il ne décide pas seul.
  ///
  ///  Fonction PURE (aucune base, aucun réseau) : c'est là que se joue
  ///  la promesse faite au client, donc c'est testable directement.
  @visibleForTesting
  static Channel? pickBest(
    List<({EpgProgram program, Channel channel})> candidats,
    List<String> noms,
    String preferredCountry,
  ) {
    if (candidats.isEmpty || noms.isEmpty) return null;
    final List<String> bas =
        noms.map((String n) => n.toLowerCase()).toList(growable: false);
    final String pays = preferredCountry.trim().toUpperCase();

    Channel? best;
    int meilleurScore = -1;
    for (final ({EpgProgram program, Channel channel}) c in candidats) {
      final String t = c.program.title.toLowerCase();
      int score = 0;
      if (bas.every((String n) => t.contains(n))) score += 4;
      if (pays.isNotEmpty && (c.channel.country?.code.toUpperCase() == pays)) {
        score += 2;
      }
      // `>` et non `>=` : à égalité, le PREMIER gagne — c'est l'ordre du
      // guide, donc l'émission qui a commencé le plus récemment (cf.
      // searchAiringNowIn). Un `>=` ferait gagner le dernier arrivé, et
      // le même match changerait de chaîne d'un rafraîchissement à
      // l'autre sans raison visible.
      if (score > meilleurScore) {
        meilleurScore = score;
        best = c.channel;
      }
    }
    return best;
  }
}
