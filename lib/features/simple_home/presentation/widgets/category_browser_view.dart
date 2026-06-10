// =========================================================
//  category_browser_view.dart — Navigation par CATÉGORIES
// =========================================================
//  Le client navigue EXACTEMENT comme dans sa playlist : on respecte
//  les catégories d'origine (`group-title` M3U / `category_name`
//  Xtream) ET LEUR ORDRE D'ORIGINE — aucune reclassification ni tri
//  maison. Si le M3U commence par l'Afrique, l'app commence par
//  l'Afrique. Trois niveaux, propres et évidents (façon TiviMate) :
//
//    Niveau 0 — FILTRES (barre du haut)
//      « Tout · TV · Films · Séries · Adultes »
//      Sépare proprement le direct, le cinéma, les séries et l'adulte
//      (détection auto via ChannelClassifier). La barre n'affiche que
//      les onglets réellement présents dans la playlist.
//
//    Niveau 1 — LISTE DES CATÉGORIES (dans l'ordre de la playlist)
//      « FR| FRANCE SPORT VIP » … 161
//      « FR| CINÉMA HD/4K »     …  40
//      (le chiffre = nombre de chaînes dans la catégorie)
//
//    Niveau 2 — LISTE DES CHAÎNES de la catégorie choisie
//      logo + nom propre, on tape → lecture.
//
//  Virtualisé (ListView.builder) → fluide même avec des milliers de
//  catégories/chaînes. Aucune dépendance au cast.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../channels/domain/channel.dart';
import '../../../country_home/presentation/widgets/channel_logo.dart';
import '../../../player/presentation/play_channel.dart';

/// Grands « rayons » de contenu, pour la barre de filtres du haut.
/// Tout ce qui n'est ni film, ni série, ni adulte tombe dans [tv]
/// (le direct : chaînes, sport, info, jeunesse, musique…).
enum _Bucket {
  tv('TV', Icons.live_tv_rounded),
  films('Films', Icons.movie_outlined),
  series('Séries', Icons.video_library_outlined),
  adult('Adultes', Icons.no_adult_content_rounded);

