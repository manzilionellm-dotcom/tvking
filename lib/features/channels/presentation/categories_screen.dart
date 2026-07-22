// =========================================================
//  categories_screen.dart — Liste de toutes les catégories
// =========================================================
//  Sur l'accueil on n'affiche qu'UNE catégorie phare (la
//  plus représentée). Cet écran liste TOUTES les catégories
//  trouvées dans la playlist, avec le nombre de chaînes par
//  catégorie, et un tap → ChannelsGridScreen filtré.
//
//  Tri : par nombre de chaînes décroissant (le + populaire
//  en premier — comportement Spotify/Netflix typique).
//
//  RÉORGANISATION PREMIUM (comme sur la TV) : APPUI LONG sur une carte →
//  elle « rebondit » (ressort) et affiche des chevrons dorés ▲ ▼ (+ ✓) pour
//  la faire MONTER / DESCENDRE. L'ordre est PERSISTÉ (CategoryOrderStore) et
//  partagé partout (téléphone + TV). Le bouton « Réorganiser » (glisser-
//  déposer plein écran) reste disponible en complément.
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../playlists/data/playlist_repository.dart';
import '../data/category_order_store.dart';
import '../domain/channel.dart';
import 'category_order_screen.dart';
import 'channels_grid_screen.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  /// Catégorie actuellement « saisie » pour être déplacée (null = aucune).
  String? _reorderName;

  Future<void> _openReorder(
      BuildContext context, List<String> currentOrder) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CategoryOrderScreen(categories: currentOrder),
      ),
    );
  }

  void _beginReorder(String name) {
    HapticFeedback.mediumImpact();
    setState(() => _reorderName = name);
  }

  void _endReorder() {
    if (_reorderName == null) return;
    HapticFeedback.selectionClick();
    setState(() => _reorderName = null);
  }

  /// Déplace la catégorie à [index] de [dir] rang (−1 = monter, +1 = descendre)
  /// dans [orderedKeys], puis PERSISTE le nouvel ordre complet. Le store notifie
  /// → le ListenableBuilder redessine avec le nouvel ordre.
  void _move(List<String> orderedKeys, int index, int dir) {
    final int next = index + dir;
    if (next < 0 || next >= orderedKeys.length) return;
    final List<String> reordered = List<String>.from(orderedKeys);
    final String tmp = reordered[index];
    reordered[index] = reordered[next];
    reordered[next] = tmp;
    HapticFeedback.selectionClick();
    // ignore: discarded_futures
    CategoryOrderStore.instance.setOrder(reordered);
  }

  @override
  Widget build(BuildContext context) {
    // Charge l'ordre personnalisé (idempotent) ; le ListenableBuilder
    // ci-dessous redessine dès qu'il est prêt ou modifié.
    // ignore: discarded_futures
    CategoryOrderStore.instance.ensureLoaded();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(context.l10n.categoriesTitle),
      ),
      body: ListenableBuilder(
        listenable: CategoryOrderStore.instance,
        builder: (BuildContext context, Widget? _) {
          return StreamBuilder<List<Channel>>(
            stream: PlaylistRepository.instance.channelsStream,
            initialData: PlaylistRepository.instance.currentChannels,
            builder:
                (BuildContext context, AsyncSnapshot<List<Channel>> snap) {
              final List<Channel> channels = snap.data ?? <Channel>[];
              if (channels.isEmpty) {
                return Center(
                  child: Text(
                    context.l10n.categoriesEmpty,
                    style: AppTextStyles.bodyMedium,
                  ),
                );
              }

              // Regroupe par catégorie
              final Map<String, List<Channel>> byCat =
                  <String, List<Channel>>{};
              for (final Channel c in channels) {
                byCat.putIfAbsent(c.category, () => <Channel>[]).add(c);
              }
              List<MapEntry<String, List<Channel>>> entries = byCat.entries
                  .toList()
                // Tri PAR DÉFAUT : nombre de chaînes décroissant.
                ..sort((MapEntry<String, List<Channel>> a,
                        MapEntry<String, List<Channel>> b) =>
                    b.value.length.compareTo(a.value.length));
              // ORDRE PERSONNALISÉ de l'utilisateur appliqué PAR-DESSUS :
              // catégories classées d'abord, le reste ensuite.
              entries = CategoryOrderStore.instance.applyOrder(
                  entries, (MapEntry<String, List<Channel>> e) => e.key);
              final List<String> orderedKeys = entries
                  .map((MapEntry<String, List<Channel>> e) => e.key)
                  .toList();

              return Column(
                children: <Widget>[
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                      child: TextButton.icon(
                        onPressed: () => _openReorder(context, orderedKeys),
                        icon: const Icon(Icons.swap_vert_rounded, size: 20),
                        label: Text(context.l10n.categoryOrderEdit),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      physics: const BouncingScrollPhysics(),
                      itemCount: entries.length,
                      separatorBuilder: (BuildContext _, int __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final MapEntry<String, List<Channel>> entry =
                            entries[index];
                        final bool reordering = entry.key == _reorderName;
                        return _CategoryTile(
                          name: entry.key,
                          count: entry.value.length,
                          channels: entry.value,
                          reordering: reordering,
                          canMoveUp: reordering && index > 0,
                          canMoveDown:
                              reordering && index < entries.length - 1,
                          onLongPress: () => _beginReorder(entry.key),
                          onMoveUp: () => _move(orderedKeys, index, -1),
                          onMoveDown: () => _move(orderedKeys, index, 1),
                          onDoneReorder: _endReorder,
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _CategoryTile extends StatefulWidget {
  const _CategoryTile({
    required this.name,
    required this.count,
    required this.channels,
    required this.reordering,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onLongPress,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDoneReorder,
  });

  final String name;
  final int count;
  final List<Channel> channels;
  final bool reordering;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onLongPress;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDoneReorder;

  @override
  State<_CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends State<_CategoryTile>
    with SingleTickerProviderStateMixin {
  // Contrôleur du « rebond » (ressort) joué quand la carte est SAISIE.
  late final AnimationController _bounceCtl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );
  late final Animation<double> _bounce =
      TweenSequence<double>(<TweenSequenceItem<double>>[
    TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.0, end: 1.05)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 28),
    TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.05, end: 0.985)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 26),
    TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0.985, end: 1.02)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 24),
    TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.02, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 22),
  ]).animate(_bounceCtl);

  @override
  void initState() {
    super.initState();
    if (widget.reordering) _bounceCtl.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant _CategoryTile old) {
    super.didUpdateWidget(old);
    if (widget.reordering && !old.reordering) _bounceCtl.forward(from: 0);
  }

  @override
  void dispose() {
    _bounceCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Dégradé déterministe basé sur le nom — chaque catégorie a "sa"
    // dérivée Maison Noir stable. On reste dans la famille accentEmber /
    // surfaces sombres : pas de néons, pas d'arc-en-ciel.
    final int seed = widget.name.hashCode.abs();
    final List<List<Color>> palette = const <List<Color>>[
      <Color>[Color(0xFF9C8359), Color(0xFF0E0B14)],
      <Color>[Color(0xFFB8965E), Color(0xFF16121C)],
      <Color>[Color(0xFFD4B483), Color(0xFF221D2D)],
      <Color>[Color(0xFF8FA8C4), Color(0xFF1C1826)],
      <Color>[Color(0xFFD4A574), Color(0xFF0E0B14)],
      <Color>[Color(0xFF7FB890), Color(0xFF16121C)],
    ];
    final List<Color> gradient = palette[seed % palette.length];
    final bool reordering = widget.reordering;

    final Widget tile = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        // APPUI LONG → on « saisit » la catégorie (rebond + chevrons ▲▼).
        onLongPress: widget.onLongPress,
        onTap: () {
          // En réorganisation, un tap sur la carte = « terminé » ; sinon on
          // ouvre la grille des chaînes de la catégorie.
          if (reordering) {
            widget.onDoneReorder();
            return;
          }
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => ChannelsGridScreen(
                title: widget.name,
                channels: widget.channels,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: reordering
                ? AppColors.royalGoldSurface
                : AppColors.surface.withValues(alpha: 0.7),
            border: Border.all(
              color: reordering
                  ? AppColors.royalGold
                  : Colors.white.withValues(alpha: 0.06),
              width: reordering ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              // Petit carré coloré dégradé
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradient,
                  ),
                ),
                child: Center(
                  child: Text(
                    widget.name.isNotEmpty
                        ? widget.name[0].toUpperCase()
                        : '?',
                    style: AppTextStyles.headlineMedium.copyWith(
                      color: Colors.white,
                      fontSize: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.name,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.channelCount(widget.count),
                      style: AppTextStyles.bodyMedium.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (reordering)
                _ReorderChevrons(
                  canUp: widget.canMoveUp,
                  canDown: widget.canMoveDown,
                  onUp: widget.onMoveUp,
                  onDown: widget.onMoveDown,
                  onDone: widget.onDoneReorder,
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
            ],
          ),
        ),
      ),
    );

    if (!reordering) return tile;
    // Le rebond ne s'anime que pour la carte saisie (coût nul ailleurs).
    return AnimatedBuilder(
      animation: _bounce,
      builder: (BuildContext context, Widget? child) =>
          Transform.scale(scale: _bounce.value, child: child),
      child: tile,
    );
  }
}

/// Chevrons DORÉS ▲ ▼ (+ ✓ terminé) — montent / descendent la catégorie.
/// Grisés quand l'action est impossible (déjà tout en haut / tout en bas).
class _ReorderChevrons extends StatelessWidget {
  const _ReorderChevrons({
    required this.canUp,
    required this.canDown,
    required this.onUp,
    required this.onDown,
    required this.onDone,
  });

  final bool canUp;
  final bool canDown;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _btn(Icons.keyboard_arrow_up_rounded, canUp, onUp),
        _btn(Icons.keyboard_arrow_down_rounded, canDown, onDown),
        _btn(Icons.check_rounded, true, onDone),
      ],
    );
  }

  Widget _btn(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Icon(
          icon,
          size: 28,
          color: enabled
              ? AppColors.royalGold
              : AppColors.royalGold.withValues(alpha: 0.30),
        ),
      ),
    );
  }
}
