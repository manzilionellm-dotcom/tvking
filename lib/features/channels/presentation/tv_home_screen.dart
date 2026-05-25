// =========================================================
//  tv_home_screen.dart — Accueil version Télévision (Android TV /
//  Fire TV / Google TV)
// =========================================================
//  Layout XL conçu pour le 10-foot UI :
//    - Tailles 1.5× du mode téléphone
//    - Focus rings ember bien visibles à 3 m
//    - D-pad : flèches haut/bas naviguent entre rangées, gauche/
//      droite entre cartes, OK lance la chaîne
//    - Header transparent qui s'estompe au scroll
//    - Cast button + Search + Settings dans la rangée du haut,
//      tous accessibles à la télécommande
//
//  Le contenu (chaînes, sections) est identique au mode téléphone
//  pour ne pas avoir deux sources de vérité. On réutilise les
//  mêmes repositories. Seul le LAYOUT change.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/branding/brand_logo.dart';
import '../../../core/support/vip_help_card.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../cast/presentation/cast_button.dart';
import '../../cast/presentation/cast_mini_bar.dart';
import '../../epg/presentation/tv_guide_screen.dart';
import '../../player/presentation/play_channel.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/presentation/add_playlist_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../data/recently_watched_repository.dart';
import '../domain/channel.dart';
import '../domain/channel_genre.dart';
import 'category_section_screen.dart';
import 'favorites_screen.dart';
import 'search_screen.dart';
import 'widgets/channel_logo.dart';
import 'widgets/empty_state.dart';
import 'widgets/resume_banner.dart';

class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  /// Premier focus reçu = bouton "Regarder" du héros, pour que la
  /// télécommande tape immédiatement OK et que ça lance la chaîne
  /// la plus en avant.
  final FocusNode _initialFocus = FocusNode(debugLabel: 'hero-watch');

  @override
  void dispose() {
    _initialFocus.dispose();
    super.dispose();
  }

  List<Channel> _zapList() => PlaylistRepository.instance.currentChannels;

  void _onChannelTap(Channel ch) =>
      playChannel(context, ch, zapPlaylist: _zapList());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: <Widget>[
          // Fond avec gradient subtil
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppColors.backgroundGradient,
            ),
            child: SizedBox.expand(),
          ),

          // Contenu principal
          SafeArea(
            child: StreamBuilder<List<Channel>>(
              stream: PlaylistRepository.instance.channelsStream,
              initialData: PlaylistRepository.instance.currentChannels,
              builder: (BuildContext context,
                  AsyncSnapshot<List<Channel>> snap) {
                final List<Channel> channels = snap.data ?? <Channel>[];
                if (channels.isEmpty) {
                  return EmptyStateView(
                    onAddPlaylist: () =>
                        Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const AddPlaylistScreen(),
                      ),
                    ),
                  );
                }
                return _buildContent(channels);
              },
            ),
          ),

          // Mini-bar de cast — toujours flottante en haut
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 24,
            right: 24,
            child: const CastMiniBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(List<Channel> all) {
    // Pré-calculs (même logique que home_screen.dart)
    final Map<String, Channel> byId = <String, Channel>{};
    final List<Channel> sports = <Channel>[];
    final List<Channel> movies = <Channel>[];
    final List<Channel> series = <Channel>[];
    final List<Channel> live = <Channel>[];

    for (final Channel c in all) {
      byId[c.id] = c;
      if (c.isLive) live.add(c);
      switch (c.genre) {
        case ChannelGenre.sports:
          sports.add(c);
        case ChannelGenre.movies:
          movies.add(c);
        case ChannelGenre.series:
          series.add(c);
        case ChannelGenre.kids:
        case ChannelGenre.news:
        case ChannelGenre.music:
        case ChannelGenre.documentary:
        case ChannelGenre.entertainment:
        case ChannelGenre.international:
        case ChannelGenre.adult:
        case ChannelGenre.other:
          break;
      }
    }

    final Channel hero =
        all.firstWhere((Channel c) => c.hasLogo, orElse: () => all.first);

    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 32),
        children: <Widget>[
          // ----- Top bar avec brand + actions -----
          _TvTopBar(
            onSearch: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
            ),
            onGuide: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const TvGuideScreen()),
            ),
            onSettings: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),

          const SizedBox(height: 16),

          // ----- Bannière "Reprendre où tu t'es arrêté" -----
          //  Hook Model — Continue Watching. Visible si < 60 min.
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 48),
            child: ResumeBanner(),
          ),

          const SizedBox(height: 16),

          // ----- Hero XL -----
          _TvHero(
            channel: hero,
            watchFocus: _initialFocus,
            onWatch: () => _onChannelTap(hero),
          ),

          const SizedBox(height: 36),

          // ----- Reprendre -----
          StreamBuilder<List<String>>(
            stream: RecentlyWatchedRepository.instance.stream,
            initialData: RecentlyWatchedRepository.instance.current,
            builder: (BuildContext context, AsyncSnapshot<List<String>> s) {
              final List<Channel> recent = <Channel>[];
              for (final String id in s.data ?? <String>[]) {
                final Channel? c = byId[id];
                if (c != null) recent.add(c);
              }
              if (recent.isEmpty) return const SizedBox.shrink();
              return _TvRow(
                title: 'Reprendre',
                channels: recent,
                onTap: _onChannelTap,
              );
            },
          ),

          // ----- Favoris -----
          StreamBuilder<Set<String>>(
            stream: FavoritesRepository.instance.favoritesStream,
            initialData: FavoritesRepository.instance.current,
            builder: (BuildContext context, AsyncSnapshot<Set<String>> s) {
              final List<Channel> favs = <Channel>[];
              for (final String id in s.data ?? <String>{}) {
                final Channel? c = byId[id];
                if (c != null) favs.add(c);
              }
              if (favs.isEmpty) return const SizedBox.shrink();
              return _TvRow(
                title: 'Favoris',
                channels: favs,
                onTap: _onChannelTap,
                onSeeAll: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const FavoritesScreen(),
                  ),
                ),
              );
            },
          ),

          if (sports.isNotEmpty)
            _TvRow(
              title: 'Sports en direct',
              subtitle: '${sports.length} chaînes',
              channels: sports.take(20).toList(),
              onTap: _onChannelTap,
              onSeeAll: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const CategorySectionScreen(
                    title: 'Sports',
                    genreFilter: ChannelGenre.sports,
                  ),
                ),
              ),
            ),

          _TvRow(
            title: 'En direct maintenant',
            subtitle: '${live.length} chaînes',
            channels: live.take(20).toList(),
            onTap: _onChannelTap,
            onSeeAll: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const CategorySectionScreen(title: 'Live TV'),
              ),
            ),
          ),

          if (movies.isNotEmpty)
            _TvRow(
              title: 'Films',
              subtitle: '${movies.length} chaînes',
              channels: movies.take(20).toList(),
              onTap: _onChannelTap,
              onSeeAll: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const CategorySectionScreen(
                    title: 'Films',
                    genreFilter: ChannelGenre.movies,
                  ),
                ),
              ),
            ),

          if (series.isNotEmpty)
            _TvRow(
              title: 'Séries',
              subtitle: '${series.length} chaînes',
              channels: series.take(20).toList(),
              onTap: _onChannelTap,
              onSeeAll: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const CategorySectionScreen(
                    title: 'Séries',
                    genreFilter: ChannelGenre.series,
                  ),
                ),
              ),
            ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ============================================================
