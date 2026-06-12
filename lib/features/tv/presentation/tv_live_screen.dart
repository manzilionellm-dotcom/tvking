// =========================================================
//  tv_live_screen.dart — Écran DIRECT (Live TV) 10-foot
// =========================================================
//  Gauche : catégories focusables (le focus met à jour la grille, façon
//  TiviMate). Droite : grille de chaînes virtualisée (logo + nom + n°),
//  focusable. OK sur une chaîne → lecteur plein écran.
//
//  Source = celle poussée par TON panel (PlaylistRepository, alimenté par
//  RemoteSourceRepository). États vides PROFESSIONNELS (pas d'écran mort).
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../core/tv_tokens.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../channels/domain/channel.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/remote_source_repository.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import 'tv_components.dart';
import 'tv_player_screen.dart';

class TvLiveScreen extends StatefulWidget {
  const TvLiveScreen({super.key});

  @override
  State<TvLiveScreen> createState() => _TvLiveScreenState();
}

class _TvLiveScreenState extends State<TvLiveScreen> {
  StreamSubscription<List<Channel>>? _sub;
  List<Channel> _all = const <Channel>[];
  List<String> _cats = const <String>[];
  String? _selectedCat;
  bool _heroShown = false;

  // Re-synchro de la source poussée par le panel. CRUCIAL : sans ça, l'app
  // ne récupérait la source qu'au tout 1er démarrage ; si le revendeur
  // activait/poussait APRÈS, la TV restait « Aucune chaîne » jusqu'au
  // redémarrage. Ici on re-tente tant qu'on n'a aucune chaîne.
  Timer? _syncTimer;
  bool _syncing = false;
  RemoteSyncResult? _lastSync;

  @override
  void initState() {
    super.initState();
    _ingest(PlaylistRepository.instance.currentChannels);
    _sub = PlaylistRepository.instance.channelsStream.listen(_ingest);
    _kickSourceSync(); // tout de suite à l'ouverture de l'écran
    _syncTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (_all.isEmpty) _kickSourceSync();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _kickSourceSync() async {
    if (_syncing) return;
    if (mounted) setState(() => _syncing = true);
    final RemoteSyncResult r = await RemoteSourceRepository.sync();
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _lastSync = r;
    });
  }

  // Catégorie EXACTEMENT comme écrite dans la source (M3U group-title /
  // Xtream category_name). On ne reclasse PAS : on respecte l'ordre et les
  // noms du créateur de la playlist.
  static String _catOf(Channel c) {
    final String raw = c.category.trim();
    return raw.isEmpty ? 'Autres' : raw;
  }

  void _ingest(List<Channel> channels) {
    final List<Channel> live =
        channels.where((Channel c) => c.isLive).toList(growable: false);
    // Ordre des catégories = ordre d'APPARITION dans la source (1re vue).
    final List<String> cats = <String>[];
    for (final Channel c in live) {
      final String cat = _catOf(c);
      if (!cats.contains(cat)) cats.add(cat);
    }
    if (!mounted) return;
    setState(() {
      _all = live;
      _cats = cats;
      _selectedCat ??= cats.isNotEmpty ? cats.first : null;
      if (_selectedCat != null && !cats.contains(_selectedCat)) {
        _selectedCat = cats.isNotEmpty ? cats.first : null;
      }
    });
  }

  List<Channel> get _shown => _selectedCat == null
      ? _all
      : _all
          .where((Channel c) => _catOf(c) == _selectedCat)
          .toList(growable: false);

  // Dernière chaîne regardée (1er id de l'historique présent dans la
  // playlist courante) → « Continuer à regarder ».
  Channel? _lastWatched() {
    for (final String id in RecentlyWatchedRepository.instance.current) {
      for (final Channel c in _all) {
        if (c.id == id) return c;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_all.isEmpty) {
      // États PRÉCIS au lieu d'un « écran mort » :
      //  • en cours / réseau → « Recherche de tes chaînes… »
      //  • source refusée     → identifiants invalides côté panel
      //  • rien d'assigné     → message d'activation habituel
      final bool searching = _syncing ||
          _lastSync == null ||
          _lastSync == RemoteSyncResult.networkError;
      final String title;
      final String subtitle;
      if (searching) {
        title = context.l10n.tvSearchingChannels;
        subtitle = context.l10n.tvNoChannelsHelp;
      } else if (_lastSync == RemoteSyncResult.sourceFailed) {
        title = context.l10n.tvNoChannels;
        subtitle = context.l10n.tvSourceInvalid;
      } else {
        title = context.l10n.tvNoChannels;
        subtitle = context.l10n.tvNoChannelsHelp;
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(searching ? Icons.wifi_find_rounded : Icons.live_tv_rounded,
                size: 64, color: TvTokens.mutedDim),
            const SizedBox(height: 16),
            Text(title,
                style: TextStyle(
                    fontSize: TvDimens.headline,
                    fontWeight: FontWeight.w700,
                    color: TvTokens.text)),
            const SizedBox(height: 10),
            SizedBox(
              width: 600,
              child: Text(subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: TvDimens.body, color: TvTokens.mutedDim)),
            ),
            const SizedBox(height: 22),
            // Bouton « Réessayer maintenant » (focusable D-pad).
            TvFocusBuilder(
              autofocus: true,
              scale: TvFocusScale.large,
              onSelect: _syncing ? null : _kickSourceSync,
              builder: (BuildContext context, bool focused) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: focused ? TvTokens.gold : TvTokens.sel,
                  borderRadius: BorderRadius.circular(TvTokens.rButton),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.refresh_rounded,
                        size: 22,
                        color: focused ? const Color(0xFF1A1206) : TvTokens.goldBright),
                    const SizedBox(width: 10),
                    Text(
                        _syncing
                            ? context.l10n.tvSearchingChannels
                            : context.l10n.tvRetry,
                        style: TextStyle(
                            fontSize: TvDimens.title,
                            fontWeight: FontWeight.w700,
                            color: focused ? const Color(0xFF1A1206) : TvTokens.goldBright)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final Channel? last = _lastWatched();
    _heroShown = last != null;

    final Widget body = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ----- Catégories -----
        SizedBox(
          width: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Text(context.l10n.tvNavLive,
                    style: TextStyle(
                        fontSize: TvDimens.displayS,
                        fontWeight: FontWeight.w800,
                        color: TvTokens.text)),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _cats.length,
                  itemBuilder: (BuildContext context, int i) {
                    final String cat = _cats[i];
                    final bool sel = cat == _selectedCat;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: TvFocusBuilder(
                        autofocus: i == 0 && !_heroShown,
                        scale: TvFocusScale.large,
                        onSelect: () => setState(() => _selectedCat = cat),
                        builder: (BuildContext context, bool focused) {
                          // Le focus met à jour la grille (preview live).
                          if (focused && _selectedCat != cat) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) setState(() => _selectedCat = cat);
                            });
                          }
                          // Maison Noir : fond `--sel` + texte or au focus/
                          // actif. JAMAIS de bloc blanc plein (interdit #4).
                          final bool hl = focused || sel;
                          final Color bg = hl ? TvTokens.sel : Colors.transparent;
                          final Color fg = hl ? TvTokens.goldBright : TvTokens.muted;
                          return Container(
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius:
                                  BorderRadius.circular(TvDimens.cardRadius),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Text(
                              cat,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: TvDimens.titleS,
                                  fontWeight: FontWeight.w600,
                                  color: fg),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: TvDimens.gutter),
        // ----- Grille de chaînes (virtualisée) -----
        Expanded(child: _ChannelGrid(channels: _shown)),
      ],
    );

    if (last == null) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ContinueHero(
          channel: last,
          all: _all,
          index: _all.indexOf(last),
        ),
        const SizedBox(height: 16),
        Expanded(child: body),
      ],
    );
  }
}

