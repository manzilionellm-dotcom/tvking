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
//    - Search + Guide + Settings dans la rangée du haut, tous
//      accessibles à la télécommande (pas de cast sur TV)
//
//  Le contenu (chaînes, sections) est identique au mode téléphone
//  pour ne pas avoir deux sources de vérité. On réutilise les
//  mêmes repositories. Seul le LAYOUT change.
// =========================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/branding/brand_logo.dart';
import '../../../core/branding/powered_by_marquee.dart';
import '../../../core/flavor/flavor.dart';
import '../../../core/support/vip_help_card.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/tv_palette.dart';
import '../../../core/widgets/tv_accent_scope.dart';
import '../../../core/widgets/tv_focusable.dart';
import '../../epg/presentation/tv_guide_screen.dart';
import '../../player/presentation/play_channel.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import 'widgets/source_choice_sheet.dart';
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
    // TvAccentScope : diffuse l'accent VIOLET à tous les TvFocusable
    // descendants (cartes, boutons d'icône…) sans les paramétrer un par
    // un. Le téléphone, lui, n'a pas ce scope → focus ember conservé.
    return TvAccentScope(
      focusBorderColor: TvRoyal.accent,
      focusGlow: TvRoyal.focusGlow(),
      child: Scaffold(
        backgroundColor: TvRoyal.background,
        body: Stack(
        children: <Widget>[
          // Fond avec gradient subtil
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: TvRoyal.backgroundGradient,
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
                    onAddPlaylist: () => showSourceChoiceSheet(context),
                  );
                }
                return _buildContent(channels);
              },
            ),
          ),

          // NB : la mini-bar de cast a été retirée de la version TV —
          // sur grand écran on regarde directement, pas besoin de
          // « caster » vers un autre appareil. Le cast reste dispo côté
          // téléphone uniquement.
        ],
        ),
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
        // Pré-rendre 1200 dp hors viewport = quand l'utilisateur
        // descend rapidement avec le D-pad, les rangées suivantes
        // sont déjà mesurées et prêtes à afficher (pas de jank
        // visible). Coût mémoire négligeable face au confort TV.
        cacheExtent: 1200,
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

          // La signature défilante du pied a été retirée — elle vit
          // maintenant collée au logo dans le top bar TV (cf. _TvTopBar).
          const SizedBox(height: 40),
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
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                FlavorConfig.current.appName,
                style: AppTextStyles.headlineLarge.copyWith(
                  fontSize: 22,
                  letterSpacing: 4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              // Baseline discrète sous le wordmark — la signature
              // animée du pied (ticker style) est supprimée.
              const BrandSignature(),
            ],
          ),

          const SizedBox(width: 44),
          // ----- Onglets de navigation (style Vu Player Pro) -----
          //  Raccourcis vers les grandes catégories. Focusables au D-pad.
          _TvNavChip(
            icon: Icons.live_tv_rounded,
            label: 'Direct',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const CategorySectionScreen(title: 'Live TV'),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _TvNavChip(
            icon: Icons.movie_outlined,
            label: 'Films',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const CategorySectionScreen(
                  title: 'Films',
                  genreFilter: ChannelGenre.movies,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _TvNavChip(
            icon: Icons.video_library_outlined,
            label: 'Séries',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const CategorySectionScreen(
                  title: 'Séries',
                  genreFilter: ChannelGenre.series,
                ),
              ),
            ),
          ),

          const Spacer(),
          // Horloge — repère temporel discret en haut à droite.
          const _TvClock(),
          const SizedBox(width: 18),
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
                  backgroundColor: TvRoyal.live,
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
          // (Bouton cast retiré de la version TV — cf. note en tête du
          // build : pas de casting sur grand écran.)
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

/// Onglet de navigation du top bar (style Vu Player Pro). Pilule
/// icône + label, focusable au D-pad (anneau violet via TvAccentScope).
class _TvNavChip extends StatelessWidget {
  const _TvNavChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      semanticsLabel: label,
      ensureVisibleAlignment: 0.5,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: TvRoyal.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 20, color: TvRoyal.textSecondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTextStyles.button.copyWith(
                fontSize: 15,
                color: TvRoyal.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horloge du top bar — se met à jour toutes les 20 s (suffisant pour
/// l'affichage HH:mm, et économe). Format 24 h, chiffres tabulaires.
class _TvClock extends StatefulWidget {
  const _TvClock();

  @override
  State<_TvClock> createState() => _TvClockState();
}

class _TvClockState extends State<_TvClock> {
  late final Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String hh = _now.hour.toString().padLeft(2, '0');
    final String mm = _now.minute.toString().padLeft(2, '0');
    return Text(
      '$hh:$mm',
      style: AppTextStyles.numeric.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: TvRoyal.textPrimary,
      ),
    );
  }
}

/// Bouton icône du top bar TV — focus géré par `TvFocusable`.
/// Garde une logique propre (fond violet au focus pour signaler la
/// sélection, icône change de teinte) que `TvFocusable` n'a pas
/// vocation à embarquer (c'est cosmétique de ce widget précis).
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
  final FocusNode _focusNode = FocusNode(debugLabel: 'tv-icon-button');

  @override
  void initState() {
    super.initState();
    // On suit le focus pour piloter la couleur de fond / icône
    // sans dupliquer la logique de bordure & glow (gérée par
    // `TvFocusable`).
    _focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bool focused = _focusNode.hasFocus;
    return TvFocusable(
      onTap: widget.onTap,
      focusNode: _focusNode,
      borderRadius: BorderRadius.circular(12),
      semanticsLabel: widget.label,
      // Pas de scroll-on-focus utile dans la top bar (toujours visible),
      // on désactive juste le surcoût.
      ensureVisibleAlignment: 0.5,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: focused ? TvRoyal.accentSurface : TvRoyal.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          widget.icon,
          color: focused ? TvRoyal.accent : TvRoyal.textSecondary,
          size: 28,
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
          color: TvRoyal.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: TvRoyal.border),
          gradient: LinearGradient(
            colors: <Color>[
              TvRoyal.surface,
              TvRoyal.surfaceHigh,
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
                    // `eyebrow` est rouge ember par défaut → on le force
                    // en violet pour rester dans l'identité TV.
                    style: AppTextStyles.eyebrow.copyWith(
                      color: TvRoyal.accentGlow,
                    ),
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
                      color: TvRoyal.textSecondary,
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
                        // Bouton Play en VIOLET (pilule claire, label
                        // sombre pour le contraste — cf. études).
                        backgroundColor: TvRoyal.accent,
                        foregroundColor: TvRoyal.voidSurface,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 14,
                        ),
                        textStyle: AppTextStyles.button.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
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
                      color: TvRoyal.textMuted,
                    ),
                  ),
                ],
                const Spacer(),
                if (onSeeAll != null)
                  TextButton(
                    onPressed: onSeeAll,
                    style: TextButton.styleFrom(
                      foregroundColor: TvRoyal.accent,
                    ),
                    child: Text(
                      'Tout voir',
                      style: AppTextStyles.button.copyWith(
                        fontSize: 14,
                        color: TvRoyal.accent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            // Cards TV agrandies (200×280) — plus lisibles à 3 m
            // qu'un écran de téléphone à 30 cm. La hauteur de la
            // rangée englobe la carte + marge d'aération.
            height: 290,
            child: FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 64),
                // Pré-rendre 1000 dp à droite = quand l'utilisateur
                // appuie ⟶ plusieurs fois rapidement, les cartes
                // suivantes sont déjà prêtes (pas de "trou blanc"
                // pendant que le logo charge).
                cacheExtent: 1000,
                itemCount: channels.length,
                separatorBuilder: (_, __) => const SizedBox(width: 18),
                itemBuilder: (BuildContext context, int i) {
                  // RepaintBoundary isole le repaint de chaque carte
                  // pour que l'animation de scale au focus ne force
                  // pas le repaint de toute la rangée.
                  return RepaintBoundary(
                    child: _TvCard(
                      channel: channels[i],
                      onTap: () => onTap(channels[i]),
                    ),
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

/// Carte chaîne TV — version 10-foot (200×280) avec focus ring
/// ember + scale + scroll-on-focus géré centralement par
/// `TvFocusable`. Si tu veux changer le look TV global (rayon,
/// glow, scale), édite `TvFocusable`, pas ce fichier.
class _TvCard extends StatelessWidget {
  const _TvCard({required this.channel, required this.onTap});

  final Channel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      unfocusedBorderColor: TvRoyal.border,
      semanticsLabel: channel.cleanName,
      child: SizedBox(
        width: 200,
        height: 280,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ChannelLogo(
                channel: channel,
                size: ChannelLogoSize.large,
              ),
              // Scrim bas pour lisibilité du nom posé par-dessus
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: TvRoyal.cardScrim,
                  ),
                ),
              ),
              Positioned(
                bottom: 14,
                left: 14,
                right: 14,
                child: Text(
                  channel.cleanName,
                  // Taille 16 px pour rester lisible à 3 m.
                  // L'ancienne valeur 13 px était trop fine pour TV.
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
