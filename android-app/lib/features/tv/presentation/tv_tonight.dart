// =========================================================
//  tv_tonight.dart — « Ce soir », uniquement ce qui est déjà là
// =========================================================
//  Aucune affiche n'est embarquée. Une image n'apparaît que si
//  l'URL vient de la liste de la personne : jaquette VOD, logo
//  de chaîne, rien d'autre. Les titres du maquette (films connus)
//  ne sont pas des données : ils ne sont pas dans ce fichier.
// =========================================================
import '../../channels/domain/channel.dart';
import '../../cinema/data/watch_progress.dart';
import '../../epg/domain/program_reminder.dart';
import '../../followed/domain/show_clock.dart';

/// Une carte de l'accueil. [watch] ou [channel] dit quoi lancer.
class TonightPiece {
  const TonightPiece({
    required this.title,
    this.artworkUrl,
    this.meta = '',
    this.channel,
    this.watch,
  });

  final String title;

  /// URL déjà fournie par la source (jaquette ou logo). Null = pas d'image.
  final String? artworkUrl;
  final String meta;
  final Channel? channel;
  final WatchEntry? watch;

  bool get canPlay => watch != null || channel != null;
}

class TonightBoard {
  const TonightBoard({
    this.hero,
    this.heroDetail = '',
    this.recommendations = const <TonightPiece>[],
    this.discover = const <TonightPiece>[],
  });

  final TonightPiece? hero;

  /// Ligne sous « Ce soir » : nom de chaîne, sous-titre d'épisode, ou vide.
  final String heroDetail;
  final List<TonightPiece> recommendations;
  final List<TonightPiece> discover;

  bool get hasHero => hero != null && hero!.title.isNotEmpty;
}

String? _httpArt(String? url) {
  final String t = (url ?? '').trim();
  if (t.isEmpty) return null;
  return t;
}

String _minutes(int ms) {
  if (ms <= 0) return '';
  final int min = (ms / 60000).round();
  if (min <= 0) return '';
  return '$min min';
}

/// 4K / HDR seulement si le nom de la source le dit vraiment.
/// « VIP » ou un chiffre inventé ne comptent pas.
String? streamQualityLabel(String raw) {
  final String t = raw.toLowerCase();
  final bool k4 =
      RegExp(r'(^|[^a-z0-9])(4k|uhd|2160p)([^a-z0-9]|$)').hasMatch(t);
  final bool hdr = RegExp(r'(^|[^a-z0-9])hdr([^a-z0-9]|$)').hasMatch(t);
  if (k4 && hdr) return '4K HDR';
  if (k4) return '4K';
  if (hdr) return 'HDR';
  return null;
}

/// Note 0–10 venue de la fiche. Hors de là, ou absente : rien.
String? ratingLabel(double? rating) {
  if (rating == null || rating <= 0 || rating > 10) return null;
  return rating.toStringAsFixed(1);
}

String joinCrispMeta({
  String duration = '',
  String? quality,
  String? year,
  double? rating,
}) {
  final String? note = ratingLabel(rating);
  final List<String> parts = <String>[
    if (year != null && year.trim().isNotEmpty) year.trim(),
    if (duration.isNotEmpty) duration,
    if (quality != null) quality,
    if (note != null) note,
  ];
  return parts.join(' · ');
}

