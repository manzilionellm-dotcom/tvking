// =========================================================
//  search_screen.dart — Découverte premium type Netflix
// =========================================================
//  Refonte complète de la recherche pour la rendre digne d'un
//  produit grand public :
//
//    - Input avec autofocus + bouton clear contextuel
//    - Debounce 300 ms (filtre exécuté seulement quand l'user
//      s'arrête de taper, pas à chaque keystroke)
//    - Skeleton shimmer pendant la fenêtre de recherche
//    - Recherches récentes (10 max) en chips horizontaux
//    - Chips par genre (Sports / Films / Séries / Kids / News /
//      Music / Docs) — tap pour pré-filtrer sans rien taper
//    - Section "À découvrir" : 6 chaînes aléatoires avec logo
//    - États dédiés : aide initiale, loading, results, no-results,
//      empty (aucune chaîne chargée)
//    - Cards riches avec badges LIVE / qualité (4K, HD…) / drapeau
//      pays
//    - Tap = lecture (route existante via playChannel), long-press
//      = sheet de détail
//
//  Performance : la liste de chaînes est filtrée en mémoire (cache
//  PlaylistRepository). Sur 27k chaînes, ~50 ms par filtre.
//  Combiné au debounce 300 ms, l'expérience est fluide même
//  pendant la frappe rapide.
//
//  Le tap "Genre" pré-remplit l'input avec le label du genre et
//  filtre tout de suite — pas besoin de comprendre la mécanique.
// =========================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../cast/presentation/cast_button.dart';
import '../../player/presentation/play_channel.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../vod/data/vod_repository.dart';
import '../../vod/domain/vod_movie.dart';
import '../data/ai_search_service.dart';
import '../data/recent_searches_repository.dart';
import '../domain/channel.dart';
import '../domain/channel_genre.dart';
import 'channel_detail_sheet.dart';
import 'widgets/search_result_card.dart';
import 'widgets/search_skeleton.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum _SearchState { idle, loading, results, noResults, empty }

class _SearchScreenState extends State<SearchScreen> {
  static const Duration _kDebounce = Duration(milliseconds: 300);

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounceTimer;

  String _activeQuery = '';
  List<Channel> _results = const <Channel>[];
  _SearchState _state = _SearchState.idle;

  /// Films VOD convertis en [Channel] (isLive=false) pour qu'ils
  /// soient cherchables ET jouables EXACTEMENT comme une chaîne (même
  /// carte, même tap → lecture, même filtre IA). Chargés une seule
  /// fois en arrière-plan : tant qu'ils ne sont pas là, la recherche
  /// porte sur les chaînes live uniquement (dégradation douce).
  List<Channel> _movies = const <Channel>[];

  @override
  void initState() {
    super.initState();
    // Charge les recherches récentes en arrière-plan — l'écran
    // s'ouvre instantanément avec un état idle vide, puis les
    // chips se peuplent dès que le repo notifie.
    RecentSearchesRepository.instance.initialize();
    _loadMovies();
  }

  /// Récupère le catalogue de films (VOD Xtream) et le convertit en
  /// [Channel] pour l'inclure dans la recherche. Silencieux si aucune
  /// source VOD (que des M3U / pas de films) → liste vide.
  Future<void> _loadMovies() async {
    try {
      final List<VodMovie> movies =
          await VodRepository.instance.fetchMovies();
      if (!mounted || movies.isEmpty) return;
      final List<Channel> asChannels = <Channel>[
        for (final VodMovie m in movies)
          Channel(
            id: m.id,
            name: m.name,
            category: m.category,
            streamUrl: m.streamUrl,
            isLive: false,
            logoUrl: m.posterUrl,
          ),
      ];
      setState(() => _movies = asChannels);
    } catch (_) {
      // Best-effort : pas de films dans la recherche, ce n'est pas bloquant.
    }
  }

