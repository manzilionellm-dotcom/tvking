// =========================================================
//  tv_iptv_home_screen.dart — Modèle B (design fourni par le client)
// =========================================================
//  Reprise FIDÈLE de la maquette envoyée par le client :
//    • thème qui suit l'heure — « Mode soirée » après 19 h, « Mode jour »
//      sinon (fonds et accent différents, plus doux pour les yeux le soir) ;
//    • bandeau haut : titre + pastille du mode courant ;
//    • rangée « Recommandé pour toi » (cartes larges qui défilent) ;
//    • grille « Toutes les chaînes » en 4 colonnes ;
//    • carte qui GRANDIT (1,08×) et s'entoure d'un halo à l'accent quand
//      elle prend le focus.
//
//  CE QUI A ÉTÉ ADAPTÉ pour que ce soit un vrai accueil de TV, et non une
//  maquette :
//    • les chaînes viennent du bouquet RÉEL (PlaylistRepository) et se
//      rafraîchissent toutes seules — plus de liste écrite en dur ;
//    • le focus est un VRAI focus télécommande (TvFocusBuilder : D-pad,
//      appui OK, tactile) et non un Focus décoratif ;
//    • OK ouvre la chaîne en plein écran, avec le zap Haut/Bas sur la même
//      liste que celle affichée ;
//    • la grille est PARESSEUSE : elle ne construit que les cartes visibles,
//      donc 40 000 chaînes coûtent autant que 12 ;
//    • les logos passent par OptimizedImage (décodage et disque bornés) et
//      retombent sur le monogramme doré quand la chaîne n'a pas d'image —
//      aucun panel IPTV ne fournit de BlurHash, le repli joue ce rôle ;
//    • « Recommandé pour toi » n'est pas décoratif : il reprend l'ordre
//      d'affection (habitude horaire → récents → favoris) et écarte les
//      chaînes que la box sait défaillantes (hero_picker, n°38).
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../widgets/optimized_image.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../channels/domain/channel.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../core/tv_focusable.dart';
import '../core/tv_logo.dart';
import '../data/channel_reliability.dart';
import '../data/hero_picker.dart';
import 'tv_player_screen.dart';

class TvIptvHomeScreen extends StatefulWidget {
  const TvIptvHomeScreen({super.key});

  @override
  State<TvIptvHomeScreen> createState() => _TvIptvHomeScreenState();
}

class _TvIptvHomeScreenState extends State<TvIptvHomeScreen> {
  StreamSubscription<List<Channel>>? _chanSub;
  StreamSubscription<List<String>>? _recentSub;

  List<Channel> _all = const <Channel>[];
  List<Channel> _reco = const <Channel>[];

  /// L'heure décide de l'ambiance. Recalculée à chaque construction, et
  /// rafraîchie par une minuterie douce : à 19 h pile, l'accueil bascule en
  /// mode soirée sans que le client ait à quitter l'écran.
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _refresh();
    _chanSub =
        PlaylistRepository.instance.channelsStream.listen((_) => _refresh());
    _recentSub =
        RecentlyWatchedRepository.instance.stream.listen((_) => _refresh());
    _clock = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _chanSub?.cancel();
    _recentSub?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  void _refresh() {
    final List<Channel> all = PlaylistRepository.instance.currentChannels;
    if (!mounted) return;
    setState(() {
      _all = all;
      _reco = all.isEmpty
          ? const <Channel>[]
          : heroCandidates(
              all: all,
              byId: <String, Channel>{for (final Channel c in all) c.id: c},
              recents: RecentlyWatchedRepository.instance.current,
              favorites: FavoritesRepository.instance.current,
              isFlaky: ChannelReliability.instance.isFlaky,
              max: 12,
            );
    });
  }

  // ---- Ambiance selon l'heure (spécification client) ----
  bool get _isEvening {
    final int h = DateTime.now().hour;
    return h >= 19 || h < 6;
  }

  Color get _bg =>
      _isEvening ? const Color(0xFF0B0F14) : const Color(0xFF0F1419);
  Color get _card =>
      _isEvening ? const Color(0xFF151A21) : const Color(0xFF1A2028);
  Color get _accent =>
      _isEvening ? const Color(0xFF4ECDC4) : const Color(0xFF00D4FF);

  void _play(List<Channel> list, int index) {
    if (list.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Material(
        type: MaterialType.transparency,
        child: TvPlayerScreen(channels: list, startIndex: index),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: <Widget>[
            SliverToBoxAdapter(child: _header()),
            if (_reco.isNotEmpty) ...<Widget>[
              SliverToBoxAdapter(child: _sectionTitle('Recommandé pour toi')),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 220,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: _reco.length,
                    itemBuilder: (BuildContext _, int i) => _ChannelCard(
                      channel: _reco[i],
                      accent: _accent,
                      cardColor: _card,
                      autofocus: i == 0,
                      onSelect: () => _play(_reco, i),
                    ),
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
            SliverToBoxAdapter(
              child: _sectionTitle('Toutes les chaînes  ·  ${_all.length}'),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
              sliver: SliverGrid(
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: 1.1,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                // PARESSEUSE : seules les cartes visibles sont construites —
                // c'est ce qui permet à 40 000 chaînes de coûter autant
                // qu'une douzaine.
                delegate: SliverChildBuilderDelegate(
                  (BuildContext _, int i) => _ChannelCard(
                    channel: _all[i],
                    accent: _accent,
                    cardColor: _card,
                    isGrid: true,
                    autofocus: _reco.isEmpty && i == 0,
                    onSelect: () => _play(_all, i),
                  ),
                  childCount: _all.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
        child: Row(
          children: <Widget>[
            const Text(
              'IPTV',
              style: TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _accent.withValues(alpha: 0.3)),
              ),
              child: Text(
                _isEvening ? 'Mode soirée' : 'Mode jour',
                style: TextStyle(
                  color: _accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 8, 32, 16),
        child: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

/// Carte de chaîne : grandit et s'allume au focus (spécification client).
class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
    required this.channel,
    required this.accent,
    required this.cardColor,
    required this.onSelect,
    this.isGrid = false,
    this.autofocus = false,
  });

  final Channel channel;
  final Color accent;
  final Color cardColor;
  final VoidCallback onSelect;
  final bool isGrid;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    // TvFocusBuilder = le VRAI focus télécommande de l'app (D-pad, OK,
    // tactile). Il porte déjà l'agrandissement : on ne le redouble pas.
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.medium,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: isGrid ? null : 180,
        margin: isGrid ? EdgeInsets.zero : const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: focused ? accent : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: focused
              ? <BoxShadow>[
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 72,
              height: 72,
              child: (channel.logoUrl ?? '').isEmpty
                  ? TvChannelLogo(
                      logoUrl: null,
                      label: channel.name,
                      size: 72,
                      radius: 12,
                    )
                  : OptimizedImage(
                      imageUrl: channel.logoUrl!,
                      width: 72,
                      height: 72,
                      fit: BoxFit.contain,
                      borderRadius: BorderRadius.circular(12),
                      // Repli instantané : le monogramme doré de la chaîne
                      // (aucun panel IPTV ne fournit de BlurHash).
                      fallback: TvChannelLogo(
                        logoUrl: null,
                        label: channel.name,
                        size: 72,
                        radius: 12,
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                channel.cleanName,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
