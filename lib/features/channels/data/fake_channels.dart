// =========================================================
//  fake_channels.dart — Données fictives pour la Phase 1
// =========================================================
//  Permet de développer et tester l'UI sans avoir à brancher
//  un vrai serveur IPTV.
//
//  IMPORTANT : aucune URL réelle, aucun lien vers du contenu
//  protégé. Les `streamUrl` sont des placeholders. On les
//  remplacera par les vraies sources que l'utilisateur ajoutera
//  via le parser M3U / Xtream (Phase 1 — étape 2).
// =========================================================

import 'package:flutter/material.dart';

import '../domain/channel.dart';

/// Liste de 4 chaînes fictives pour tester l'écran d'accueil.
const List<Channel> kFakeChannels = <Channel>[
  Channel(
    id: 'demo-sport-1',
    name: 'King Sport',
    category: 'Sport',
    streamUrl: 'about:blank',
    isLive: true,
    currentProgram: 'Champions League — Demi-finale',
    gradientColors: <Color>[
      Color(0xFFFF3366), // rose
      Color(0xFF7B1FA2), // violet
    ],
  ),
  Channel(
    id: 'demo-cinema-1',
    name: 'King Cinéma',
    category: 'Cinéma',
    streamUrl: 'about:blank',
    isLive: true,
    currentProgram: 'Inception (2010)',
    gradientColors: <Color>[
      Color(0xFF00D9FF), // cyan
      Color(0xFF0288D1), // bleu profond
    ],
  ),
  Channel(
    id: 'demo-info-1',
    name: 'King Info',
    category: 'Information',
    streamUrl: 'about:blank',
    isLive: true,
    currentProgram: 'Journal de 20h',
    gradientColors: <Color>[
      Color(0xFFFFD700), // or
      Color(0xFFFF6F00), // orange
    ],
  ),
  Channel(
    id: 'demo-kids-1',
    name: 'King Kids',
    category: 'Jeunesse',
    streamUrl: 'about:blank',
    isLive: false,
    currentProgram: 'Reprend à 7h00',
    gradientColors: <Color>[
      Color(0xFF00E676), // vert
      Color(0xFF00BFA5), // teal
    ],
  ),
];
