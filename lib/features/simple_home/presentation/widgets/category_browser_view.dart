// =========================================================
//  category_browser_view.dart — Navigation par CATÉGORIES
// =========================================================
//  Le client navigue EXACTEMENT comme dans sa playlist : on respecte
//  les catégories d'origine (`group-title` M3U / `category_name`
//  Xtream), sans aucune reclassification maison. Deux niveaux, propres
//  et évidents (façon TiviMate) :
//
//    Niveau 1 — LISTE DES CATÉGORIES
//      « FR| FRANCE SPORT VIP » … 161
//      « FR| CINÉMA HD/4K »     …  40
//      « IT| AMAZON PRIME PP. » …   6
//      (le chiffre = nombre de chaînes dans la catégorie)
//
//    Niveau 2 — LISTE DES CHAÎNES de la catégorie choisie
//      logo + nom propre, on tape → lecture.
//
//  Tri des catégories : alphabétique (ça regroupe naturellement les
//  préfixes pays « FR| … », « IT| … » ensemble, comme sur ta TV).
//  Virtualisé (ListView.builder) → fluide même avec des milliers de
//  catégories/chaînes. Aucune dépendance au cast.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../channels/domain/channel.dart';
import '../../../country_home/presentation/widgets/channel_logo.dart';
import '../../../player/presentation/play_channel.dart';

class CategoryBrowserView extends StatefulWidget {
  const CategoryBrowserView({super.key, required this.channels});

  /// Toutes les chaînes de la playlist active (déjà filtrées par flavor
  /// au niveau du repository — ex. Red Room ne reçoit que l'adulte).
  final List<Channel> channels;

  @override
  State<CategoryBrowserView> createState() => _CategoryBrowserViewState();
}

class _CategoryBrowserViewState extends State<CategoryBrowserView> {
  /// Catégorie ouverte (`null` = on est sur la liste des catégories).
  String? _selected;

  /// Libellé utilisé pour les chaînes sans catégorie dans la playlist.
  static const String _kNoCategory = 'Autres';

  /// Regroupe les chaînes par catégorie BRUTE (group-title) en
  /// conservant l'ordre d'apparition à l'intérieur de chaque catégorie.
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

  // ----- Niveau 1 : la liste des catégories -----
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
    // Tri alphabétique insensible à la casse → regroupe les préfixes
    // pays ensemble (« FR| … » puis « IT| … »), comme sur ta TV.
    final List<String> cats = grouped.keys.toList()
      ..sort((String a, String b) =>
          a.toLowerCase().compareTo(b.toLowerCase()));

    return ListView.separated(
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
