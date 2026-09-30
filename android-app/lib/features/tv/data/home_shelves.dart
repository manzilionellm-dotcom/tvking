// =========================================================
//  home_shelves.dart — Ce que l'accueil a le droit de montrer
// =========================================================
//  Fonctions PURES : pas de disque, pas de réseau, pas de setState.
//  L'écran leur donne les listes déjà chargées (chaînes, favoris,
//  historique, tendances, films entamés, rappels) et récupère des
//  rangées courtes, dans un ordre stable.
//
//  Pourquoi « court » : une box peut avoir 50 000 chaînes. On ne
//  dessine jamais plus de [kHomeShelfMax] cartes, et on ne lance
//  JAMAIS le nettoyeur de titres (dizaines de regex) sur toute la
//  liste — c'est ce qui figeait le Direct (ANR). Le rapprochement
//  « populaire » utilise une clé grossière, dans un isolate si la
//  liste est grosse (voir [matchTrendingChannelIds]).
// =========================================================

import 'package:flutter/foundation.dart';

import '../../channels/domain/channel.dart';
import '../../cinema/data/watch_progress.dart';
import '../../epg/domain/program_reminder.dart';

/// Nombre de cartes par rangée. Au-delà, la télécommande scrolle
/// longtemps pour rien : 8 suffisent pour revenir, le Direct a le reste.
const int kHomeShelfMax = 8;

/// Moment de la journée pour le bonjour (heure LOCALE de la box).
enum HomeDayPart { morning, afternoon, evening }

/// 5 h → midi : bonjour. Midi → 18 h : bon après-midi. Sinon : bonsoir.
HomeDayPart homeDayPart(int hour) {
  if (hour >= 5 && hour < 12) return HomeDayPart.morning;
  if (hour >= 12 && hour < 18) return HomeDayPart.afternoon;
  return HomeDayPart.evening;
}

/// Quelle rangée reçoit le focus au premier affichage.
/// Un rappel dans la demi-heure passe devant : c'est la personne qui
/// l'a demandé, on ne le cache pas derrière les favoris.
enum HomeShelfKind { reminders, resume, continueWatching, favorites, popular }

HomeShelfKind? pickInitialShelf({
  required bool hasSoonReminder,
  required bool hasResume,
  required bool hasContinue,
  required bool hasFavorites,
  required bool hasPopular,
}) {
  if (hasSoonReminder) return HomeShelfKind.reminders;
  if (hasResume) return HomeShelfKind.resume;
  if (hasContinue) return HomeShelfKind.continueWatching;
  if (hasFavorites) return HomeShelfKind.favorites;
  if (hasPopular) return HomeShelfKind.popular;
  return null;
}

/// Les chaînes de l'accueil, déjà filtrées et bornées.
@immutable
class HomeShelfModel {
  const HomeShelfModel({
    this.resume = const <Channel>[],
    this.favorites = const <Channel>[],
    this.popular = const <Channel>[],
    this.continueWatching = const <WatchEntry>[],
    this.reminders = const <ProgramReminder>[],
  });

  /// Dernières chaînes en direct, la plus récente en premier.
  final List<Channel> resume;

  /// Favoris, dans l'ordre de la playlist (pas un ordre aléatoire).
  final List<Channel> favorites;

  /// Tendances du moment, limitées aux chaînes de CETTE playlist.
  final List<Channel> popular;

  /// Films / épisodes entamés (reprise à la bonne minute).
  final List<WatchEntry> continueWatching;

  /// Rappels posés par l'utilisateur, du plus proche au plus lointain.
  final List<ProgramReminder> reminders;

  bool get hasAny =>
      resume.isNotEmpty ||
      favorites.isNotEmpty ||
      popular.isNotEmpty ||
      continueWatching.isNotEmpty ||
      reminders.isNotEmpty;

  Channel? get lastChannel => resume.isEmpty ? null : resume.first;
}

