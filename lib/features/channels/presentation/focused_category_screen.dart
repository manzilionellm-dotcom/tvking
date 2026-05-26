// =========================================================
//  focused_category_screen.dart — Catégorie focus (Football…)
// =========================================================
//  Écran générique qui prend UN thème (Football, Jeunesse, etc.)
//  et affiche TOUTES les chaînes correspondantes — pas un sous-
//  ensemble par genre, mais un FILTRE TEXTUEL agressif sur les
//  noms + catégories. Puis on REGROUPE par pays.
//
//  Cas d'usage donné par le user :
//    "En catégorie Football, ce sont TOUTES les chaînes de
//     football qui sont dedans. Il voit juste les pays
//     différemment — Bein Sport FR à côté de Bein Sport AR
//     à côté de Sky Sports UK — mais ce sont des footballs."
//
//  Implémentation lean :
//    1. StreamBuilder sur PlaylistRepository.channelsStream
//    2. Filtre case-insensitive sur name+category par mots-clés
//    3. Group by channel.country?.name (fallback "International")
//    4. Une PremiumRow par pays, tri par taille décroissante
//       (le pays le plus fourni en premier) puis "International"
//       à la fin
//
//  Pas de nouvel état, pas de nouveau repository — on consomme
//  ce qui existe déjà.
// =========================================================

import 'dart:collection';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../player/presentation/play_channel.dart';
import '../../playlists/data/playlist_repository.dart';
import '../domain/channel.dart';
import 'widgets/premium_row.dart';

class FocusedCategoryScreen extends StatelessWidget {
  const FocusedCategoryScreen({
    required this.title,
    required this.keywords,
    super.key,
  });

  /// Titre affiché dans l'AppBar (ex. "Football").
  final String title;

  /// Mots-clés à matcher (case-insensitive, OR logique) sur
  /// `channel.name` + `channel.category`. Ex. pour Football :
  /// `['foot', 'soccer', 'bein', 'rmc sport', 'champions', 'ligue']`.
  final List<String> keywords;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(title, style: AppTextStyles.headlineMedium),
      ),
      body: StreamBuilder<List<Channel>>(
        stream: PlaylistRepository.instance.channelsStream,
        initialData: PlaylistRepository.instance.currentChannels,
        builder: (BuildContext context, AsyncSnapshot<List<Channel>> snap) {
          final List<Channel> all = snap.data ?? const <Channel>[];
          final List<Channel> matched = _filter(all);

          if (matched.isEmpty) {
            return _EmptyState(title: title);
          }

          final LinkedHashMap<String, List<Channel>> byCountry =
              _groupByCountry(matched);

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: <Widget>[
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverToBoxAdapter(
                child: _ResultsHeader(
                  total: matched.length,
                  countries: byCountry.length,
                ),
              ),
              for (final MapEntry<String, List<Channel>> entry
                  in byCountry.entries)
                SliverToBoxAdapter(
                  child: PremiumRow(
                    title: entry.key,
                    subtitle: '${entry.value.length} chaînes',
                    channels: entry.value,
                    onChannelTap: (Channel ch) => playChannel(context, ch),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          );
        },
      ),
    );
  }

  List<Channel> _filter(List<Channel> all) {
    final List<String> lower = keywords
        .map((String k) => k.toLowerCase())
        .toList(growable: false);
    return all
        .where((Channel ch) {
          final String hay =
              '${ch.name} ${ch.category}'.toLowerCase();
          for (final String k in lower) {
            if (hay.contains(k)) return true;
          }
          return false;
        })
        .toList(growable: false);
  }

  /// Regroupe par pays. Tri : pays avec le plus de chaînes d'abord,
  /// "International" (= pays inconnu) toujours en dernier.
  LinkedHashMap<String, List<Channel>> _groupByCountry(
    List<Channel> chs,
  ) {
    const String kInternational = 'International';
    final Map<String, List<Channel>> raw = <String, List<Channel>>{};
    for (final Channel ch in chs) {
      final String key = ch.country?.name ?? kInternational;
      raw.putIfAbsent(key, () => <Channel>[]).add(ch);
    }
    // Tri stable : par count desc, puis nom asc, "International" en fin
    final List<MapEntry<String, List<Channel>>> sorted = raw.entries.toList()
      ..sort((MapEntry<String, List<Channel>> a,
          MapEntry<String, List<Channel>> b) {
        final bool aLast = a.key == kInternational;
        final bool bLast = b.key == kInternational;
        if (aLast && !bLast) return 1;
        if (!aLast && bLast) return -1;
        final int byCount = b.value.length.compareTo(a.value.length);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });
    return LinkedHashMap<String, List<Channel>>.fromEntries(sorted);
  }
}

// ============================================================
//  Composants
// ============================================================

class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({required this.total, required this.countries});

  final int total;
  final int countries;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Text(
        '$total chaînes · $countries pays',
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.textMuted,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.sports_soccer_outlined,
              size: 48,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'Aucune chaîne $title trouvée dans tes playlists.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