//  Top bar TV — brand à gauche, actions à droite, tout focusable
// ============================================================

class _TvTopBar extends StatelessWidget {
  const _TvTopBar({
    required this.onSearch,
    required this.onGuide,
    required this.onSettings,
  });

  final VoidCallback onSearch;
  final VoidCallback onGuide;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 64),
      child: Row(
        children: <Widget>[
          const BrandLogo.compact(),
          const SizedBox(width: 14),
          Text(
            BrandStrings.appName,
            style: AppTextStyles.headlineLarge.copyWith(
              fontSize: 22,
              letterSpacing: 4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          // Bouton Actualiser TV — focusable au D-pad, visible à 3 m.
          _TvIconButton(
            icon: Icons.refresh_rounded,
            label: 'Actualiser',
            onTap: () async {
              final ScaffoldMessengerState m =
                  ScaffoldMessenger.of(context);
              try {
                final int ok =
                    await PlaylistRepository.instance.refreshAll();
                m.showSnackBar(SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: Text(
                    ok == 0
                        ? 'Aucune playlist actualisée.'
                        : 'Actualisé : $ok playlist(s).',
                  ),
                ));
              } catch (e) {
                m.showSnackBar(SnackBar(
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.live,
                  content: Text('Erreur : $e'),
                ));
              }
            },
          ),
          const SizedBox(width: 10),
          _TvIconButton(
            icon: Icons.search_rounded,
            label: 'Recherche',
            onTap: onSearch,
          ),
          const SizedBox(width: 10),
          _TvIconButton(
            icon: Icons.event_note_rounded,
            label: 'Guide',
            onTap: onGuide,
          ),
          const SizedBox(width: 10),
          // Bouton cast — la version compacte existante marche très
          // bien en TV (icône + halo focus géré par le thème).
          const CastButton(),
          const SizedBox(width: 10),
          _TvIconButton(
            icon: Icons.settings_outlined,
            label: 'Réglages',
            onTap: onSettings,
          ),
          const SizedBox(width: 16),
          // ----- Pastille Aide VIP — toujours visible à la télécommande
          const VipHelpCard.floating(),
        ],
      ),
    );
  }
}