/// Choisit le héros et deux rangées courtes. Pur : pas de réseau.
TonightBoard composeTonight({
  required List<WatchEntry> watching,
  required List<Channel> favorites,
  required List<Channel> popular,
  required List<Channel> resume,
  required List<GuideSlot> guide,
  required List<ProgramReminder> reminders,
  required List<Channel> also,
  required int nowMs,
  required Map<String, Channel> channelsById,
}) {
  final List<WatchEntry> vod = <WatchEntry>[
    for (final WatchEntry w in watching)
      if (w.title.trim().isNotEmpty) w,
  ];
  GuideSlot? onNow;
  for (final GuideSlot slot in guide) {
    if (slot.startMs <= nowMs &&
        nowMs < slot.stopMs &&
        slot.title.trim().isNotEmpty) {
      onNow = slot;
      break;
    }
  }

  TonightPiece? hero;
  String detail = '';
  if (vod.isNotEmpty) {
    final WatchEntry w = vod.first;
    hero = TonightPiece(
      title: w.title.trim(),
      artworkUrl: _httpArt(w.posterUrl),
      meta: joinCrispMeta(
        duration: _minutes(w.durMs),
        quality: streamQualityLabel(w.title),
      ),
      watch: w,
    );
    detail = (w.subtitle ?? '').trim();
  } else if (onNow != null) {
    final Channel? channel = channelsById[onNow.channelId];
    hero = TonightPiece(
      title: onNow.title.trim(),
      artworkUrl: _httpArt(channel?.logoUrl),
      meta: joinCrispMeta(
        duration: _minutes(onNow.stopMs - onNow.startMs),
        quality: streamQualityLabel(channel?.name ?? ''),
      ),
      channel: channel,
    );
    detail = onNow.channelName.trim();
  } else if (reminders.isNotEmpty && reminders.first.title.trim().isNotEmpty) {
    final ProgramReminder reminder = reminders.first;
    final Channel? channel = channelsById[reminder.channelId];
    hero = TonightPiece(
      title: reminder.title.trim(),
      artworkUrl: _httpArt(channel?.logoUrl),
      meta: joinCrispMeta(quality: streamQualityLabel(channel?.name ?? '')),
      channel: channel,
    );
    detail = reminder.channelName.trim();
  } else if (favorites.isNotEmpty) {
    final Channel channel = favorites.first;
    hero = TonightPiece(
      title: channel.cleanName,
      artworkUrl: _httpArt(channel.logoUrl),
      meta: joinCrispMeta(quality: streamQualityLabel(channel.name)),
      channel: channel,
    );
  } else if (resume.isNotEmpty) {
    final Channel channel = resume.first;
    hero = TonightPiece(
      title: channel.cleanName,
      artworkUrl: _httpArt(channel.logoUrl),
      meta: joinCrispMeta(quality: streamQualityLabel(channel.name)),
      channel: channel,
    );
  }

  final Set<String> used = <String>{};
  if (hero?.watch != null) used.add('w:${hero!.watch!.id}');
  if (hero?.channel != null) used.add('c:${hero!.channel!.id}');

  TonightPiece pieceWatch(WatchEntry w) => TonightPiece(
        title: w.title.trim(),
        artworkUrl: _httpArt(w.posterUrl),
        meta: joinCrispMeta(
        duration: _minutes(w.durMs),
        quality: streamQualityLabel(w.title),
      ),
        watch: w,
      );
  TonightPiece pieceChannel(Channel c) => TonightPiece(
        title: c.cleanName,
        artworkUrl: _httpArt(c.logoUrl),
        meta: joinCrispMeta(quality: streamQualityLabel(c.name)),
        channel: c,
      );

  final List<TonightPiece> recs = <TonightPiece>[];
  void takeWatch(WatchEntry w) {
    if (recs.length >= 8) return;
    if (!used.add('w:${w.id}')) return;
    recs.add(pieceWatch(w));
  }

  void takeChannel(List<TonightPiece> into, Channel c) {
    if (into.length >= 8) return;
    if (!used.add('c:${c.id}')) return;
    into.add(pieceChannel(c));
  }

  for (final WatchEntry w in vod) {
    takeWatch(w);
  }
  for (final Channel c in favorites) {
    takeChannel(recs, c);
  }
  for (final ProgramReminder reminder in reminders) {
    if (recs.length >= 8) break;
    final Channel? channel = channelsById[reminder.channelId];
    if (channel != null) {
      takeChannel(recs, channel);
      continue;
    }
    if (reminder.title.trim().isEmpty) continue;
    if (!used.add('r:${reminder.channelId}@${reminder.startMs}')) continue;
    recs.add(TonightPiece(title: reminder.title.trim(), meta: reminder.channelName));
  }
  if (recs.isEmpty) {
    for (final Channel c in popular) {
      takeChannel(recs, c);
    }
  }

  final List<TonightPiece> discover = <TonightPiece>[];
  for (final Channel c in popular) {
    takeChannel(discover, c);
  }
  for (final Channel c in resume) {
    takeChannel(discover, c);
  }
  for (final Channel c in also) {
    takeChannel(discover, c);
  }

  return TonightBoard(
    hero: hero,
    heroDetail: detail,
    recommendations: recs,
    discover: discover,
  );
}
