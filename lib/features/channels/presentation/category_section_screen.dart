// =========================================================
//  category_section_screen.dart — Écran de section unifié
// =========================================================
//  UN SEUL écran pour toutes les sections principales :
//   - Live TV (toutes les chaînes)
//   - Sports
//   - Films
//   - Séries
//   - Jeunesse
//   - Info
//   - Musique
//   - Documentaires
//   - International
//
//  Filtre fait en mémoire (instantané sur 20k chaînes).
//  Affichage en mode COMPACT LIST par défaut (item extent
//  fixe → ListView.builder ultra rapide), avec bouton pour
//  basculer en mode GRILLE si l'utilisateur préfère.
//
//  Sous-filtres :
//    - Live / Tous
//    - Par catégorie M3U (les groupes bruts)
//    - Par pays détecté
//    - Par qualité (HD+)
// =========================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../cast/presentation/cast_button.dart';
import '../../player/presentation/play_channel.dart';
import '../../playlists/data/playlist_repository.dart';
import '../domain/channel.dart';
import '../domain/channel_genre.dart';
import 'channel_detail_sheet.dart';
import 'widgets/channel_card.dart';
import 'widgets/compact_channel_row.dart';

enum SectionViewMode { compact, grid }

class CategorySectionScreen extends StatefulWidget {
  const CategorySectionScreen({
    required this.title,
    this.genreFilter,
    this.rawCategoryFilter,
    this.countryFilter,
    super.key,
  });

  final String title;

  /// Si fourni → on filtre par ce genre canonique.
  final ChannelGenre? genreFilter;

  /// Si fourni → on filtre par cette catégorie BRUTE (group-title M3U).
  final String? rawCategoryFilter;

  /// Si fourni → on filtre par pays détecté.
  final String? countryFilter;

  @override
  State<CategorySectionScreen> createState() => _CategorySectionScreenState();
}

class _CategorySectionScreenState extends State<CategorySectionScreen> {
  static const String _kViewModePrefKey = 'section.view_mode';
  SectionViewMode _viewMode = SectionViewMode.compact;

  // Sous-filtres
  bool _liveOnly = false;
  ChannelQuality? _qualityFilter;
  String? _selectedSubCategory;
  CountryInfo? _countryFilter;

  // Recherche interne
  String _query = '';
  final TextEditingController _searchCtrl = TextEditingController();

  List<Channel> _channels = const <Channel>[];
  StreamSubscription<List<Channel>>? _sub;

  @override
  void initState() {
    super.initState();
    _channels = PlaylistRepository.instance.currentChannels;
    if (_channels.isEmpty) {
      PlaylistRepository.instance.getAllChannels().then((List<Channel> ch) {
        if (mounted) setState(() => _channels = ch);
      });
    }
    _sub =
        PlaylistRepository.instance.channelsStream.listen((List<Channel> ch) {
      if (mounted) setState(() => _channels = ch);
    });
    _restoreViewMode();
  }

