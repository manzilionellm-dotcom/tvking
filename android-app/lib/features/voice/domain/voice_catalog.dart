// =========================================================
//  voice_catalog.dart — Chercher dans la playlist
// =========================================================
//  Chaînes en direct, films et séries. Tout est déjà en mémoire
//  (liste M3U / Xtream chargée, index cinéma s'il a été construit).
//  On ne télécharge rien ici : si les films ne sont pas encore indexés,
//  on renvoie ce qu'on a (souvent les chaînes) et l'écran le dit.
//
//  Chaque mot de la phrase doit être dans le titre (ou la catégorie).
//  « grand journal » ne trouve pas une chaîne qui s'appelle seulement
//  « Journal ». Les accents sont ignorés (« amelie » trouve « Amélie »).
// =========================================================

import '../../channels/domain/channel.dart';
import '../../cinema/domain/cinema_language.dart';
import '../../cinema/domain/cinema_models.dart';
import 'voice_query.dart';

enum VoiceHitKind { channel, movie, series }

/// Une ligne de résultat. [channel] OU [cinema] est rempli, selon
/// d'où vient le titre. L'écran s'en sert pour ouvrir le bon lecteur
/// sans reconstruire l'URL.
class VoiceHit {
  const VoiceHit({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.channel,
    this.cinema,
  });

  final VoiceHitKind kind;
  final String id;
  final String title;
  final String subtitle;
  final Channel? channel;
  final CinemaTitle? cinema;

  factory VoiceHit.fromChannel(Channel c) {
    return VoiceHit(
      kind: _kindOfChannel(c),
      id: 'ch:${c.id}',
      title: c.cleanName,
      subtitle: c.category,
      channel: c,
    );
  }

  factory VoiceHit.fromCinema(CinemaTitle t) {
    return VoiceHit(
      kind: t.kind == CinemaKind.series
          ? VoiceHitKind.series
          : VoiceHitKind.movie,
      id: 'ci:${t.id}',
      title: t.name,
      subtitle: t.year ?? '',
      cinema: t,
    );
  }
}

/// Chaîne en direct → « chaîne », même si la catégorie dit « cinéma »
/// (Ciné+ est une chaîne). Le reste de la playlist (VOD M3U) est rangé
/// en film ou en série d'après le nom, sans lancer le gros classificateur
/// sur les 50 000 chaînes.
VoiceHitKind _kindOfChannel(Channel c) {
  if (c.isLive) return VoiceHitKind.channel;
  final String blob = voiceFold('${c.name} ${c.category}');
  if (blob.contains('serie') ||
      blob.contains('series') ||
      blob.contains('saison') ||
      blob.contains('episode')) {
    return VoiceHitKind.series;
  }
  return VoiceHitKind.movie;
}

/// Préparation d'UNE chaîne pour la recherche. Le classement adulte
/// et la clé sans accents sont faits ici, une fois, pas à chaque
/// frappe. [searchCatalog] s'en sert si on les lui passe.
void prepareChannelSearch(
  Channel channel,
  Map<String, String> hay,
  Set<String> adultIds,
) {
  hay[channel.id] = CinemaLanguage.searchKey(
    '${channel.name} ${channel.category}',
  );
  if (channel.genre == ChannelGenre.adult) adultIds.add(channel.id);
}

/// Note de pertinence d'une ligne (plus petit = mieux placé).
/// [hay] et [query] sont déjà repliés (minuscules, sans accents).
///   0 : le nom commence par la demande, mot entier (« tf1 » → « TF1 »)
///   1 : le nom commence par la demande (« euro » → « Eurosport 2 »)
///   2 : un mot du nom commence par la demande (« sport » → « beIN Sports »)
///   3 : la demande est quelque part dans le nom ou la catégorie
int searchRank(String hay, String query) {
  if (hay.startsWith(query)) {
    if (hay.length == query.length || hay[query.length] == ' ') return 0;
    return 1;
  }
  if (hay.contains(' $query')) return 2;
  return 3;
}

/// Nombre de fautes de frappe tolérées pour un mot de cette longueur.
/// Un mot court ne pardonne rien : « tf2 » ne doit pas trouver « TF1 ».
int typoBudget(int length) {
  if (length < 4) return 0;
  if (length < 8) return 1;
  return 2;
}

