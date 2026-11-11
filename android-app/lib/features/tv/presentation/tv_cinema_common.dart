// =========================================================
//  tv_cinema_common.dart — Briques partagées du Cinéma (Films / Séries)
// =========================================================
//  • VodPlayItem : ce que le lecteur doit jouer (film OU épisode), construit
//    depuis un film, un épisode ou une entrée « Continuer à regarder ».
//  • openVod(...) : LE point d'entrée de lecture — choisit le fichier
//    téléchargé s'il existe (hors ligne), sinon le flux ; applique la
//    reprise ; ouvre le lecteur.
//  • Préférences audio / sous-titres retenues (comme Netflix : si tu as
//    choisi les sous-titres arabes une fois, les films suivants les
//    proposent d'office).
//  • Widgets communs (pilule, affiche, ligne de catégorie) — mêmes jetons
//    (TvTokens / TvDimens) et même comportement de focus que le Direct.
// =========================================================
import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/app/app_platform.dart';
import '../../security/data/parental_controls.dart';
import '../../channels/domain/channel_genre.dart';
import '../../cinema/data/watch_progress.dart';
import '../../cinema/data/cinema_repository.dart';
import '../../profiles/data/active_profile.dart';
import '../../profiles/data/profile_repository.dart';
import '../../security/data/adult_access.dart';
import '../../cinema/domain/resume_start.dart';
import '../../cinema/domain/cinema_models.dart';
import '../../vod/data/download_repository.dart';
import '../../vod/domain/vod_movie.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import '../core/tv_app_tokens.dart';
import 'tv_vod_player_screen.dart';

// =========================================================
//  Ce que le lecteur joue
// =========================================================

@immutable
class VodPlayItem {
  const VodPlayItem({
    required this.id,
    required this.isEpisode,
    required this.title,
    required this.url,
    this.subtitle,
    this.posterUrl,
    this.containerExt = 'mp4',
    this.sourceKey = '',
    this.remoteId = '',
    this.seriesId,
    this.season,
    this.episode,
    this.isAdult = false,
    this.adultClassificationKnown = true,
    this.classification,
  });

  final String id;
  final bool isEpisode;

  /// Film : titre. Épisode : nom de la série.
  final String title;

  /// Épisode : « S1 · E3 · Titre ».
  final String? subtitle;
  final String url;
  final String? posterUrl;
  final String containerExt;
  final String sourceKey;
  final String remoteId;
  final String? seriesId;
  final int? season;
  final int? episode;
  final bool isAdult;
  final bool adultClassificationKnown;
  final CinemaClassification? classification;

  // Faible : aucune liste globale de médias n'est retenue. Après remplacement
  // du catalogue, seul un item encore détenu peut mémoriser sa preuve relue.
  static final Expando<CinemaClassification> _revalidated =
      Expando<CinemaClassification>();

  int? get playlistId => sourceKey.isNotEmpty
      ? int.tryParse(sourceKey.startsWith('p') ? sourceKey.substring(1) : '')
      : int.tryParse(RegExp(r'^p([1-9][0-9]*):[mes]:')
          .firstMatch(id)?.group(1) ?? '');

  CinemaClassification? get _currentClassification {
    final previous = _revalidated[this] ?? classification;
    final proof = CinemaRepository.instance.classificationForMedia(
        isEpisode ? (seriesId ?? id) : id,
        isEpisode ? CinemaKind.series : CinemaKind.movie,
        previous: previous);
    if (proof != null && !identical(previous, proof)) _revalidated[this] = proof;
    return proof;
  }

  CinemaClassification? get playbackClassification => _currentClassification;

  bool? get currentAdultStatus {
    if (isAdult || ChannelClassifier.isAdult(title, subtitle ?? '')) return true;
    final proof = _currentClassification;
    return proof != null ? proof.isAdult
        : (adultClassificationKnown ? false : null);
  }