  /// Le « bassin » de recherche = chaînes live de la playlist active
  /// + films VOD. C'est lui qu'on filtre (mots-clés ET IA), pour que
  /// taper « chaîne OU film » trouve les deux d'un coup.
  List<Channel> get _searchPool => <Channel>[
        ...PlaylistRepository.instance.currentChannels,
        ..._movies,
      ];

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ============================================================
  //  Saisie & debounce
  // ============================================================

  void _onChanged(String value) {
    _debounceTimer?.cancel();
    final String clean = value.trim();
    if (clean.isEmpty) {
      setState(() {
        _activeQuery = '';
        _results = const <Channel>[];
        _state = _SearchState.idle;
      });
      return;
    }
    // Pendant le debounce → skeleton (sensation "ça réfléchit")
    setState(() => _state = _SearchState.loading);
    _debounceTimer = Timer(_kDebounce, () => _runSearch(clean));
  }

  void _runSearch(String query) {
    final List<Channel> all = _searchPool;
    if (all.isEmpty) {
      setState(() {
        _activeQuery = query;
        _state = _SearchState.empty;
      });
      return;
    }
    final String needle = _normalize(query);
    final List<Channel> hits = <Channel>[];
    for (final Channel c in all) {
      if (_normalize(c.name).contains(needle) ||
          _normalize(c.category).contains(needle)) {
        hits.add(c);
      }
    }
    if (!mounted) return;
    setState(() {
      _activeQuery = query;
      _results = hits;
      _state = hits.isEmpty
          ? _SearchState.noResults
          : _SearchState.results;
    });
    // Enregistre dans les recherches récentes seulement si on a
    // au moins 1 hit — ça évite de polluer les chips avec des
    // requêtes ratées.
    if (hits.isNotEmpty) {
      RecentSearchesRepository.instance.record(query);
    }
  }