/// Index id → chaîne. Une passe, réutilisé par toutes les rangées.
Map<String, Channel> indexChannelsById(List<Channel> channels) =>
    <String, Channel>{for (final Channel c in channels) c.id: c};

/// Chaînes dans l'ordre des [ids] (historique, tendances…). Les ids
/// inconnus sont ignorés : la playlist a pu changer depuis.
List<Channel> channelsInIdOrder(
  List<String> ids,
  Map<String, Channel> byId, {
  int max = kHomeShelfMax,
  bool Function(Channel channel)? hide,
}) {
  if (ids.isEmpty || byId.isEmpty || max <= 0) return const <Channel>[];
  final List<Channel> out = <Channel>[];
  for (final String id in ids) {
    final Channel? c = byId[id];
    if (c == null) continue;
    if (hide != null && hide(c)) continue;
    out.add(c);
    if (out.length >= max) break;
  }
  return out;
}

/// Favoris dans l'ordre de la playlist. On ne parcourt la liste qu'avec
/// un test d'ensemble (rapide) ; le filtre enfants ne s'applique qu'aux
/// favoris réellement rencontrés, jamais à 50 000 noms.
List<Channel> favoriteChannels(
  List<Channel> channels,
  Set<String> favoriteIds, {
  int max = kHomeShelfMax,
  bool Function(Channel channel)? hide,
}) {
  if (favoriteIds.isEmpty || channels.isEmpty || max <= 0) {
    return const <Channel>[];
  }
  final List<Channel> out = <Channel>[];
  for (final Channel c in channels) {
    if (!favoriteIds.contains(c.id)) continue;
    if (hide != null && hide(c)) continue;
    out.add(c);
    if (out.length >= max) break;
  }
  return out;
}

/// « Continuer à regarder », déjà trié par le dépôt. En Mode Enfants on
/// retire seulement les titres qui se classent Adulte (quelques cartes,
/// pas tout le catalogue).
List<WatchEntry> continueForHome(
  List<WatchEntry> entries, {
  required bool kidsMode,
  int max = kHomeShelfMax,
}) {
  if (entries.isEmpty || max <= 0) return const <WatchEntry>[];
  final List<WatchEntry> out = <WatchEntry>[];
  for (final WatchEntry e in entries) {
    if (!e.isResumable) continue;
    if (kidsMode && _titleLooksAdult(e.title)) continue;
    out.add(e);
    if (out.length >= max) break;
  }
  return out;
}

bool _titleLooksAdult(String title) =>
    ChannelClassifier.classifyGenre(title, '') == ChannelGenre.adult;

/// Mode Enfants sur une chaîne de l'accueil.
///
///   • Genre déjà en cache « adulte » → masquée.
///   • Genre déjà en cache autre chose → visible.
///   • Pas encore classée → on regarde quelques mots du nom BRUT
///     (`xxx`, `porn`, `adult`). On ne lance pas le classifieur complet :
///     ce serait des dizaines de regex par chaîne, sur le fil de l'écran.
///     Une chaîne au nom neutre reste visible ; le Direct, lui, reste
///     plus strict le temps du pré-calcul.
bool hiddenForKids(Channel channel) {
  final ChannelGenre? known = ChannelPrecompute.cachedGenre(channel);
  if (known == ChannelGenre.adult) return true;
  if (known != null) return false;
  return roughLooksAdult(channel.name) || roughLooksAdult(channel.category);
}

/// Vrai si le texte brut contient un marqueur adulte évident.
bool roughLooksAdult(String raw) {
  final String s = raw.toLowerCase();
  return s.contains('xxx') || s.contains('porn') || s.contains('adult');
}

// -----------------------------------------------------------------
//  « Populaire maintenant » — rapprochement léger, hors du fil UI
// -----------------------------------------------------------------