  static bool get _zunoKids => AppPlatform.isZuno &&
      (ParentalControls.instance.kidsMode.value ||
       ProfileRepository.instance.activeIsKids);

  /// La sélection n'est pas un droit : une feuille peut rester ouverte
  /// pendant le remplacement du catalogue, sans changement de profil.
  bool isAllowedNow({AdultAccessGrant? adultAccess}) {
    if (!AppPlatform.isZuno) {
      return adultClassificationKnown &&
          (adultAccess == null ? !isAdult : adultAccess.isValid);
    }
    if (!ParentalControls.instance.protectsZuno ||
        !ParentalControls.instance.contentReady ||
        adultAccess?.isValid == false) {
      return false;
    }
    final source = playlistId;
    final structuredSource = int.tryParse(RegExp(r'^p([1-9][0-9]*):[mes]:')
        .firstMatch(id)?.group(1) ?? '');
    if ((sourceKey.isNotEmpty && (source == null || source <= 0)) ||
        (structuredSource != null && source != structuredSource) ||
        !ActiveProfile.instance.allowsPlaylist(source)) {
      return false;
    }
    final proof = _currentClassification;
    if (proof != null && proof.sourceKey != 'p$source') return false;
    final explicitAdult = isAdult ||
        ChannelClassifier.isAdult(title, subtitle ?? '');
    final status = proof != null ? proof.isAdult
        : CinemaRepository.instance.adultStatusForMedia(
            isEpisode ? (seriesId ?? id) : id, title);
    if (_zunoKids) return !explicitAdult && status == false;
    // Une ancienne reprise sans classement demeure fermée. Les factories
    // de films/séries conservent le comportement adulte du 116 ci-dessous.
    return adultClassificationKnown &&
        (adultAccess == null
            ? !explicitAdult && status != true
            : adultAccess.isValid);
  }

  factory VodPlayItem.movie(CinemaTitle t,
      {bool? isAdult, CinemaClassification? previousClassification}) {
    final status = CinemaRepository.instance.adultStatusForTitle(t);
    return VodPlayItem(
    id: t.id,
    isEpisode: false,
    title: t.name,
    url: t.streamUrl ?? '',
    posterUrl: t.posterUrl,
    containerExt: t.containerExt,
    sourceKey: t.sourceKey,
    remoteId: t.remoteId,
    isAdult: AppPlatform.isZuno ? (isAdult == true || status == true)
        : isAdult ?? CinemaRepository.instance.isAdultTitle(t),
    adultClassificationKnown: !AppPlatform.isZuno ||
        (ParentalControls.instance.contentReady && !_zunoKids) ||
        isAdult == true || status != null,
    classification: CinemaRepository.instance.classificationForMedia(t.id, t.kind,
        previous: previousClassification),
  );
  }

  /// La fiche d'une série doit protéger son titre avant de choisir un épisode.
  /// Cet objet porte seulement l'identité de la fiche, jamais une URL inventée.
  factory VodPlayItem.catalogueTitle(CinemaTitle title) {
    if (title.kind == CinemaKind.movie) return VodPlayItem.movie(title);
    return VodPlayItem(id: title.id, isEpisode: true, seriesId: title.id,
        title: title.name, url: '', sourceKey: title.sourceKey,
        isAdult: CinemaRepository.instance.isAdultTitle(title),
        classification: CinemaRepository.instance.classificationForMedia(
            title.id, CinemaKind.series));
  }

  factory VodPlayItem.episode(CinemaEpisode e, CinemaTitle series,
      {bool? isAdult, CinemaClassification? previousClassification}) {
    final status = CinemaRepository.instance.adultStatusForTitle(series);
    return VodPlayItem(
        id: e.id,
        isEpisode: true,
        title: series.name,
        subtitle: episodeLabel(e),
        url: e.streamUrl,
        posterUrl: e.stillUrl ?? series.posterUrl,
        containerExt: e.containerExt,
        sourceKey: series.sourceKey,
        remoteId: e.remoteId,
        seriesId: series.id,
        season: e.season,
        episode: e.number,
        isAdult: AppPlatform.isZuno ? (isAdult == true || status == true)
            : isAdult ?? CinemaRepository.instance.isAdultTitle(series),
        adultClassificationKnown: !AppPlatform.isZuno ||
            (ParentalControls.instance.contentReady && !_zunoKids) ||
            isAdult == true || status != null,
        classification: CinemaRepository.instance.classificationForMedia(
            series.id, CinemaKind.series, previous: previousClassification),
      );
  }