class _TvIconButton extends StatefulWidget {
  const _TvIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_TvIconButton> createState() => _TvIconButtonState();
}

class _TvIconButtonState extends State<_TvIconButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onShowFocusHighlight: (bool f) => setState(() => _focused = f),
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _focused
                  ? AppColors.accentSurface
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _focused ? AppColors.accent : AppColors.border,
                width: _focused ? 2 : 1,
              ),
              boxShadow: _focused ? AppColors.champagneGlow : null,
            ),
            child: Icon(
              widget.icon,
              color:
                  _focused ? AppColors.accent : AppColors.textSecondary,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
//  Hero XL — chaîne mise en avant, bouton Regarder focusable
// ============================================================

class _TvHero extends StatelessWidget {
  const _TvHero({
    required this.channel,
    required this.watchFocus,
    required this.onWatch,
  });

  final Channel channel;
  final FocusNode watchFocus;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 64),
      child: Container(
        height: 320,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
          gradient: LinearGradient(
            colors: <Color>[
              AppColors.surface,
              AppColors.surfaceHigh,
            ],
          ),
        ),
        padding: const EdgeInsets.all(36),
        child: Row(
          children: <Widget>[
            // ----- Visual -----
            SizedBox(
              width: 200,
              height: 200,
              child: ChannelLogo(
                channel: channel,
                size: ChannelLogoSize.large,
              ),
            ),
            const SizedBox(width: 36),
            // ----- Infos + CTA -----
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    'À LA UNE',
                    style: AppTextStyles.eyebrow,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    channel.cleanName,
                    style: AppTextStyles.displayLarge.copyWith(
                      fontSize: 40,
                      height: 1.05,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    channel.prettyCategory,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      focusNode: watchFocus,
                      autofocus: true,
                      onPressed: onWatch,
                      icon: const Icon(Icons.play_arrow_rounded, size: 26),
                      label: const Text('Regarder'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 14,
                        ),
                        textStyle: AppTextStyles.button.copyWith(
                          fontSize: 17,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
//  Rangée horizontale TV — cards XL focusables au D-pad
// ============================================================

class _TvRow extends StatelessWidget {
  const _TvRow({
    required this.title,
    required this.channels,
    required this.onTap,
    this.subtitle,
    this.onSeeAll,
  });

  final String title;
  final String? subtitle;
  final List<Channel> channels;
  final void Function(Channel) onTap;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(64, 0, 64, 14),
            child: Row(
              children: <Widget>[
                Text(title, style: AppTextStyles.headlineMedium.copyWith(
                  fontSize: 22,
                )),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(width: 10),
                  Text(
                    '· $subtitle',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 14,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                const Spacer(),
                if (onSeeAll != null)
                  TextButton(
                    onPressed: onSeeAll,
                    child: Text(
                      'Tout voir',
                      style: AppTextStyles.button.copyWith(fontSize: 14),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 220,
            child: FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 64),
                itemCount: channels.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (BuildContext context, int i) {
                  return _TvCard(
                    channel: channels[i],
                    onTap: () => onTap(channels[i]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TvCard extends StatefulWidget {
  const _TvCard({required this.channel, required this.onTap});

  final Channel channel;
  final VoidCallback onTap;

  @override
  State<_TvCard> createState() => _TvCardState();
}

class _TvCardState extends State<_TvCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    return FocusableActionDetector(
      onShowFocusHighlight: (bool f) => setState(() => _focused = f),
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedScale(
            scale: _focused ? 1.06 : 1.0,
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              width: 170,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _focused ? AppColors.accent : AppColors.border,
                  width: _focused ? 2.4 : 1,
                ),
                boxShadow: _focused ? AppColors.champagneGlow : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ChannelLogo(
                      channel: widget.channel,
                      size: ChannelLogoSize.large,
                    ),
                    // Scrim bas pour lisibilité du nom
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppColors.cardScrim,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      left: 12,
                      right: 12,
                      child: Text(
                        widget.channel.cleanName,
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