  Future<void> _restoreViewMode() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? saved = prefs.getString(_kViewModePrefKey);
    if (!mounted || saved == null) return;
    setState(() {
      _viewMode = saved == 'grid'
          ? SectionViewMode.grid
          : SectionViewMode.compact;
    });
  }

  Future<void> _setViewMode(SectionViewMode mode) async {
    setState(() => _viewMode = mode);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kViewModePrefKey,
      mode == SectionViewMode.grid ? 'grid' : 'compact',
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _sub?.cancel();
    super.dispose();
  }

  List<Channel> _applyFilters(List<Channel> all) {
    Iterable<Channel> q = all;

    // Filtre par genre canonique
    if (widget.genreFilter != null) {
      q = q.where((Channel c) => c.genre == widget.genreFilter);
    }
    // Filtre par catégorie M3U brute
    if (widget.rawCategoryFilter != null) {
      q = q.where((Channel c) => c.category == widget.rawCategoryFilter);
    }
    // Filtre par pays
    if (widget.countryFilter != null) {
      q = q.where(
          (Channel c) => c.country?.code == widget.countryFilter);
    }

    // Sous-filtre : live uniquement
    if (_liveOnly) {
      q = q.where((Channel c) => c.isLive);
    }
    // Sous-filtre : qualité
    if (_qualityFilter != null) {
      q = q.where((Channel c) => c.quality == _qualityFilter);
    }
    // Drill-down dans une sous-catégorie M3U
    if (_selectedSubCategory != null) {
      q = q.where((Channel c) => c.category == _selectedSubCategory);
    }
    // Recherche libre
    if (_query.trim().isNotEmpty) {
      final String needle = _query.trim().toLowerCase();
      q = q.where(
          (Channel c) => c.name.toLowerCase().contains(needle));
    }

    return q.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          const CastButton(),
          _ViewModeToggle(
            current: _viewMode,
            onChanged: _setViewMode,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Builder(
        builder: (BuildContext context) {
          final List<Channel> all = _channels;
          final List<Channel> filtered = _applyFilters(all);

          return Column(
            children: <Widget>[
              _SearchBar(
                controller: _searchCtrl,
                onChanged: (String v) => setState(() => _query = v),
              ),
              _FilterChipsBar(
                allCount: all.length,
                filteredCount: filtered.length,
                liveOnly: _liveOnly,
                qualityFilter: _qualityFilter,
                onLiveToggle: () => setState(() => _liveOnly = !_liveOnly),
                onQuality: (ChannelQuality? q) =>
                    setState(() => _qualityFilter = q),
              ),
              if (widget.rawCategoryFilter == null)
                _SubCategoriesBar(
                  channels: widget.genreFilter == null
                      ? all
                      : all
                          .where((Channel c) => c.genre == widget.genreFilter)
                          .toList(growable: false),
                  selected: _selectedSubCategory,
                  onSelected: (String? cat) =>
                      setState(() => _selectedSubCategory = cat),
                ),
              const SizedBox(height: 4),
              Expanded(
                child: filtered.isEmpty
                    ? _EmptyResult(query: _query)
                    : _viewMode == SectionViewMode.compact
                        ? _CompactList(channels: filtered)
                        : _Grid(channels: filtered),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================
//  Composants internes
// ============================================================

class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({
    required this.current,
    required this.onChanged,
  });

  final SectionViewMode current;
  final ValueChanged<SectionViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          _segment(
            icon: Icons.view_list_rounded,
            selected: current == SectionViewMode.compact,
            onTap: () => onChanged(SectionViewMode.compact),
            tooltip: context.l10n.viewModeList,
          ),
          Container(
            width: 1,
            height: 20,
            color: AppColors.border,
          ),
          _segment(
            icon: Icons.grid_view_rounded,
            selected: current == SectionViewMode.grid,
            onTap: () => onChanged(SectionViewMode.grid),
            tooltip: context.l10n.viewModeGrid,
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? AppColors.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: selected ? Colors.black : AppColors.textSecondary,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: AppTextStyles.bodyLarge.copyWith(fontSize: 14),
        decoration: InputDecoration(
          hintText: context.l10n.sectionFilterHint,
          hintStyle: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textMuted,
            fontSize: 13,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: AppColors.textMuted,
            size: 20,
          ),
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.accent, width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _FilterChipsBar extends StatelessWidget {
  const _FilterChipsBar({
    required this.allCount,
    required this.filteredCount,
    required this.liveOnly,
    required this.qualityFilter,
    required this.onLiveToggle,
    required this.onQuality,
  });

  final int allCount;
  final int filteredCount;
  final bool liveOnly;
  final ChannelQuality? qualityFilter;
  final VoidCallback onLiveToggle;
  final ValueChanged<ChannelQuality?> onQuality;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: <Widget>[
          Text(
            '$filteredCount / $allCount',
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  _chip(
                    label: context.l10n.badgeLive,
                    selected: liveOnly,
                    onTap: onLiveToggle,
                  ),
                  const SizedBox(width: 6),
                  _chip(
                    label: 'HD+',
                    selected: qualityFilter == ChannelQuality.hd,
                    onTap: () => onQuality(
                        qualityFilter == ChannelQuality.hd
                            ? null
                            : ChannelQuality.hd),
                  ),
                  const SizedBox(width: 6),
                  _chip(
                    label: '4K',
                    selected: qualityFilter == ChannelQuality.q4K,
                    onTap: () => onQuality(
                        qualityFilter == ChannelQuality.q4K
                            ? null
                            : ChannelQuality.q4K),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              fontSize: 11,
              color: selected ? Colors.black : AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// Barre horizontale des sous-catégories M3U brutes existantes
/// (utile pour drill-down dans Sports → "Sports US" / "Sports FR").
class _SubCategoriesBar extends StatelessWidget {
  const _SubCategoriesBar({
    required this.channels,
    required this.selected,
    required this.onSelected,
  });

  final List<Channel> channels;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    // Compte les sous-catégories
    final Map<String, int> counts = <String, int>{};
    for (final Channel c in channels) {
      counts[c.category] = (counts[c.category] ?? 0) + 1;
    }
    if (counts.length <= 1) return const SizedBox.shrink();

    final List<MapEntry<String, int>> sorted = counts.entries.toList()
      ..sort((MapEntry<String, int> a, MapEntry<String, int> b) =>
          b.value.compareTo(a.value));

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: sorted.length + 1,
        separatorBuilder: (BuildContext _, int __) =>
            const SizedBox(width: 6),
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return _categoryChip(
              label: context.l10n.filterAll,
              selected: selected == null,
              onTap: () => onSelected(null),
            );
          }
          final MapEntry<String, int> entry = sorted[index - 1];
          return _categoryChip(
            label:
                '${_pretty(entry.key)} · ${entry.value}',
            selected: selected == entry.key,
            onTap: () => onSelected(entry.key),
          );
        },
      ),
    );
  }

  String _pretty(String raw) =>
      ChannelClassifier.prettifyCategory(raw);

  Widget _categoryChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accentSurface
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 11,
              color: selected
                  ? AppColors.accent
                  : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactList extends StatelessWidget {
  const _CompactList({required this.channels});

  final List<Channel> channels;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      // itemExtent = clé de la perf à 20k items
      itemExtent: CompactChannelRow.height,
      cacheExtent: 1200, // pré-rend ~20 tiles invisibles → scroll smooth
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: false, // déjà fait manuellement plus bas
      itemCount: channels.length,
      itemBuilder: (BuildContext context, int index) {
        final Channel ch = channels[index];
        return RepaintBoundary(
          child: CompactChannelRow(
            channel: ch,
            onTap: () => playChannel(context, ch, zapPlaylist: channels),
            onLongPress: () => showChannelDetail(context, ch),
          ),
        );
      },
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.channels});

  final List<Channel> channels;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints cons) {
        final double w = cons.maxWidth;
        final int cols = w >= 1400 ? 6 : w >= 1000 ? 5 : w >= 700 ? 4 : 3;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          cacheExtent: 800,
          addAutomaticKeepAlives: false,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 16 / 13,
          ),
          itemCount: channels.length,
          itemBuilder: (BuildContext context, int index) {
            final Channel ch = channels[index];
            return RepaintBoundary(
              child: ChannelCard(
                channel: ch,
                onTap: () => playChannel(context, ch, zapPlaylist: channels),
                onLongPress: () => showChannelDetail(context, ch),
              ),
            );
          },
        );
      },
    );
  }
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              query.isEmpty
                  ? context.l10n.sectionEmptyNoChannel
                  : context.l10n.searchNoResult(query),
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge,
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.sectionEmptyAdjustFilters,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
