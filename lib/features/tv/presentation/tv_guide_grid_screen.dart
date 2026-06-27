// =========================================================
//  tv_guide_grid_screen.dart — Guide EPG « Maintenant / À suivre » (TV)
// =========================================================
//  Onglet GUIDE : la liste des chaînes avec, pour chacune, l'émission EN COURS
//  (titre + barre de progression + horaire) et CELLE D'APRÈS. C'est la vue
//  « qu'est-ce qui passe maintenant » façon TiviMate, à parcourir au D-pad.
//
//  ANTI-OOM (façon TiviMate) : les chaînes sont lues par PAGES depuis SQLite
//  (jamais toute la liste en RAM) ; l'EPG de chaque ligne est chargé À LA
//  DEMANDE quand la ligne apparaît, et libéré quand elle sort de l'écran.
//
//  OK sur une chaîne → lecteur plein écran (ExoPlayer).
//  Appui LONG → favori (même raccourci que le Direct).
// =========================================================
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../channels/domain/channel.dart';
import '../../epg/data/epg_repository.dart';
import '../../epg/domain/epg_program.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_player_screen.dart';

class TvGuideGridScreen extends StatefulWidget {
  const TvGuideGridScreen({super.key});

  @override
  State<TvGuideGridScreen> createState() => _TvGuideGridScreenState();
}

class _TvGuideGridScreenState extends State<TvGuideGridScreen> {
  // Chaînes chargées par PAGES (pagination keyset SQLite). Seules les pages
  // déjà défilées vivent en RAM.
  final List<Channel> _channels = <Channel>[];
  int _cursor = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _ready = false;
  StreamSubscription<List<Channel>>? _sub;

  static const int _kPageSize = 120;

