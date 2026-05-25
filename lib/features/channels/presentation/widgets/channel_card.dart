// =========================================================
//  channel_card.dart — Vignette d'une chaîne TV
// =========================================================
//  Élément central de l'écran d'accueil. Pour chaque chaîne,
//  on affiche :
//    - Une "tuile" carrée avec dégradé + initiales (placeholder
//      de logo en attendant les vraies images).
//    - Le nom de la chaîne en gros.
//    - La catégorie en plus petit.
//    - Le programme en cours sur 1 ligne.
//    - Un badge "EN DIRECT" en haut à gauche si applicable.
//
//  Bonus TV : la carte réagit au focus de la télécommande
//  (D-pad) avec un effet "scale + glow" — typique des UIs TV.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/live_badge.dart';
import '../../../playlists/data/favorites_repository.dart';
import '../../domain/channel.dart';

class ChannelCard extends StatefulWidget {
  const ChannelCard({
    required this.channel,
    required this.onTap,
    super.key,
  });

  final Channel channel;
  final VoidCallback onTap;

  @override
  State<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<ChannelCard> {
  /// True quand la carte est sélectionnée par la télécommande TV
  /// ou survolée à la souris (Android TV, web, desktop).
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final Channel ch = widget.channel;

    // Couleurs du dégradé (auto-générées depuis l'id si non fournies).
    final List<Color> gradient = ch.effectiveGradient;

    return Focus(
      // onFocusChange est déclenché quand on arrive sur la carte
      // avec le D-pad d'une télécommande Android TV / Fire TV.
      onFocusChange: (bool hasFocus) {
        setState(() => _isFocused = hasFocus);
      },
      child: MouseRegion(
        // Pour la souris (Android TV avec souris, desktop, web).
        onEnter: (_) => setState(() => _isFocused = true),
        onExit: (_) => setState(() => _isFocused = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            // Animation fluide à chaque changement de focus.
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            // Effet "scale" au focus : la carte grandit légèrement.
            transform: _isFocused
                ? (Matrix4.identity()..scale(1.05))
                : Matrix4.identity(),
            transformAlignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              // Glow lumineux uniquement quand la carte est en focus.
              boxShadow: _isFocused
                  ? <BoxShadow>[
                      BoxShadow(
                        color: gradient.first.withValues(alpha: 0.6),
                        blurRadius: 28,
                        spreadRadius: 2,
                      ),
                    ]
                  : <BoxShadow>[],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: <Widget>[
                  // ---------- Fond dégradé + initiales ---------------
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: gradient,
                      ),
                    ),
                  ),

                  // Initiales gigantesques en transparence.
                  Positioned.fill(
                    child: Align(
                      alignment: const Alignment(0, -0.2),
                      child: Text(
                        ch.initials,
                        style: AppTextStyles.channelInitials.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  ),

                  // ---------- Voile sombre en bas (lisibilité) -------
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.center,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.85),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ---------- Bandeau bas : nom + métadonnées --------
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          ch.name,
                          style: AppTextStyles.headlineMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ch.category,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.accentCyan,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        if (ch.currentProgram != null) ...<Widget>[
                          const SizedBox(height: 6),
                          Text(
                            ch.currentProgram!,
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ---------- Badge "EN DIRECT" en haut à gauche -----
                  if (ch.isLive)
                    const Positioned(
                      top: 12,
                      left: 12,
                      child: LiveBadge(),
                    ),

                  // ---------- Bouton "Favori ♥" en haut à droite -----
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _FavoriteToggle(channelId: ch.id),
                  ),

                  // ---------- Bordure lumineuse au focus -------------
                  if (_isFocused)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
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
      ),
    );
  }
}

/// Petit bouton coeur en haut à droite des vignettes.
/// S'abonne au stream des favoris pour rester synchronisé.
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
        return Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => FavoritesRepository.instance.toggle(channelId),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.4),
              ),
              child: Icon(
                isFav ? Icons.favorite : Icons.favorite_outline,
                color: isFav ? AppColors.accentPink : Colors.white,
                size: 18,
              ),
            ),
          ),
        );
      },
    );
  }
}
