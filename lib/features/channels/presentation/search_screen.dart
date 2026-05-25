// =========================================================
//  search_screen.dart — Recherche instantanée dans les chaînes
// =========================================================
//  Recherche en mémoire (toutes les chaînes sont déjà
//  chargées par le repository). Pour 5000 chaînes c'est
//  instantané ; au-delà on passerait sur SQL FTS5.
//
//  Recherche : nom + catégorie (sans accents, casse ignorée).
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../domain/channel.dart';
import 'widgets/channel_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Normalise une chaîne pour la recherche : minuscules + sans
  /// accents (les utilisateurs ne pensent pas toujours aux accents).
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: AppTextStyles.bodyLarge,
          decoration: InputDecoration(
            hintText: 'Rechercher une chaîne...',
            hintStyle: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textMuted,
            ),
            border: InputBorder.none,
          ),
          onChanged: (String v) => setState(() => _query = v),
        ),
        actions: <Widget>[
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: StreamBuilder<List<Channel>>(
        stream: PlaylistRepository.instance.channelsStream,
        initialData: const <Channel>[],
        builder: (BuildContext context, AsyncSnapshot<List<Channel>> snap) {
          final List<Channel> all = snap.data ?? <Channel>[];
          if (all.isEmpty) {
            return Center(
              child: Text(
                'Aucune chaîne — ajoute d\'abord une playlist.',
                style: AppTextStyles.bodyMedium,
              ),
            );
          }

          final String needle = _normalize(_query.trim());
          if (needle.isEmpty) {
            return _hint();
          }

          final List<Channel> results = all
              .where((Channel c) =>
                  _normalize(c.name).contains(needle) ||
                  _normalize(c.category).contains(needle))
              .toList();

          if (results.isEmpty) {
            return Center(
              child: Text(
                'Aucun résultat pour "$_query"',
                style: AppTextStyles.bodyMedium,
              ),
            );
          }

          return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints cons) {
              final double w = cons.maxWidth;
              final int cols = w >= 1000 ? 4 : w >= 700 ? 3 : 2;
              return GridView.builder(
                padding: const EdgeInsets.all(16),
                physics: const BouncingScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 16 / 11,
                ),
                itemCount: results.length,
                itemBuilder: (BuildContext context, int index) {
                  final Channel ch = results[index];
                  return ChannelCard(
                    channel: ch,
                    onTap: () => _onTap(ch),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _onTap(Channel channel) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        backgroundColor: AppColors.surfaceHigh,
        action: SnackBarAction(
          label: '♥',
          textColor: AppColors.accentPink,
          onPressed: () => FavoritesRepository.instance.toggle(channel.id),
        ),
        content: Text(
          '${channel.name} — lecteur à brancher (Phase 1.3)',
          style: AppTextStyles.bodyLarge,
        ),
      ),
    );
  }

  Widget _hint() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.search, size: 56, color: AppColors.textMuted),
          const SizedBox(height: 14),
          Text(
            'Tape pour chercher dans tes chaînes',
            style: AppTextStyles.bodyMedium,
          ),
        ],
      ),
    );
  }
}
