// =========================================================
//  tv_tivimate_home_screen.dart — Template « TiviMate »
// =========================================================
//  Réplique de l'accueil TiviMate (liste des chaînes en panneau) :
//    • rail d'icônes à gauche (Recherche · TV actif · Films · Séries ·
//      Catch-up · Templates · Réglages)
//    • colonne des GROUPES (catégories dépliées de la playlist)
//    • liste des CHAÎNES du groupe + APERÇU (logo/nom/n°) et EPG now/next
//  OK sur une chaîne → TvPlayerScreen (ExoPlayer/Media3) → zapping haut/bas.
//
//  COULEURS IDENTIQUES à TiviMate (fond #000000, panneaux #12171C, accent
//  bleu #0A84FF, focus = pill blanc plein / texte noir, chaîne active =
//  n°+nom bleu + ►). SEUL le logo = SEVEN.
//
//  Réutilise UNIQUEMENT des briques EXISTANTES (PlaylistRepository,
//  MiniEpgNowNext, TvChannelLogo, TvPlayerScreen). AUCUN fichier media_kit :
//  la lecture passe par TvPlayerScreen (natif). Aucun fichier cast/lecture/
//  boot touché. 100 % télécommande.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../channels/domain/channel.dart';
import '../../channels/domain/channel_genre.dart';
import '../../epg/presentation/widgets/mini_epg_now_next.dart';
import '../../playlists/data/playlist_repository.dart';
import '../core/tv_focusable.dart';
import '../core/tv_logo.dart';
import 'tv_films_screen.dart';
import 'tv_home_template_screen.dart';
import 'tv_player_screen.dart';
import 'tv_recordings_screen.dart';
import 'tv_search_screen.dart';
import 'tv_series_screen.dart';
import 'tv_settings_screen.dart';
import 'tv_tivimate_guide_screen.dart';

// ---- Palette TiviMate (tokens §1 de la fiche) ----
const Color _tmBg = Color(0xFF000000); // fond app / vidéo
const Color _tmPanel = Color(0xFF12171C); // surface panneau (groupes/liste)
const Color _tmRail = Color(0xFF0C0F12); // rail d'icônes
const Color _tmItem = Color(0xFF1E2126); // item au repos
const Color _tmAccent = Color(0xFF0A84FF); // ACCENT bleu marque
const Color _tmText = Color(0xFFFFFFFF); // texte principal
const Color _tmText2 = Color(0xFFB8BDC4); // texte secondaire
const Color _tmText3 = Color(0xFF6B7178); // texte tertiaire / n°
const Color _tmSoft = Color(0xFF3A3E45); // sélection douce (groupe non focus)

const String _kAllGroup = 'Toutes les chaînes';

class TvTivimateHomeScreen extends StatefulWidget {
  const TvTivimateHomeScreen({super.key});

  @override
  State<TvTivimateHomeScreen> createState() => _TvTivimateHomeScreenState();
}

class _TvTivimateHomeScreenState extends State<TvTivimateHomeScreen> {
  StreamSubscription<List<Channel>>? _sub;
  List<Channel> _all = <Channel>[];
  List<String> _groups = <String>[_kAllGroup];
  String _group = _kAllGroup;
  List<Channel> _visible = <Channel>[];
  Channel? _preview;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _ingest(PlaylistRepository.instance.currentChannels);
    _sub = PlaylistRepository.instance.channelsStream.listen(_ingest);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Nombre de chaînes par groupe — PRÉ-CALCULÉ à l'ingestion (une passe).
  /// Filtrer 10 000+ chaînes par tuile à chaque rebuild saccaderait.
  Map<String, int> _counts = <String, int>{};

  void _ingest(List<Channel> channels) {
    // Groupes = catégories nettoyées, dans l'ordre de première apparition.
    final List<String> groups = <String>[_kAllGroup];
    final Set<String> seen = <String>{};
    final Map<String, int> counts = <String, int>{};
    for (final Channel c in channels) {
      final String g = ChannelClassifier.prettifyCategory(c.category);
      if (g.isEmpty) continue;
      if (seen.add(g)) groups.add(g);
      counts[g] = (counts[g] ?? 0) + 1;
    }
    counts[_kAllGroup] = channels.length;
    if (!mounted) return;
    setState(() {
      _all = channels;
      _groups = groups;
      _counts = counts;
      if (!_groups.contains(_group)) _group = _kAllGroup;
      _visible = _channelsFor(_group);
      _preview ??= _visible.isNotEmpty ? _visible.first : null;
      _loading = false;
    });
  }

  List<Channel> _channelsFor(String group) {
    if (group == _kAllGroup) return _all;
    return _all
        .where((Channel c) =>
            ChannelClassifier.prettifyCategory(c.category) == group)
        .toList(growable: false);
  }

  void _selectGroup(String group) {
    setState(() {
      _group = group;
      _visible = _channelsFor(group);
      _preview = _visible.isNotEmpty ? _visible.first : null;
    });
  }