/// Bandeau « Continuer à regarder » (dernière chaîne), auto-focus.
class _ContinueHero extends StatelessWidget {
  const _ContinueHero(
      {required this.channel, required this.all, required this.index});
  final Channel channel;
  final List<Channel> all;
  final int index;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: true,
      scale: TvFocusScale.large,
      baseColor: TvTokens.card,
      onSelect: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TvPlayerScreen(
              channels: all, startIndex: index < 0 ? 0 : index),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: <Widget>[
            const Icon(Icons.play_circle_fill_rounded,
                color: TvTokens.text, size: 40),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(context.l10n.tvContinueWatching,
                    style: TextStyle(
                        fontSize: TvDimens.caption,
                        letterSpacing: 2,
                        color: TvTokens.mutedDim)),
                const SizedBox(height: 2),
                Text(channel.cleanName,
                    style: TextStyle(
                        fontSize: TvDimens.title,
                        fontWeight: FontWeight.w800,
                        color: TvTokens.text)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelGrid extends StatelessWidget {
  const _ChannelGrid({required this.channels});
  final List<Channel> channels;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return Center(
        child: Text(context.l10n.tvNoChannelInCategory,
            style: TextStyle(
                fontSize: TvDimens.body, color: TvTokens.mutedDim)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 230,
        mainAxisExtent: 132,
        crossAxisSpacing: TvDimens.gutter,
        mainAxisSpacing: TvDimens.gutter,
      ),
      itemCount: channels.length,
      itemBuilder: (BuildContext context, int i) =>
          _ChannelCard(channel: channels[i], all: channels, index: i),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard(
      {required this.channel, required this.all, required this.index});
  final Channel channel;
  final List<Channel> all;
  final int index;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      scale: TvFocusScale.small,
      onSelect: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                TvPlayerScreen(channels: all, startIndex: index),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Expanded(child: _Logo(channel: channel)),
            const SizedBox(height: 8),
            Text(
              channel.cleanName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: TvDimens.caption,
                  fontWeight: FontWeight.w600,
                  color: TvTokens.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.channel});
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
    if (url == null || url.isEmpty) return fallback;
    return Image.network(
      url,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => fallback,
      // Décodage hors-UI + petite taille mémoire (perf §10).
      cacheWidth: 200,
    );
  }
}

class _EmptyChannels extends StatelessWidget {
  const _EmptyChannels();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.live_tv_rounded,
              size: 72, color: TvTokens.mutedDim),
          const SizedBox(height: 16),
          Text('Aucune chaîne pour l\'instant',
              style: TextStyle(
                  fontSize: TvDimens.headline,
                  fontWeight: FontWeight.w700,
                  color: TvTokens.text)),
          const SizedBox(height: 10),
          SizedBox(
            width: 560,
            child: Text(
              'Active cet appareil dans ton panel et pousse-lui une source. '
              'Les chaînes apparaîtront ici automatiquement.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: TvDimens.body, color: TvTokens.mutedDim),
            ),
          ),
        ],
      ),
    );
  }
}