/// Distance d'édition (lettre en trop, en moins, changée, ou deux lettres
/// inversées), arrêtée dès qu'elle dépasse [max]. Rend `max + 1` au-delà.
int typoDistance(String a, String b, int max) {
  final int la = a.length;
  final int lb = b.length;
  if ((la - lb).abs() > max) return max + 1;
  List<int> prev2 = List<int>.filled(lb + 1, 0);
  List<int> prev = List<int>.generate(lb + 1, (int i) => i);
  List<int> cur = List<int>.filled(lb + 1, 0);
  for (int i = 1; i <= la; i++) {
    cur[0] = i;
    int best = cur[0];
    final int ca = a.codeUnitAt(i - 1);
    for (int j = 1; j <= lb; j++) {
      final int cb = b.codeUnitAt(j - 1);
      final int cost = ca == cb ? 0 : 1;
      int v = prev[j - 1] + cost;
      if (prev[j] + 1 < v) v = prev[j] + 1;
      if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
      if (i > 1 &&
          j > 1 &&
          ca == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == cb &&
          prev2[j - 2] + 1 < v) {
        v = prev2[j - 2] + 1;
      }
      cur[j] = v;
      if (v < best) best = v;
    }
    if (best > max) return max + 1;
    final List<int> swap = prev2;
    prev2 = prev;
    prev = cur;
    cur = swap;
  }
  return prev[lb];
}

/// Vrai si [word] ressemble à un mot de [hay], à quelques fautes près.
/// On compare aussi au DÉBUT d'un mot plus long : « eurosprt » trouve
/// « eurosport », et « netflx » trouve « netflix ».
bool typoMatches(String hay, String word) {
  final int budget = typoBudget(word.length);
  if (budget == 0) return false;
  for (final String token in hay.split(' ')) {
    if (token.length < word.length - budget) continue;
    if (typoDistance(word, token, budget) <= budget) return true;
    for (int cut = word.length - budget; cut <= word.length + budget; cut++) {
      if (cut < 3 || cut >= token.length) continue;
      if (typoDistance(word, token.substring(0, cut), budget) <= budget) {
        return true;
      }
    }
  }
  return false;
}

