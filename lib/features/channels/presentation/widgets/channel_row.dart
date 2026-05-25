// =========================================================
//  channel_row.dart — Rangée horizontale de ChannelPoster
// =========================================================
//  Composant clé du nouvel accueil : une section avec un
//  titre ("Pour vous", "En direct"...) suivie d'une liste
//  horizontale scrollable de vignettes.
//
//  Performance : on utilise `ListView.builder` (lazy) pour
//  ne créer que les vignettes visibles à l'écran. Avec
//  500+ chaînes, c'est indispensable pour rester fluide.
// =========================================================

import 'package:flutter/material.dart';

import '../../domain/channel.dart';
import 'channel_poster.dart';
import 'section_header.dart';

class ChannelRow extends StatelessWidget {
  const ChannelRow({
    required this.title,
    required this.channels,
    required this.onChannelTap,
    this.onSeeAll,
    super.key,
  });

  final String title;
  final List<Channel> channels;
  final void Function(Channel channel) onChannelTap;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: title, onSeeAll: onSeeAll),
        SizedBox(
          // Hauteur fixe : vignette + texte sous la vignette.
          // ~ 200px sur téléphone, 240px sur tablette/TV.
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            // Physique iOS-like : on rebondit sur les bords
            physics: const BouncingScrollPhysics(),
            itemCount: channels.length,
            separatorBuilder: (BuildContext _, int __) =>
                const SizedBox(width: 12),
            itemBuilder: (BuildContext context, int index) {
              final Channel ch = channels[index];
              return SizedBox(
                // Largeur fixe pour une vignette poster (2/3 ratio
                // sur la hauteur 200 → ~133 de large, on prend 130).
                width: 130,
                child: ChannelPoster(
                  channel: ch,
                  onTap: () => onChannelTap(ch),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