  factory VodPlayItem.entry(WatchEntry e) {
    final bool? adult = CinemaRepository.instance.adultStatusForWatch(e);
    return VodPlayItem(
    id: e.id,
    isEpisode: e.isEpisode,
    title: e.title,
    subtitle: e.subtitle,
    url: e.streamUrl,
    posterUrl: e.posterUrl,
    containerExt: e.containerExt,
    sourceKey: e.sourceKey,
    remoteId: e.remoteId,
    seriesId: e.seriesId,
    season: e.season,
    episode: e.episode,
    isAdult: adult == true,
    adultClassificationKnown: adult != null,
    classification: CinemaRepository.instance.classificationForMedia(
        e.isEpisode ? (e.seriesId ?? e.id) : e.id,
        e.isEpisode ? CinemaKind.series : CinemaKind.movie),
  );
  }

  /// Les anciens téléchargements ne portent aucun classement persistant.
  /// La preuve provient uniquement du catalogue réellement chargé maintenant.
  factory VodPlayItem.download(Download download, {required bool isAdult}) {
    final episode = download.id.contains(':e:');
    final proof = CinemaRepository.instance.classificationForMedia(
        download.id, episode ? CinemaKind.series : CinemaKind.movie);
    return VodPlayItem(id: download.id, isEpisode: episode,
        title: download.name, url: download.sourceUrl,
        posterUrl: download.posterUrl, isAdult: isAdult,
        adultClassificationKnown: !AppPlatform.isZuno ||
            (ParentalControls.instance.contentReady && !_zunoKids) ||
            isAdult || proof != null,
        classification: proof);
  }

  WatchEntry toEntry({required int posMs, required int durMs}) => WatchEntry(
    id: id,
    isEpisode: isEpisode,
    title: title,
    subtitle: subtitle,
    posterUrl: posterUrl,
    streamUrl: url,
    containerExt: containerExt,
    sourceKey: sourceKey,
    remoteId: remoteId,
    seriesId: seriesId,
    season: season,
    episode: episode,
    isAdult: isAdult,
    adultClassificationKnown: adultClassificationKnown,
    posMs: posMs,
    durMs: durMs,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  );

  /// Pour le moteur de téléchargement (un épisode se télécharge comme un film).
  VodMovie toVodMovie() => VodMovie(
    id: id,
    name: subtitle == null ? title : '$title · $subtitle',
    category: isEpisode ? 'series' : 'movie',
    streamUrl: url,
    containerExt: containerExt,
    posterUrl: posterUrl,
  );
}

/// « S1 · E3 · Titre » (ou « S1 · E3 » si l'épisode n'a pas de titre propre).
String episodeLabel(CinemaEpisode e) {
  final String code = 'S${e.season} · E${e.number}';
  return e.title.isEmpty ? code : '$code · ${e.title}';
}

/// Fichier local du téléchargement TERMINÉ de [id] (null sinon).
Future<String?> offlinePathFor(String id) async {
  await DownloadsRepository.instance.initialize();
  final Download? d = DownloadsRepository.instance.byId(id);
  if (d == null || !d.isDone) return null;
  try {
    if (await File(d.filePath).exists()) return d.filePath;
  } catch (_) {}
  return null;
}

