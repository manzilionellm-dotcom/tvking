// =========================================================
//  channel_card.dart — Card paysage pour les grilles
// =========================================================
//  Refonte Phase 1.4 :
//
//    AVANT : fond multicolore aléatoire + initiales géantes
//    APRÈS : card sombre élégante + logo de chaîne centré
//
//  Utilisé par :
//    - `ChannelsGridScreen` (Voir tout, Catégorie, Recherche...)
//    - `FavoritesScreen`
//    - Tout endroit qui affiche une grille de chaînes
//
//  Ratio 16:11 pour bien afficher un logo sans le déformer
//  tout en gardant une présence visuelle correcte.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../playlists/data/favorites_repository.dart';
import '../../domain/channel.dart';
import 'channel_logo.dart';

class ChannelCard extends StatefulWidget {
  const ChannelCard({
    required this.channel,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  final Channel channel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<ChannelCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final Channel ch = widget.channel;

    return Focus(
      onFocusChange: (bool f) => setState(() => _focused = f),
      child: MouseRegion(
        onEnter: (_) => setState(() => _focused = true),
        onExit: (_) => setState(() => _focused = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            transform: _focused
                ? (Matrix4.identity()..scale(1.03))
                : Matrix4.identity(),
            transformAlignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: AppColors.surface,
              border: Border.all(
                color: _focused ? AppColors.accent : AppColors.border,
                width: _focused ? 1.5 : 1,
              ),
              boxShadow: _focused
                  ? <BoxShadow>[
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.2),
                        blurRadius: 18,
                      ),
                    ]
                  : <BoxShadow>[],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: <Widget>[
                  // ----- Logo centré -----
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 56),
                      child: ChannelLogo(
                        channel: ch,
                        size: ChannelLogoSize.medium,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),

                  // ----- Bandeau bas opaque : nom + meta -----
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Colors.transparent,
                            AppColors.background.withValues(alpha: 0.92),
                          ],
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            ch.cleanName,
                            style: AppTextStyles.bodyLarge.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: <Widget>[
                              Icon(
                                ch.genre.icon,
                                size: 10,
                                color: AppColors.textMuted,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  ch.genre.label,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    fontSize: 10,
                                    color: AppColors.textMuted,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (ch.country != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Text(
                                    ch.country!.flag,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ----- Badge LIVE haut-gauche -----
                  if (ch.isLive)
                    const Positioned(
                      top: 10,
                      left: 10,
                      child: _LivePill(),
                    ),

                  // ----- Badge qualité haut-droite -----
                  if (ch.quality != ChannelQuality.sd)
                    Positioned(
                      top: 10,
                      right: 38,
                      child: ChannelQualityBadge(quality: ch.quality),
                    ),

                  // ----- Bouton favori haut-droite -----
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _FavoriteToggle(channelId: ch.id),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.live,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'LIVE',
        style: AppTextStyles.labelSmall.copyWith(
          color: Colors.white,
          fontSize: 9,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _FavoriteToggle extends StatelessWidget {
  const _FavoriteToggle({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Set<String>>(
      stream: FavoritesRepository.instance.favoritesStream,
      initialData: FavoritesRepository.instance.current,
      builder: (BuildContext context, AsyncSnapshot<Set<String>> snap) {
        final bool isFav = (snap.data ?? <String>{}).contains(channelId);
        return IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: Icon(
            isFav ? Icons.favorite : Icons.favorite_outline,
            color: isFav ? AppColors.accent : Colors.white,
            size: 16,
          ),
          onPressed: () => FavoritesRepository.instance.toggle(channelId),
        );
      },
    );
  }
}
