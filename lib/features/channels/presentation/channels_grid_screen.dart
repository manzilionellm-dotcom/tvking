// =========================================================
//  channels_grid_screen.dart — Liste complète de chaînes
// =========================================================
//  Écran réutilisable affichant une grille verticale de
//  chaînes. Utilisé pour :
//    - "Voir tout" depuis n'importe quelle rangée d'accueil
//    - Liste d'une catégorie ("Sport", "Cinéma", ...)
//    - Liste des favoris
//    - Résultats de recherche
//
//  L'écran prend une liste de chaînes en paramètre (le filtre
//  est fait par l'appelant). Lui se contente d'afficher.
//
//  Performances : `GridView.builder` (lazy) — ne crée que les
//  vignettes visibles. Marche jusqu'à 5000+ chaînes sans lag.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../cast/presentation/cast_button.dart';
import '../../player/presentation/play_channel.dart';
import '../domain/channel.dart';
import 'widgets/channel_card.dart';

class ChannelsGridScreen extends StatelessWidget {
  const ChannelsGridScreen({
    required this.title,
    required this.channels,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Channel> channels;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: AppTextStyles.headlineMedium.copyWith(fontSize: 18),
            ),
            Text(
              subtitle ?? '${channels.length} chaînes',
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        actions: const <Widget>[
          CastButton(),
          SizedBox(width: 6),
        ],
      ),
      body: channels.isEmpty
          ? _buildEmpty()
          : LayoutBuilder(
              builder: (BuildContext context, BoxConstraints cons) {
                final double w = cons.maxWidth;
                final int cols = w >= 1400
                    ? 5
                    : w >= 1000
                        ? 4
                        : w >= 700
                            ? 3
                            : 2;
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 16 / 11,
                  ),
                  itemCount: channels.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Channel ch = channels[index];
                    return ChannelCard(
                      channel: ch,
                      onTap: () => _onChannelTap(context, ch),
                    );
                  },
                );
              },
            ),
    );
  }

  void _onChannelTap(BuildContext context, Channel channel) {
    playChannel(context, channel);
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.tv_off_rounded,
              size: 56,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              'Aucune chaîne ici',
              style: AppTextStyles.headlineMedium.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              'Ajoute une playlist ou ajuste tes filtres.',
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