/// Ouvre le lecteur. [fromStart] ignore la reprise. [series] + [seriesTitle]
/// permettent l'enchaînement automatique des épisodes.
Future<void> openVod(
  BuildContext context,
  VodPlayItem item, {
  bool fromStart = false,
  SeriesDetails? series,
  CinemaTitle? seriesTitle,
  AdultAccessGrant? adultAccess,
}) async {
  final int scope = ActiveProfile.instance.scopeListenable.value;
  final int generation = ParentalControls.instance.contentGeneration;
  bool allowed() => context.mounted &&
      (!AppPlatform.isZuno || (ParentalControls.instance.contentReady &&
        generation == ParentalControls.instance.contentGeneration)) &&
      scope == ActiveProfile.instance.scopeListenable.value &&
      (item.sourceKey.isEmpty || ActiveProfile.instance.allowsPlaylist(int.tryParse(
        item.sourceKey.startsWith('p') ? item.sourceKey.substring(1) : '',
      ))) && item.isAllowedNow(adultAccess: adultAccess);
  if (!allowed()) return;
  await WatchProgressRepository.instance.load();
  if (!allowed()) return;
  final WatchEntry? prev = WatchProgressRepository.instance.get(item.id);
  // Même règle pour la rangée « Reprendre », la fiche, et « Depuis le début ».
  final Duration startAt = ResumeStart.decide(
    entry: prev,
    fromStart: fromStart,
  ).at;
  final String? local = await offlinePathFor(item.id);
  if (!allowed()) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AppPlatform.isZuno && !allowed()
          ? const SizedBox.shrink() : TvVodPlayerScreen(
        item: item,
        startAt: startAt,
        localPath: local,
        series: series,
        seriesTitle: seriesTitle,
        adultAccess: adultAccess,
      ),
    ),
  );
}

// =========================================================
//  Préférences audio / sous-titres (retenues d'un film à l'autre)
// =========================================================

abstract final class CinemaTrackPrefs {
  static const String _kAudio = 'cinema.pref.audio';
  static const String _kText = 'cinema.pref.text';

  /// Langue audio choisie par l'utilisateur (null = langue de l'app).
  static Future<String?> audio() async =>
      (await SharedPreferences.getInstance()).getString(_kAudio);

  /// Langue de sous-titres (null = aucun choix, 'off' = désactivés).
  static Future<String?> text() async =>
      (await SharedPreferences.getInstance()).getString(_kText);

  static Future<void> setAudio(String? lang) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    if (lang == null || lang.isEmpty) {
      await p.remove(_kAudio);
    } else {
      await p.setString(_kAudio, lang);
    }
  }

  static Future<void> setText(String? lang) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setString(_kText, (lang == null || lang.isEmpty) ? 'off' : lang);
  }
}

// =========================================================
//  Formatage
// =========================================================