  void _play(int index) {
    if (_visible.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvPlayerScreen(channels: _visible, startIndex: index),
      ),
    );
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) async {
        if (didPop) return;
        await SystemNavigator.pop();
      },
      child: Container(
        color: _tmBg,
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _iconRail(),
                _groupsColumn(),
                Expanded(child: _channelPane()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Rail d'icônes (gauche) ----
  Widget _iconRail() {
    return Container(
      width: 76,
      color: _tmRail,
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: <Widget>[
          _RailIcon(
              icon: Icons.search_rounded,
              onSelect: () => _open(const TvSearchScreen())),
          const SizedBox(height: 14),
          const _RailIcon(icon: Icons.live_tv_rounded, active: true),
          const SizedBox(height: 14),
          _RailIcon(
              icon: Icons.movie_rounded,
              onSelect: () => _open(const TvFilmsScreen())),
          const SizedBox(height: 14),
          _RailIcon(
              icon: Icons.video_library_rounded,
              onSelect: () => _open(const TvSeriesScreen())),
          const SizedBox(height: 14),
          _RailIcon(
              icon: Icons.replay_rounded,
              onSelect: () => _open(const TvRecordingsScreen())),
          const SizedBox(height: 14),
          _RailIcon(
              icon: Icons.grid_view_rounded,
              onSelect: () => _open(const TvTivimateGuideScreen())),
          const Spacer(),
          _RailIcon(
              icon: Icons.dashboard_customize_rounded,
              onSelect: () => _open(const TvHomeTemplateScreen())),
          const SizedBox(height: 14),
          _RailIcon(
              icon: Icons.settings_outlined,
              onSelect: () => _open(const TvSettingsScreen())),
        ],
      ),
    );
  }

  // ---- Colonne des groupes ----
  Widget _groupsColumn() {
    return Container(
      width: 300,
      color: _tmPanel,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Text('Groupes',
                style: TextStyle(
                    color: _tmText3,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _groups.length,
              itemBuilder: (BuildContext context, int i) {
                final String g = _groups[i];
                return _GroupTile(
                  label: g,
                  count: _counts[g] ?? 0,
                  active: g == _group,
                  autofocus: false,
                  onSelect: () => _selectGroup(g),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---- Panneau chaînes : aperçu (haut) + liste (bas) ----
  Widget _channelPane() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: _tmAccent));
    }
    if (_visible.isEmpty) {
      return const Center(
        child: Text('Aucune chaîne dans ce groupe',
            style: TextStyle(color: _tmText2, fontSize: 18)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _preview == null ? const SizedBox.shrink() : _previewHeader(_preview!),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            itemCount: _visible.length,
            itemBuilder: (BuildContext context, int i) {
              final Channel c = _visible[i];
              return Focus(
                key: ValueKey<String>('tm-focus-${c.id}-$i'),
                canRequestFocus: false,
                skipTraversal: true,
                onFocusChange: (bool has) {
                  if (has && mounted && _preview?.id != c.id) {
                    setState(() => _preview = c);
                  }
                },
                child: _ChannelRow(
                  number: i + 1,
                  channel: c,
                  active: _preview?.id == c.id,
                  autofocus: i == 0,
                  onSelect: () => _play(i),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---- Aperçu (logo + nom + n° + EPG now/next) ----
  Widget _previewHeader(Channel c) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _tmPanel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TvChannelLogo(logoUrl: c.logoUrl, label: c.name, size: 84, radius: 10),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _tmText,
                      fontSize: 26,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                MiniEpgNowNext(channelId: c.id),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================
//  Sous-widgets
// =========================================================

/// Icône du rail gauche. `active` = onglet courant (fond bleu accent).
class _RailIcon extends StatelessWidget {
  const _RailIcon({required this.icon, this.onSelect, this.active = false});
  final IconData icon;
  final VoidCallback? onSelect;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      enabled: onSelect != null,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color bg = focused
            ? _tmText // pill blanc au focus
            : active
                ? _tmAccent
                : Colors.transparent;
        final Color fg = focused
            ? _tmBg
            : active
                ? _tmText
                : _tmText3;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(icon, size: 26, color: fg),
        );
      },
    );
  }
}

/// Ligne de groupe (catégorie). Focus = pill blanc ; actif = texte bleu.
class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.label,
    required this.count,
    required this.active,
    required this.autofocus,
    required this.onSelect,
  });
  final String label;

  /// Nombre de chaînes du groupe — affiché à droite (demande client).
  final int count;
  final bool active;
  final bool autofocus;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color bg = focused
            ? _tmText
            : active
                ? _tmSoft
                : Colors.transparent;
        final Color fg = focused
            ? _tmBg
            : active
                ? _tmAccent
                : _tmText2;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: fg,
                      fontSize: 17,
                      fontWeight:
                          active ? FontWeight.w700 : FontWeight.w500),
                ),
              ),
              const SizedBox(width: 8),
              // Compteur de chaînes du groupe (ex. « Sports FR · 240 »).
              Text('$count',
                  style: TextStyle(
                      color: focused ? _tmBg : _tmText3,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              if (active && !focused) ...<Widget>[
                const SizedBox(width: 6),
                const Icon(Icons.play_arrow_rounded,
                    size: 18, color: _tmAccent),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Ligne de chaîne : [n°] [logo] [nom] [► si active]. Focus = pill blanc.
class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.number,
    required this.channel,
    required this.active,
    required this.autofocus,
    required this.onSelect,
  });
  final int number;
  final Channel channel;
  final bool active;
  final bool autofocus;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color bg = focused
            ? _tmText
            : active
                ? _tmItem
                : Colors.transparent;
        final Color nameColor = focused
            ? _tmBg
            : active
                ? _tmAccent
                : _tmText;
        final Color numColor = focused
            ? _tmBg
            : active
                ? _tmAccent
                : _tmText3;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 44,
                child: Text(
                  '$number',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: numColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              TvChannelLogo(
                  logoUrl: channel.logoUrl,
                  label: channel.name,
                  size: 44,
                  radius: 8),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: nameColor,
                      fontSize: 18,
                      fontWeight:
                          active ? FontWeight.w700 : FontWeight.w500),
                ),
              ),
              if (active && !focused)
                const Icon(Icons.play_arrow_rounded,
                    size: 20, color: _tmAccent),
            ],
          ),
        );
      },
    );
  }
}