  const _Bucket(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Range une catégorie dans un rayon à partir de son genre détecté.
/// On s'appuie sur le classifier partagé, puis on rattrape le cas très
/// courant des rayons « VOD » (que le classifier ne capte pas) : on les
/// met en Séries s'ils mentionnent une série, sinon en Films.
_Bucket _bucketOf(String category) {
  switch (ChannelClassifier.classifyGenre('', category)) {
    case ChannelGenre.movies:
      return _Bucket.films;
    case ChannelGenre.series:
      return _Bucket.series;
    case ChannelGenre.adult:
      return _Bucket.adult;
    default:
      final String t = category.toLowerCase();
      if (t.contains('vod')) {
        return t.contains('seri') ? _Bucket.series : _Bucket.films;
      }
      return _Bucket.tv;
  }
}

class CategoryBrowserView extends StatefulWidget {
  const CategoryBrowserView({super.key, required this.channels});

  /// Toutes les chaînes de la playlist active, DANS L'ORDRE de la
  /// playlist (le repository les renvoie triées par ordre d'insertion).
  final List<Channel> channels;

  @override
  State<CategoryBrowserView> createState() => _CategoryBrowserViewState();
}

class _CategoryBrowserViewState extends State<CategoryBrowserView> {
  /// Catégorie ouverte (`null` = on est sur la liste des catégories).
  String? _selected;

  /// Filtre de rayon actif (`null` = « Tout »).
  _Bucket? _bucket;

  /// Libellé utilisé pour les chaînes sans catégorie dans la playlist.
  static const String _kNoCategory = 'Autres';

  /// Regroupe les chaînes par catégorie BRUTE (group-title) en
  /// CONSERVANT l'ordre d'apparition — des catégories ET des chaînes.
  /// (LinkedHashMap : l'ordre des clés = ordre de 1re apparition.)
  Map<String, List<Channel>> _grouped() {
    final Map<String, List<Channel>> map = <String, List<Channel>>{};
    for (final Channel c in widget.channels) {
      final String raw = c.category.trim();
      final String cat = raw.isEmpty ? _kNoCategory : raw;
      (map[cat] ??= <Channel>[]).add(c);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, List<Channel>> grouped = _grouped();
    final bool inCategory =
        _selected != null && grouped.containsKey(_selected);

    // On intercepte le « retour » système pour remonter d'abord de la
    // liste des chaînes vers la liste des catégories (au lieu de quitter).
    return PopScope<Object?>(
      canPop: !inCategory,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop && inCategory) setState(() => _selected = null);
      },
      child: inCategory
          ? _buildChannelList(_selected!, grouped[_selected]!)
          : _buildCategoryList(grouped),
    );
  }

  // ----- Niveau 1 : la liste des catégories (+ barre de filtres) -----
  Widget _buildCategoryList(Map<String, List<Channel>> grouped) {
    if (grouped.isEmpty) {
      return Center(
        child: Text(
          'Aucune catégorie dans ta playlist.',
          style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 14, color: AppColors.textSecondary),
        ),
      );
    }

    // ORDRE NATIF : on garde l'ordre d'apparition des catégories dans la
    // playlist (PAS de tri alphabétique). On calcule le rayon de chaque
    // catégorie une seule fois, et les rayons réellement présents.
    final List<String> allCats = grouped.keys.toList();
    final Map<String, _Bucket> catBucket = <String, _Bucket>{
      for (final String c in allCats) c: _bucketOf(c),
    };
    final Set<_Bucket> present =
        catBucket.values.toSet();

    // Catégories visibles selon le filtre actif.
    final List<String> cats = _bucket == null
        ? allCats
        : allCats.where((String c) => catBucket[c] == _bucket).toList();

    return Column(
      children: <Widget>[
        // Barre de filtres : affichée seulement s'il y a plus d'un rayon
        // (sinon elle ne sert à rien). « Tout » + les rayons présents,
        // dans un ordre fixe et lisible.
        if (present.length > 1) _buildFilterBar(present),
        Expanded(
          child: cats.isEmpty
              ? Center(
                  child: Text(
                    'Rien dans ce rayon.',
                    style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 14, color: AppColors.textSecondary),
                  ),
                )
              : ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                  itemCount: cats.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int i) {
                    final String cat = cats[i];
                    return _CategoryRow(
                      title: cat,
                      count: grouped[cat]!.length,
                      onTap: () => setState(() => _selected = cat),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Barre horizontale de filtres (« Tout » + rayons présents).
  Widget _buildFilterBar(Set<_Bucket> present) {
    // Ordre fixe et logique des onglets, on ne garde que ceux présents.
    final List<_Bucket?> tabs = <_Bucket?>[
      null, // « Tout »
      for (final _Bucket b in _Bucket.values)
        if (present.contains(b)) b,
    ];
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int i) {
          final _Bucket? b = tabs[i];
          final bool active = b == _bucket;
          return _FilterChip(
            label: b?.label ?? 'Tout',
            icon: b?.icon ?? Icons.apps_rounded,
            active: active,
            onTap: () => setState(() => _bucket = b),
          );
        },
      ),
    );
  }

  // ----- Niveau 2 : les chaînes d'une catégorie -----
  Widget _buildChannelList(String category, List<Channel> channels) {
    return Column(
      children: <Widget>[
        // En-tête de catégorie : retour + nom + compteur.
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _selected = null),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.arrow_back_rounded, size: 22),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.headlineMedium.copyWith(fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${channels.length}',
                    style: AppTextStyles.labelSmall.copyWith(
                        fontSize: 13, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1, color: AppColors.surface),
        Expanded(
          child: ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 16),
            itemCount: channels.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (BuildContext context, int i) {
              final Channel c = channels[i];
              return _ChannelRow(
                channel: c,
                number: i + 1,
                onTap: () => playChannel(context, c, zapPlaylist: channels),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---- Sous-widgets ----

/// Puce de filtre (rayon). Teintée ember quand active.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color fg = active ? AppColors.accent : AppColors.textSecondary;
    return Material(
      color: active ? AppColors.accentSurface : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? AppColors.accent.withValues(alpha: 0.6)
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.labelSmall.copyWith(
                  fontSize: 13,
                  color: fg,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ligne de catégorie : dossier + nom + pastille « nombre de chaînes ».
class _CategoryRow extends StatelessWidget {
  const _CategoryRow(
      {required this.title, required this.count, required this.onTap});
  final String title;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: <Widget>[
              Icon(Icons.folder_rounded,
                  color: AppColors.accent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyLarge
                      .copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),
              // Pastille compteur.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentSurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: AppTextStyles.labelSmall.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.textTertiary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ligne de chaîne : numéro + logo + nom propre. Tape → lecture.
class _ChannelRow extends StatelessWidget {
  const _ChannelRow(
      {required this.channel, required this.number, required this.onTap});
  final Channel channel;
  final int number;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 30,
                child: Text(
                  '$number',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelSmall.copyWith(
                      fontSize: 12, color: AppColors.textTertiary),
                ),
              ),
              ChannelLogo(channel: channel, size: 44, radius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  channel.cleanName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyLarge.copyWith(fontSize: 14),
                ),
              ),
              const Icon(Icons.play_arrow_rounded,
                  color: AppColors.textTertiary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