/// 1:02:05 / 42:10.
String formatClock(Duration d) {
  final int h = d.inHours;
  final int m = d.inMinutes.remainder(60);
  final int s = d.inSeconds.remainder(60);
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

// =========================================================
//  Widgets communs
// =========================================================

/// Pilule d'action (même rendu que les actions du Direct).
class CinemaPill extends StatelessWidget {
  const CinemaPill({
    super.key,
    required this.icon,
    required this.label,
    required this.onSelect,
    this.autofocus = false,
    this.focusNode,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onSelect;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      focusNode: focusNode,
      scale: TvFocusScale.large,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused
            ? TvAppTokens.of(context).onAccent
            : TvAppTokens.of(context).accentBright;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          decoration: BoxDecoration(
            color: focused
                ? TvAppTokens.of(context).accent
                : TvAppTokens.of(context).sel,
            borderRadius: BorderRadius.circular(TvTokens.rButton),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 9),
              Text(
                label,
                style: TextStyle(
                  fontSize: TvDimens.titleS,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Ligne de la colonne de gauche (même rendu que les catégories du Direct).
class CinemaRailRow extends StatelessWidget {
  const CinemaRailRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelect,
    this.onFocused,
    this.icon,
    this.count,
    this.autofocus = false,
  });
  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onFocused;
  final IconData? icon;
  final int? count;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: TvFocusBuilder(
        autofocus: autofocus,
        scale: TvFocusScale.small,
        onSelect: onSelect,
        builder: (BuildContext context, bool focused) {
          if (focused) onFocused?.call();
          final bool active = selected && !focused;
          final Color bg = (focused || active)
              ? TvAppTokens.of(context).sel
              : Colors.transparent;
          final Color fg = focused
              ? TvAppTokens.of(context).accentBright
              : (active
                    ? TvAppTokens.of(context).text
                    : TvAppTokens.of(context).muted);
          return Container(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(TvTokens.rMenuItem),
              border: focused
                  ? Border.all(
                      color: TvAppTokens.of(context).accent,
                      width: TvDimens.focusOutline,
                    )
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 20, color: fg),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TvAppTokens.of(context).ui(
                      TvDimens.body,
                      weight: (focused || active)
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ),
                if (count != null) ...<Widget>[
                  const SizedBox(width: 10),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: TvDimens.label,
                      fontWeight: FontWeight.w700,
                      color: focused
                          ? TvAppTokens.of(context).accentBright
                          : TvAppTokens.of(context).mutedDim,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Affiche 2:3 + titre, barre de progression (or) et pastille « téléchargé ».
class CinemaPoster extends StatelessWidget {
  const CinemaPoster({
    super.key,
    required this.title,
    required this.onSelect,
    this.posterUrl,
    this.caption,
    this.progress,
    this.downloaded = false,
    this.locked = false,
    this.onFocused,
    this.autofocus = false,
  });

  final String title;
  final String? posterUrl;

  /// 2e ligne discrète (« S1 · E3 », année…).
  final String? caption;

  /// 0..1 → barre de reprise ; null = rien.
  final double? progress;
  final bool downloaded;
  final bool locked;
  final VoidCallback onSelect;
  final VoidCallback? onFocused;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        if (focused) onFocused?.call();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: TvAppTokens.of(context).tile,
                  borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                  border: Border.all(
                    color: focused
                        ? TvAppTokens.of(context).accent
                        : TvAppTokens.of(context).tileBorder,
                    width: focused ? TvDimens.focusOutline : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    _PosterImage(url: posterUrl, title: title),
                    if (locked)
                      ColoredBox(
                        color: Colors.black.withValues(alpha: 0.7),
                        child: Center(
                          child: Icon(
                            Icons.lock_rounded,
                            color: TvAppTokens.of(context).accentBright,
                            size: 34,
                          ),
                        ),
                      ),
                    if (downloaded)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: TvAppTokens.of(context).accent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.download_done_rounded,
                            size: 16,
                            color: TvAppTokens.of(context).onAccent,
                          ),
                        ),
                      ),
                    if (progress != null && progress! > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          height: 5,
                          color: Colors.black.withValues(alpha: 0.6),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: progress!.clamp(0.0, 1.0),
                            child: Container(
                              color: TvAppTokens.of(context).accent,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TvAppTokens.of(context).ui(
                TvDimens.caption,
                weight: FontWeight.w700,
                color: focused
                    ? TvAppTokens.of(context).accentBright
                    : TvAppTokens.of(context).text,
              ),
            ),
            Text(
              caption ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TvAppTokens.of(context).ui(
                TvDimens.caption,
                color: TvAppTokens.of(context).mutedDim,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PosterImage extends StatelessWidget {
  const _PosterImage({required this.url, required this.title});
  final String? url;
  final String title;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Center(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: TvAppTokens.of(context)
              .display(18, color: TvAppTokens.of(context).muted),
        ),
      ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      // Affiche ~132 px affichée : 220 px décodés suffisent (mémoire box).
      memCacheWidth: 220,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, __) => fallback,
      errorWidget: (_, __, ___) => fallback,
    );
  }
}

/// Petit bandeau de chargement sobre (texte + indicateur or).
class CinemaLoading extends StatelessWidget {
  const CinemaLoading({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: TvAppTokens.of(context).accent,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            label ?? context.l10n.tvCinemaLoading,
            style: TextStyle(
              fontSize: TvDimens.body,
              color: TvAppTokens.of(context).mutedDim,
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================
//  Petit menu d'actions (fiche téléchargement, suppression…)
// =========================================================

@immutable
class CinemaSheetAction {
  const CinemaSheetAction(this.icon, this.label, this.run);
  final IconData icon;
  final String label;
  final FutureOr<void> Function() run;
}

/// Menu centré, navigable à la télécommande (1re action focalisée, Retour =
/// fermer sans rien faire).
Future<void> showCinemaSheet(
  BuildContext context, {
  required String title,
  required List<CinemaSheetAction> actions,
  bool Function()? isAllowed,
  Listenable? permissionChanges,
}) async {
  bool allowed() => !AppPlatform.isZuno || isAllowed?.call() != false;
  if (!allowed()) return;
  final CinemaSheetAction? chosen = await Navigator.of(context)
      .push<CinemaSheetAction>(
        PageRouteBuilder<CinemaSheetAction>(
          opaque: false,
          barrierDismissible: true,
          barrierColor: Colors.black.withValues(alpha: 0.6),
          pageBuilder: (BuildContext ctx, _, __) {
            final Widget sheet = Material(
            type: MaterialType.transparency,
            child: Center(
              child: Container(
                width: 460,
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(
                  color: TvAppTokens.of(context).surface3,
                  borderRadius: BorderRadius.circular(TvTokens.rCard),
                  border: Border.all(color: TvAppTokens.of(context).line),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TvAppTokens.of(context)
                          .display(26, color: TvAppTokens.of(context).text),
                    ),
                    const SizedBox(height: 18),
                    for (int i = 0; i < actions.length; i++) ...<Widget>[
                      CinemaPill(
                        icon: actions[i].icon,
                        label: actions[i].label,
                        autofocus: i == 0,
                        onSelect: () => Navigator.of(ctx).pop(actions[i]),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ),
            );
            return AppPlatform.isZuno && isAllowed != null
                ? _CinemaSheetProtection(isAllowed: isAllowed,
                    permissionChanges: permissionChanges, child: sheet)
                : sheet;
          },
        ),
      );
  if (chosen != null && allowed()) await chosen.run();
}

/// Une feuille déjà ouverte ne garde ni titre ni actions d'un média révoqué.
/// La fermeture vise sa propre route ; elle ne dépile jamais une autre page.
class _CinemaSheetProtection extends StatefulWidget {
  const _CinemaSheetProtection({required this.isAllowed, required this.child,
      this.permissionChanges});
  final bool Function() isAllowed;
  final Widget child;
  final Listenable? permissionChanges;

  @override
  State<_CinemaSheetProtection> createState() => _CinemaSheetProtectionState();
}

class _CinemaSheetProtectionState extends State<_CinemaSheetProtection> {
  late final Listenable _changes = Listenable.merge(<Listenable?>[
    CinemaRepository.instance.classificationVersion,
    ActiveProfile.instance.scopeListenable,
    ParentalControls.instance.readiness,
    ParentalControls.instance.kidsMode,
    widget.permissionChanges,
  ]);
  bool _revoked = false;

  @override
  void initState() {
    super.initState();
    _changes.addListener(_changed);
    if (!widget.isAllowed()) _close();
  }

  void _changed() {
    if (!mounted || _revoked) return;
    if (!widget.isAllowed()) {
      setState(_close);
    }
  }

  void _close() {
    if (_revoked) return;
    _revoked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive && !route.isFirst) {
        Navigator.of(context).removeRoute(route);
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      _revoked || !widget.isAllowed() ? const SizedBox.shrink() : widget.child;

  @override
  void dispose() {
    _changes.removeListener(_changed);
    super.dispose();
  }
}
