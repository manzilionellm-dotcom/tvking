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

/// Recherche locale. [hideAdult] masque le contenu adulte (mode enfants) :
/// on réutilise le même classificateur que le reste de l'app.
List<VoiceHit> searchCatalog({
  required String query,
  required List<Channel> channels,
  required List<CinemaTitle> movies,
  required List<CinemaTitle> series,
  bool hideAdult = false,
  int maxPerKind = 24,
}) {
  final List<String> words = voiceWords(voiceFold(query));
  if (words.isEmpty) return const <VoiceHit>[];
  final int cap = maxPerKind < 1 ? 1 : (maxPerKind > 60 ? 60 : maxPerKind);

  bool matches(String haystack) {
    final String hay = CinemaLanguage.searchKey(haystack);
    for (final String w in words) {
      if (!hay.contains(w)) return false;
    }
    return true;
  }

  bool adultChannel(Channel c) =>
      hideAdult && c.genre == ChannelGenre.adult;

  bool adultTitle(CinemaTitle t) =>
      hideAdult &&
      ChannelClassifier.classifyGenre(t.name, t.categoryKey) ==
          ChannelGenre.adult;

  final List<VoiceHit> channelsOut = <VoiceHit>[];
  final List<VoiceHit> moviesOut = <VoiceHit>[];
  final List<VoiceHit> seriesOut = <VoiceHit>[];
  final Set<String> seen = <String>{};

  void add(VoiceHit hit, List<VoiceHit> bucket) {
    if (bucket.length >= cap) return;
    final String key = '${hit.kind.name}|${CinemaLanguage.searchKey(hit.title)}';
    if (!seen.add(key)) return;
    bucket.add(hit);
  }

  for (final Channel c in channels) {
    if (adultChannel(c)) continue;
    if (!matches('${c.name} ${c.category}')) continue;
    final VoiceHitKind kind = _kindOfChannel(c);
    final List<VoiceHit> bucket = switch (kind) {
      VoiceHitKind.channel => channelsOut,
      VoiceHitKind.movie => moviesOut,
      VoiceHitKind.series => seriesOut,
    };
    // cleanName (curator) seulement pour les lignes qu'on va montrer.
    if (bucket.length >= cap) continue;
    add(VoiceHit.fromChannel(c), bucket);
  }
  for (final CinemaTitle t in movies) {
    if (adultTitle(t)) continue;
    if (!matches('${t.name} ${t.categoryKey}')) continue;
    add(VoiceHit.fromCinema(t), moviesOut);
  }
  for (final CinemaTitle t in series) {
    if (adultTitle(t)) continue;
    if (!matches('${t.name} ${t.categoryKey}')) continue;
    add(VoiceHit.fromCinema(t), seriesOut);
  }

  return <VoiceHit>[...channelsOut, ...moviesOut, ...seriesOut];
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