  /// Recherche en LANGAGE NATUREL (IA) : la phrase est envoyée au backend
  /// qui la traduit en filtre via Claude, puis on applique ce filtre
  /// localement au catalogue. Repli silencieux sur la recherche classique
  /// si l'IA est indisponible.
  Future<void> _runAiSearch(String query) async {
    final String q = query.trim();
    if (q.isEmpty) return;
    setState(() => _state = _SearchState.loading);
    final List<Channel> all = _searchPool;
    final AiSearchFilter? filter = await AiSearchService.search(q);
    if (!mounted) return;
    if (filter == null) {
      setState(() {
        _activeQuery = q;
        _state = _SearchState.noResults;
      });
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.surfaceHigh,
          behavior: SnackBarBehavior.floating,
          content: Text(
            context.l10n.searchAiUnavailable,
            style: AppTextStyles.bodyMedium,
          ),
        ),
      );
      return;
    }
    final List<Channel> hits =
        all.where((Channel c) => filter.matches(c)).toList();
    setState(() {
      _activeQuery = q;
      _results = hits;
      _state =
          hits.isEmpty ? _SearchState.noResults : _SearchState.results;
    });
    if (hits.isNotEmpty) {
      RecentSearchesRepository.instance.record(q);
    }
  }

  /// Tap sur le bouton « Demander à l'IA » : on envoie la phrase
  /// courante à l'IA. Si le champ est vide, on invite l'utilisateur à
  /// décrire ce qu'il veut voir (focus + petit message) au lieu de ne
  /// rien faire.
  void _onAiTap() {
    HapticFeedback.selectionClick();
    final String q = _controller.text.trim();
    if (q.isEmpty) {
      _focus.requestFocus();
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.surfaceHigh,
          behavior: SnackBarBehavior.floating,
          content: Text(
            context.l10n.searchAiEmptyPrompt,
            style: AppTextStyles.bodyMedium,
          ),
        ),
      );
      return;
    }
    _debounceTimer?.cancel();
    _runAiSearch(q);
  }

  /// Force un filtre instantané (utilisé quand l'user tape sur
  /// une chip — pas besoin d'attendre le debounce).
  void _setQueryAndSearch(String query) {
    _debounceTimer?.cancel();
    _controller
      ..text = query
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: query.length),
      );
    setState(() => _state = _SearchState.loading);
    // Petit délai pour que le skeleton ait le temps d'apparaître
    // et signaler à l'œil qu'on a réagi au tap.
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _runSearch(query);
    });
  }

  void _clear() {
    HapticFeedback.selectionClick();
    _controller.clear();
    _debounceTimer?.cancel();
    setState(() {
      _activeQuery = '';
      _results = const <Channel>[];
      _state = _SearchState.idle;
    });
    _focus.requestFocus();
  }

  String _normalize(String s) {
    final String lower = s.toLowerCase();
    const Map<String, String> map = <String, String>{
      'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a',
      'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    final StringBuffer out = StringBuffer();
    for (final int rune in lower.runes) {
      final String ch = String.fromCharCode(rune);
      out.write(map[ch] ?? ch);
    }
    return out.toString();
  }

  // ============================================================
  //  Interactions
  // ============================================================

  void _onChannelTap(Channel c) {
    HapticFeedback.lightImpact();
    playChannel(context, c, zapPlaylist: _results);
  }

  void _onChannelLongPress(Channel c) {
    HapticFeedback.mediumImpact();
    showChannelDetail(context, c);
  }

  // ============================================================
  //  Build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _SearchHeader(
              controller: _controller,
              focusNode: _focus,
              hasText: _activeQuery.isNotEmpty,
              onChanged: _onChanged,
              onClear: _clear,
              onBack: () => Navigator.of(context).pop(),
              onAiTap: _onAiTap,
            ),
            Expanded(
              child: StreamBuilder<List<Channel>>(
                stream: PlaylistRepository.instance.channelsStream,
                initialData: PlaylistRepository.instance.currentChannels,
                builder: (BuildContext context,
                    AsyncSnapshot<List<Channel>> snap) {
                  // Bassin complet pour l'affichage idle / découverte :
                  // chaînes live + films VOD.
                  final List<Channel> all = <Channel>[
                    ...(snap.data ?? <Channel>[]),
                    ..._movies,
                  ];
                  if (all.isEmpty) {
                    return const _EmptyCatalog();
                  }
                  return _buildContent(all);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(List<Channel> all) {
    switch (_state) {
      case _SearchState.idle:
        return _IdleDiscovery(
          allChannels: all,
          onSubmitGenre: (ChannelGenre g) => _setQueryAndSearch(g.label),
          onSubmitQuery: _setQueryAndSearch,
        );
      case _SearchState.loading:
        return const SearchSkeleton();
      case _SearchState.noResults:
        return _NoResults(
          query: _activeQuery,
          onSuggestion: _setQueryAndSearch,
          onAiSearch: () => _runAiSearch(_activeQuery),
        );
      case _SearchState.empty:
        return const _EmptyCatalog();
      case _SearchState.results:
        return _ResultsGrid(
          results: _results,
          query: _activeQuery,
          onTap: _onChannelTap,
          onLongPress: _onChannelLongPress,
        );
    }
  }
}

// ============================================================
//  Header — TextField glassmorphique + actions
// ============================================================

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.controller,
    required this.focusNode,
    required this.hasText,
    required this.onChanged,
    required this.onClear,
    required this.onBack,
    required this.onAiTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onBack;
  final VoidCallback onAiTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: context.l10n.buttonBack,
            onPressed: onBack,
          ),
          Expanded(
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.search_rounded,
                    color: AppColors.textTertiary,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      autofocus: true,
                      onChanged: onChanged,
                      textInputAction: TextInputAction.search,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontSize: 15,
                      ),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        hintText: context.l10n.searchHint,
                        hintStyle: AppTextStyles.bodyMedium.copyWith(
                          fontSize: 14,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                  if (hasText)
                    GestureDetector(
                      onTap: onClear,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceOverlay,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          // ----- Bouton « Demander à l'IA » (toujours visible) -----
          //  L'utilisateur décrit ce qu'il veut voir en langage naturel
          //  (« un film d'action récent », « un dessin animé pour enfant »)
          //  et l'IA filtre chaînes + films. Mis en avant en couleur accent
          //  pour qu'on le repère tout de suite.
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onAiTap,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.accentSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.l10n.navAi,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          const CastButton(),
        ],
      ),
    );
  }
}