/// Clé grossière pour comparer un nom de tendance (déjà propre, envoyé
/// par les box) et un nom de playlist (souvent « FR| TF1 HD »).
///
/// On retire un préfixe pays (`fr|`, `uk:`), quelques suffixes techniques
/// et tout ce qui n'est pas une lettre ou un chiffre. « TF1 » et
/// « FR| TF1 HD » deviennent tous les deux `tf1`. Ce n'est pas le
/// nettoyeur complet (TitleCurator) : volontairement, pour rester bon
/// marché sur une grosse liste.
String roughChannelKey(String raw) {
  String s = raw.toLowerCase().trim();
  s = s.replaceFirst(RegExp(r'^[a-z]{2,3}\s*[|:]\s*'), '');
  s = s.replaceAll(
    RegExp(
        r'\b(fhd|uhd|hd|sd|4k|2160p|1080p|720p|hevc|h\.?265|raw|vip|backup)\b'),
    ' ',
  );
  return s.replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

/// À partir de cette taille, le rapprochement part dans un isolate
/// ([compute]) pour ne pas bloquer la télécommande.
const int kPopularIsolateThreshold = 2500;

/// Fonction d'isolate. Entrée et sortie : uniquement des [String].
///
/// Charge utile :
///   names : noms tendance, du plus regardé au moins regardé
///   ids   : identifiants de la playlist (même ordre que raws)
///   raws  : noms bruts
///   cats  : catégories brutes (même ordre), optionnel
///   kids  : si vrai, on ignore un nom OU une catégorie à marqueur adulte
///
/// Renvoie au plus [kHomeShelfMax] identifiants, dans l'ordre des tendances.
List<String> matchTrendingChannelIds(Map<String, Object?> payload) {
  final List<String> names = ((payload['names'] as List?) ?? const <Object>[])
      .map((Object? e) => '$e')
      .toList(growable: false);
  final List<String> ids = ((payload['ids'] as List?) ?? const <Object>[])
      .map((Object? e) => '$e')
      .toList(growable: false);
  final List<String> raws = ((payload['raws'] as List?) ?? const <Object>[])
      .map((Object? e) => '$e')
      .toList(growable: false);
  final List<String> cats = ((payload['cats'] as List?) ?? const <Object>[])
      .map((Object? e) => '$e')
      .toList(growable: false);
  final bool kids = payload['kids'] == true;
  if (names.isEmpty || ids.isEmpty || ids.length != raws.length) {
    return const <String>[];
  }

  final Map<String, String> idByKey = <String, String>{};
  for (int i = 0; i < ids.length; i++) {
    final String cat = i < cats.length ? cats[i] : '';
    if (kids && (roughLooksAdult(raws[i]) || roughLooksAdult(cat))) continue;
    final String key = roughChannelKey(raws[i]);
    if (key.isEmpty) continue;
    idByKey.putIfAbsent(key, () => ids[i]);
  }

  final List<String> out = <String>[];
  final Set<String> seen = <String>{};
  for (final String name in names) {
    if (kids && roughLooksAdult(name)) continue;
    final String? id = idByKey[roughChannelKey(name)];
    if (id == null || !seen.add(id)) continue;
    out.add(id);
    if (out.length >= kHomeShelfMax) break;
  }
  return out;
}

/// Rapproche les tendances de la playlist. Sur une petite liste, on le
/// fait ici ; sur une grosse, dans un isolate.
Future<List<String>> resolvePopularIds({
  required List<String> trendingNames,
  required List<Channel> channels,
  required bool kidsMode,
}) async {
  if (trendingNames.isEmpty || channels.isEmpty) return const <String>[];
  final Map<String, Object?> payload = <String, Object?>{
    'names': trendingNames,
    'ids': <String>[for (final Channel c in channels) c.id],
    'raws': <String>[for (final Channel c in channels) c.name],
    'cats': <String>[for (final Channel c in channels) c.category],
    'kids': kidsMode,
  };
  if (channels.length < kPopularIsolateThreshold) {
    return matchTrendingChannelIds(payload);
  }
  return compute(matchTrendingChannelIds, payload);
}