  @override
  void initState() {
    super.initState();
    _loadMore();
    // Si la source se (re)synchronise alors que le guide est vide, on relance
    // un 1er chargement (signal uniquement — on n'absorbe pas la liste).
    _sub = PlaylistRepository.instance.channelsStream.listen((_) {
      if (mounted && _channels.isEmpty) _reload();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    _cursor = 0;
    _hasMore = true;
    _channels.clear();
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    _loading = true;
    try {
      final page = await PlaylistRepository.instance
          .getChannelsPage(afterLocalId: _cursor, limit: _kPageSize);
      if (!mounted) return;
      setState(() {
        _channels.addAll(page.channels);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _ready = true;
      });
    } finally {
      _loading = false;
    }
  }

  void _play(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvPlayerScreen(channels: _channels, startIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_channels.isEmpty) {
      return Center(
        child: Text(context.l10n.tvNoChannels,
            style: TvTokens.ui(18, color: TvTokens.mutedDim)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Text(context.l10n.tvNavGuide.toUpperCase(),
              style: TvTokens.ui(13,
                  weight: FontWeight.w800,
                  color: TvTokens.mutedDim,
                  spacing: 2)),
        ),
        Expanded(
          child: ListView.separated(
            // Mémoire bornée : on ne garde pas les lignes (ni leur EPG) hors écran.
            addAutomaticKeepAlives: false,
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: _channels.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int i) {
              // Pagination : on charge la page suivante à l'approche du bas.
              if (i >= _channels.length - 12) _loadMore();
              return _GuideRow(
                key: ValueKey<String>(_channels[i].id),
                channel: _channels[i],
                onPlay: () => _play(i),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Une ligne du guide : logo + nom + (émission EN COURS avec progression) +
/// (à suivre). L'EPG est chargé À LA DEMANDE pour CETTE chaîne.
class _GuideRow extends StatefulWidget {
  const _GuideRow({required this.channel, required this.onPlay, super.key});

  final Channel channel;
  final VoidCallback onPlay;

  @override
  State<_GuideRow> createState() => _GuideRowState();
}

class _GuideRowState extends State<_GuideRow> {
  late Future<List<EpgProgram?>> _epg;

  @override
  void initState() {
    super.initState();
    _epg = _load();
  }

  // On charge EN PARALLÈLE l'émission en cours et la suivante (2 requêtes
  // indexées légères). Retour : [maintenant, ensuite] (chacune peut être null).
  Future<List<EpgProgram?>> _load() async {
    final EpgRepository epg = EpgRepository.instance;
    final List<EpgProgram?> res = await Future.wait(<Future<EpgProgram?>>[
      epg.currentProgram(widget.channel.id),
      epg.nextProgram(widget.channel.id),
    ]);
    return res;
  }

  void _toggleFavorite() {
    FavoritesRepository.instance.toggle(widget.channel.id);
    HapticFeedback.selectionClick();
    if (mounted) setState(() {}); // rafraîchit le cœur immédiatement
  }

  @override
  Widget build(BuildContext context) {
    final Channel c = widget.channel;
    final bool fav = FavoritesRepository.instance.isFavorite(c.id);
    return TvFocusable(
      scale: TvFocusScale.small,
      baseColor: TvTokens.card,
      onSelect: widget.onPlay,
      onLongPress: _toggleFavorite,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            // ----- Logo -----
            _GuideLogo(channel: c),
            const SizedBox(width: 14),
            // ----- Nom + cœur favori -----
            SizedBox(
              width: 240,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      c.cleanName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: TvDimens.title,
                          fontWeight: FontWeight.w700,
                          color: TvTokens.text),
                    ),
                  ),
                  if (fav)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.favorite_rounded,
                          size: 16, color: TvTokens.gold),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            // ----- EPG maintenant / à suivre -----
            Expanded(
              child: FutureBuilder<List<EpgProgram?>>(
                future: _epg,
                builder: (BuildContext context,
                    AsyncSnapshot<List<EpgProgram?>> snap) {
                  final EpgProgram? now =
                      (snap.data != null && snap.data!.isNotEmpty)
                          ? snap.data![0]
                          : null;
                  final EpgProgram? next =
                      (snap.data != null && snap.data!.length > 1)
                          ? snap.data![1]
                          : null;
                  if (now == null && next == null) {
                    // Pas d'EPG pour cette chaîne → on reste discret.
                    return Text(
                      c.category.trim().isEmpty ? '' : c.category.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: TvDimens.label, color: TvTokens.mutedDim),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (now != null) _NowLine(program: now),
                      if (next != null) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          'À suivre · ${next.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: TvDimens.label,
                              color: TvTokens.mutedDim),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ligne « EN COURS » : titre + barre de progression + horaire.
class _NowLine extends StatelessWidget {
  const _NowLine({required this.program});
  final EpgProgram program;

  @override
  Widget build(BuildContext context) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int span = program.stopTime - program.startTime;
    final double prog =
        span > 0 ? ((now - program.startTime) / span).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          program.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: TvDimens.body,
              fontWeight: FontWeight.w600,
              color: TvTokens.text),
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 4,
                  child: LinearProgressIndicator(
                    value: prog,
                    backgroundColor: TvTokens.line,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(TvTokens.gold),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(program.timeRangeShort,
                style: TextStyle(
                    fontSize: TvDimens.label, color: TvTokens.mutedDim)),
          ],
        ),
      ],
    );
  }
}

/// Logo de chaîne normalisé (contain + repli initiales).
class _GuideLogo extends StatelessWidget {
  const _GuideLogo({required this.channel});
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Center(
      child: Text(channel.initials,
          style: TextStyle(
              fontSize: TvDimens.title,
              fontWeight: FontWeight.w800,
              color: TvTokens.muted)),
    );
    final String? url = channel.logoUrl;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xD9141210),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TvTokens.line),
      ),
      padding: const EdgeInsets.all(8),
      child: (url == null || url.isEmpty)
          ? fallback
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              memCacheWidth: 160,
              memCacheHeight: 160,
              placeholder: (_, __) => Opacity(opacity: 0.35, child: fallback),
              errorWidget: (_, __, ___) => fallback,
            ),
    );
  }
}