/// Recherche locale. [hideAdult] masque le contenu adulte (mode enfants) :
/// on réutilise le même classificateur que le reste de l'app.
///
/// [channelHay] et [adultIds], s'ils sont là, évitent de replier
/// 50 000 noms à chaque lettre. Sans eux, le résultat est le même :
/// on calcule au fil de l'eau.
///
/// CLASSEMENT (13/11/2026). Avant, on montrait les 24 premières lignes
/// dans l'ordre de la liste : « tf1 » pouvait afficher « TF1 Séries
/// Films » avant « TF1 ». Maintenant le meilleur nom passe devant
/// ([searchRank]), puis le plus court, puis l'ordre de la liste.
///
/// FAUTES DE FRAPPE. Si rien ne correspond exactement, une deuxième
/// passe accepte une ou deux fautes par mot ([typoMatches]). Elle ne
/// tourne que dans ce cas : une recherche normale ne coûte pas plus.
List<VoiceHit> searchCatalog({
  required String query,
  required List<Channel> channels,
  required List<CinemaTitle> movies,
  required List<CinemaTitle> series,
  bool hideAdult = false,
  int maxPerKind = 24,
  Map<String, String>? channelHay,
  Set<String>? adultIds,
}) {
  final List<String> words = voiceWords(voiceFold(query));
  if (words.isEmpty) return const <VoiceHit>[];
  final String joined = words.join(' ');
  final int cap = maxPerKind < 1 ? 1 : (maxPerKind > 60 ? 60 : maxPerKind);
  // Au-delà, on arrête de ramasser des candidats : une demande d'une
  // seule lettre ne doit pas trier toute la liste sur une petite box.
  const int pool = 600;

  bool adultChannel(Channel c) {
    if (!hideAdult) return false;
    if (adultIds != null) return adultIds.contains(c.id);
    return c.genre == ChannelGenre.adult;
  }

  bool adultTitle(CinemaTitle t) =>
      hideAdult &&
      ChannelClassifier.classifyGenre(t.name, t.categoryKey) ==
          ChannelGenre.adult;

  String hayOfChannel(Channel c) =>
      channelHay?[c.id] ??
      CinemaLanguage.searchKey('${c.name} ${c.category}');

  bool strict(String hay) {
    for (final String w in words) {
      if (!hay.contains(w)) return false;
    }
    return true;
  }

  bool loose(String hay) {
    for (final String w in words) {
      if (!hay.contains(w) && !typoMatches(hay, w)) return false;
    }
    return true;
  }

  List<VoiceHit> run(bool Function(String hay) accept) {
    final List<_Scored<Channel>> liveC = <_Scored<Channel>>[];
    final List<_Scored<Channel>> movieC = <_Scored<Channel>>[];
    final List<_Scored<Channel>> seriesC = <_Scored<Channel>>[];
    int order = 0;
    for (final Channel c in channels) {
      if (liveC.length >= pool &&
          movieC.length >= pool &&
          seriesC.length >= pool) {
        break;
      }
      if (adultChannel(c)) continue;
      final String hay = hayOfChannel(c);
      if (!accept(hay)) continue;
      final List<_Scored<Channel>> bucket = switch (_kindOfChannel(c)) {
        VoiceHitKind.channel => liveC,
        VoiceHitKind.movie => movieC,
        VoiceHitKind.series => seriesC,
      };
      if (bucket.length >= pool) continue;
      bucket.add(
        _Scored<Channel>(c, searchRank(hay, joined), hay.length, order++),
      );
    }
    final List<_Scored<CinemaTitle>> movieT = <_Scored<CinemaTitle>>[];
    final List<_Scored<CinemaTitle>> seriesT = <_Scored<CinemaTitle>>[];
    void scan(List<CinemaTitle> from, List<_Scored<CinemaTitle>> into) {
      for (final CinemaTitle t in from) {
        if (into.length >= pool) break;
        if (adultTitle(t)) continue;
        final String hay =
            CinemaLanguage.searchKey('${t.name} ${t.categoryKey}');
        if (!accept(hay)) continue;
        into.add(
          _Scored<CinemaTitle>(
            t,
            searchRank(hay, joined),
            hay.length,
            order++,
          ),
        );
      }
    }

    scan(movies, movieT);
    scan(series, seriesT);

    final Set<String> seen = <String>{};
    final List<VoiceHit> channelsOut = <VoiceHit>[];
    final List<VoiceHit> moviesOut = <VoiceHit>[];
    final List<VoiceHit> seriesOut = <VoiceHit>[];
    void add(VoiceHit hit, List<VoiceHit> bucket) {
      if (bucket.length >= cap) return;
      final String key =
          '${hit.kind.name}|${CinemaLanguage.searchKey(hit.title)}';
      if (!seen.add(key)) return;
      bucket.add(hit);
    }

    // cleanName (curator) seulement pour les lignes qu'on va montrer.
    void takeChannels(List<_Scored<Channel>> from, List<VoiceHit> into) {
      from.sort(_Scored.compare);
      for (final _Scored<Channel> s in from) {
        if (into.length >= cap) break;
        add(VoiceHit.fromChannel(s.item), into);
      }
    }

    void takeTitles(List<_Scored<CinemaTitle>> from, List<VoiceHit> into) {
      from.sort(_Scored.compare);
      for (final _Scored<CinemaTitle> s in from) {
        if (into.length >= cap) break;
        add(VoiceHit.fromCinema(s.item), into);
      }
    }

    takeChannels(liveC, channelsOut);
    takeChannels(movieC, moviesOut);
    takeTitles(movieT, moviesOut);
    takeChannels(seriesC, seriesOut);
    takeTitles(seriesT, seriesOut);
    return <VoiceHit>[...channelsOut, ...moviesOut, ...seriesOut];
  }

  final List<VoiceHit> exact = run(strict);
  if (exact.isNotEmpty) return exact;
  // Rien d'exact : on retente en pardonnant les fautes de frappe, si au
  // moins un mot est assez long pour ça.
  if (!words.any((String w) => typoBudget(w.length) > 0)) return exact;
  return run(loose);
}

/// Une ligne candidate et sa note. Tri : note, puis nom le plus court
/// (« TF1 » avant « TF1 Séries Films »), puis ordre de la liste.
class _Scored<T> {
  const _Scored(this.item, this.rank, this.length, this.order);
  final T item;
  final int rank;
  final int length;
  final int order;

  static int compare(_Scored<Object?> a, _Scored<Object?> b) {
    if (a.rank != b.rank) return a.rank - b.rank;
    if (a.length != b.length) return a.length - b.length;
    return a.order - b.order;
  }
}

/// Quand l'aide distante (réglage, désactivé par défaut) a compris la
/// phrase, on met SES chaînes devant. Les films et séries restent ceux
/// trouvés sur la box : le service ne reçoit jamais le catalogue.
///
/// Liste vide ou nulle → on garde la recherche locale telle quelle.
/// Un service muet ne doit pas effacer les résultats déjà affichés.
List<VoiceHit> mergeRemoteChannels({
  required List<VoiceHit> local,
  required List<VoiceHit>? remoteChannels,
}) {
  if (remoteChannels == null || remoteChannels.isEmpty) return local;
  final List<VoiceHit> rest = <VoiceHit>[
    for (final VoiceHit h in local)
      if (h.kind != VoiceHitKind.channel) h,
  ];
  return <VoiceHit>[...remoteChannels, ...rest];
}
