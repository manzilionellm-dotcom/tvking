// Galerie de la typographie TV, pour les captures avant / après.
// Elle n'est pas une route de production : `lib/main_tv.dart` ne l'ouvre pas.
// Les couleurs viennent des jetons existants, pour que le thème confort
// des yeux reste le propriétaire de la palette.

import 'package:flutter/material.dart';

import '../features/tv/core/tv_app_tokens.dart';
import '../features/tv/core/tv_dimens.dart';
import '../features/tv/core/tv_tokens.dart';
import '../features/tv/presentation/tv_components.dart';

class TypeGallery extends StatelessWidget {
  const TypeGallery({super.key});

  @override
  Widget build(BuildContext context) {
    final TvAppTokens palette = TvAppTokens.of(context);
    return ColoredBox(
      color: palette.bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(48, 36, 48, 36),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Ce soir',
                    style: palette.display(TvDimens.displayM),
                  ),
                  const SizedBox(height: 8),
                  const TvSectionLabel('Pour vous'),
                  const SizedBox(height: 16),
                  Text(
                    'Le guide reprend à 21:00. Rien ne se lance tout seul.',
                    style: palette.ui(TvDimens.body, color: palette.muted),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    '42:10  /  1:28:00',
                    style: palette.figure(TvDimens.title, color: palette.text),
                  ),
                  const SizedBox(height: 28),
                  _ArtworkTitle(palette: palette),
                ],
              ),
            ),
            const SizedBox(width: 36),
            const SizedBox(
              width: 460,
              child: TvEmptyState(
                icon: Icons.live_tv_rounded,
                title: 'Cette rangée est encore vide',
                subtitle:
                    'La liste est là. Ajuste les filtres, ou ouvre Films et Séries.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtworkTitle extends StatelessWidget {
  const _ArtworkTitle({required this.palette});
  final TvAppTokens palette;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(TvTokens.rCard),
      child: SizedBox(
        height: 220,
        width: 640,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: <Color>[Color(0xFF8C4A2F), Color(0xFF1A120C)],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[
                    palette.bg,
                    palette.bg.withValues(alpha: 0),
                  ],
                  stops: const <double>[0.2, 0.72],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Text('Minuit à Lisbonne', style: palette.display(40)),
                  const SizedBox(height: 6),
                  Text(
                    '2024   ·   1 h 48   ·   8,4',
                    style: palette.ui(
                      TvDimens.body,
                      weight: FontWeight.w500,
                      color: palette.accentBright,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