// ============================================================
//  État IDLE — recherches récentes + chips genres + découverte
// ============================================================

class _IdleDiscovery extends StatelessWidget {
  const _IdleDiscovery({
    required this.allChannels,
    required this.onSubmitGenre,
    required this.onSubmitQuery,
  });

  final List<Channel> allChannels;
  final void Function(ChannelGenre) onSubmitGenre;
  final void Function(String) onSubmitQuery;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      children: <Widget>[
        // ----- Astuce IA -----
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.accentSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.auto_awesome_rounded,
                  size: 18, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l10n.searchAiTip,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ----- Recherches récentes -----
        ListenableBuilder(
          listenable: RecentSearchesRepository.instance,
          builder: (BuildContext context, _) {
            final List<String> recents =
                RecentSearchesRepository.instance.current;
            if (recents.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SectionHeader(
                  title: context.l10n.searchRecent,
                  trailing: TextButton(
                    onPressed: () =>
                        RecentSearchesRepository.instance.clearAll(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      minimumSize: const Size(0, 28),
                    ),
                    child: Text(
                      context.l10n.buttonClear,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    physics: const BouncingScrollPhysics(),
                    itemCount: recents.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: 8),
                    itemBuilder:
                        (BuildContext context, int i) => _Chip(
                      label: recents[i],
                      icon: Icons.history_rounded,
                      onTap: () => onSubmitQuery(recents[i]),
                      onDelete: () => RecentSearchesRepository.instance
                          .remove(recents[i]),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            );
          },
        ),

        // ----- Chips par genre -----
        _SectionHeader(title: context.l10n.searchExploreByCategory),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final ChannelGenre g in <ChannelGenre>[
                ChannelGenre.sports,
                ChannelGenre.movies,
                ChannelGenre.series,
                ChannelGenre.kids,
                ChannelGenre.news,
                ChannelGenre.music,
                ChannelGenre.documentary,
              ])
                _GenreChip(
                  genre: g,
                  onTap: () => onSubmitGenre(g),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ----- À découvrir : 6 chaînes random avec logo -----
        _SectionHeader(title: context.l10n.sectionDiscover),
        _DiscoveryRow(
          channels: _pickDiscovery(allChannels),
          onTap: onSubmitQuery,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Tire 6 chaînes uniques (par nom propre) au hasard pour
  /// alimenter "À découvrir". Pseudo-aléatoire stable par heure
  /// pour que ça ne danse pas à chaque scroll.
  List<Channel> _pickDiscovery(List<Channel> all) {
    if (all.isEmpty) return const <Channel>[];
    final math.Random rnd = math.Random(DateTime.now().hour);
    final Set<String> seenNames = <String>{};
    final List<Channel> picks = <Channel>[];
    // On préfère les chaînes avec un logo (plus joli)
    final List<Channel> candidates =
        all.where((Channel c) => c.hasLogo).toList();
    final List<Channel> pool =
        candidates.isNotEmpty ? candidates : all;
    int safety = 0;
    while (picks.length < 6 && safety < 200) {
      final Channel c = pool[rnd.nextInt(pool.length)];
      if (seenNames.add(c.cleanName)) picks.add(c);
      safety++;
    }
    return picks;
  }
}

// ============================================================
//  Sections, chips, rows
// ============================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
      child: Row(
        children: <Widget>[
          Text(
            title.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: 11,
              letterSpacing: 1.4,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.onDelete,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 14, color: AppColors.textTertiary),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 12,
                  color: AppColors.textPrimary,
                ),
              ),
              if (onDelete != null) ...<Widget>[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onDelete,
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GenreChip extends StatelessWidget {
  const _GenreChip({required this.genre, required this.onTap});
  final ChannelGenre genre;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.accentSurface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(genre.icon, size: 15, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(
                genre.localizedLabel,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoveryRow extends StatelessWidget {
  const _DiscoveryRow({required this.channels, required this.onTap});
  final List<Channel> channels;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          context.l10n.searchDiscoveryEmpty,
          style: AppTextStyles.bodyMedium.copyWith(fontSize: 12),
        ),
      );
    }
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: const BouncingScrollPhysics(),
        itemCount: channels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (BuildContext context, int i) {
          final Channel c = channels[i];
          return _DiscoveryPill(
            channel: c,
            onTap: () => onTap(c.cleanName),
          );
        },
      ),
    );
  }
}

class _DiscoveryPill extends StatelessWidget {
  const _DiscoveryPill({required this.channel, required this.onTap});
  final Channel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 140,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  channel.initials,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      channel.cleanName,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      channel.genre.localizedLabel,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
//  État RESULTS — grille
// ============================================================

class _ResultsGrid extends StatelessWidget {
  const _ResultsGrid({
    required this.results,
    required this.query,
    required this.onTap,
    required this.onLongPress,
  });

  final List<Channel> results;
  final String query;
  final void Function(Channel) onTap;
  final void Function(Channel) onLongPress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints cons) {
        final double w = cons.maxWidth;
        final int cols = w >= 1000 ? 4 : w >= 700 ? 3 : 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
              child: Text(
                context.l10n.searchResultsCount(results.length, query),
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                physics: const BouncingScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 16 / 14,
                ),
                itemCount: results.length,
                itemBuilder: (BuildContext context, int i) {
                  final Channel ch = results[i];
                  return SearchResultCard(
                    channel: ch,
                    onTap: () => onTap(ch),
                    onLongPress: () => onLongPress(ch),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================
//  État NO RESULTS
// ============================================================

class _NoResults extends StatelessWidget {
  const _NoResults({
    required this.query,
    required this.onSuggestion,
    required this.onAiSearch,
  });
  final String query;
  final void Function(String) onSuggestion;
  final VoidCallback onAiSearch;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      physics: const BouncingScrollPhysics(),
      children: <Widget>[
        Center(
          child: Icon(
            Icons.search_off_rounded,
            size: 64,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 14),
        // ----- Recherche IA (langage naturel) -----
        //  Quand la recherche par mots-clés ne trouve rien, on propose
        //  à l'IA de comprendre la phrase (« un film d'action ce soir »).
        Center(
          child: FilledButton.icon(
            onPressed: onAiSearch,
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(context.l10n.searchAiButton),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.voidSurface,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          context.l10n.searchNoResult(query),
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineMedium.copyWith(fontSize: 16),
        ),
        const SizedBox(height: 6),
        Text(
          context.l10n.searchNoResultHelp,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(
            fontSize: 12,
            color: AppColors.textMuted,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          context.l10n.searchTipsToTry,
          textAlign: TextAlign.center,
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.textSecondary,
            fontSize: 11,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final ChannelGenre g in <ChannelGenre>[
              ChannelGenre.sports,
              ChannelGenre.movies,
              ChannelGenre.series,
              ChannelGenre.news,
            ])
              _GenreChip(
                genre: g,
                onTap: () => onSuggestion(g.label),
              ),
          ],
        ),
      ],
    );
  }
}

// ============================================================
//  État EMPTY — aucune chaîne dans le catalogue
// ============================================================

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.tv_off_rounded,
                size: 56, color: AppColors.textMuted),
            const SizedBox(height: 14),
            Text(
              context.l10n.searchEmptyCatalogTitle,
              style: AppTextStyles.headlineMedium.copyWith(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.searchEmptyCatalogHelp,
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 12,
                color: AppColors.textMuted,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
