// =========================================================
//  channel_poster.dart — Carte chaîne format "poster"
// =========================================================
//  Version compacte du ChannelCard pour les rangées
//  horizontales scrollables (style Apple TV).
//
//  Différences avec ChannelCard :
//    - Format vertical (poster, ratio 2:3) au lieu de paysage
//    - Plus compact, plus dense
//    - Le nom est SOUS la vignette (pas par-dessus)
//    - Animation de hover/focus plus subtile
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/live_badge.dart';
import '../../../playlists/data/favorites_repository.dart';
import '../../domain/channel.dart';

class ChannelPoster extends StatefulWidget {
  const ChannelPoster({
    required this.channel,
    required this.onTap,
    super.key,
  });

  final Channel channel;
  final VoidCallback onTap;

  @override
  State<ChannelPoster> createState() => _ChannelPosterState();
}

class _ChannelPosterState extends State<ChannelPoster> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final Channel ch = widget.channel;
    final List<Color> gradient = ch.effectiveGradient;

    return Focus(
      onFocusChange: (bool hasFocus) {
        setState(() => _isFocused = hasFocus);
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isFocused = true),
        onExit: (_) => setState(() => _isFocused = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            transform: _isFocused
                ? (Matrix4.identity()..scale(1.06))
                : Matrix4.identity(),
            transformAlignment: Alignment.center,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // ---------- Vignette (le visuel) ----------
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: _isFocused
                          ? <BoxShadow>[
                              BoxShadow(
                                color: gradient.first.withValues(alpha: 0.55),
                                blurRadius: 22,
                                spreadRadius: 1,
                              ),
                            ]
                          : <BoxShadow>[],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        children: <Widget>[
                          // Dégradé de fond
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: gradient,
                              ),
                            ),
                          ),

                          // Initiales centrées
                          Positioned.fill(
                            child: Center(
                              child: Text(
                                ch.initials,
                                style: AppTextStyles.channelInitials.copyWith(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 42,
                                ),
                              ),
                            ),
                          ),

                          // Badge LIVE en haut à gauche
                          if (ch.isLive)
                            const Positioned(
                              top: 8,
                              left: 8,
                              child: LiveBadge(),
                            ),

                          // Coeur favori en haut à droite
                          Positioned(
                            top: 6,
                            right: 6,
                            child: _PosterFavorite(channelId: ch.id),
                          ),

                          // Bordure lumineuse au focus
                          if (_isFocused)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ---------- Texte sous la vignette ----------
                const SizedBox(height: 8),
                Text(
                  ch.name,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  ch.currentProgram ?? ch.category,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Coeur favori discret pour les vignettes Poster (rangées horizontales).
class _PosterFavorite extends StatelessWidget {
  const _PosterFavorite({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Set<String>>(
      stream: FavoritesRepository.instance.favoritesStream,
      initialData: FavoritesRepository.instance.current,
      builder: (BuildContext context, AsyncSnapshot<Set<String>> snap) {
        final bool isFav = (snap.data ?? <String>{}).contains(channelId);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => FavoritesRepository.instance.toggle(channelId),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.5),
              ),
              child: Icon(
                isFav ? Icons.favorite : Icons.favorite_outline,
                color: isFav ? AppColors.accentPink : Colors.white,
                size: 14,
              ),
            ),
          ),
        );
      },
    );
  }
}
