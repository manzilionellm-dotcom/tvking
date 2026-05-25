// =========================================================
//  fake_channels.dart — Données fictives (Phase 1)
// =========================================================
//  Permet de développer et tester l'UI sans serveur IPTV.
//
//  IMPORTANT : aucune URL réelle, aucun lien vers du contenu
//  protégé. Les `streamUrl` sont des placeholders. On les
//  remplacera quand on aura le parser M3U (Phase 1.1).
//
//  10 chaînes pour bien remplir les sections horizontales
//  du nouvel écran d'accueil.
// =========================================================

import 'package:flutter/material.dart';

import '../domain/channel.dart';

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
  Channel(
    id: 'demo-music-1',
    name: 'King Music',
    category: 'Musique',
    streamUrl: 'about:blank',
    isLive: true,
    currentProgram: 'Top 50 — Live mix',
    gradientColors: <Color>[
      Color(0xFFE040FB), // magenta
      Color(0xFF7C4DFF), // indigo
    ],
  ),
  Channel(
    id: 'demo-series-1',
    name: 'King Séries',
    category: 'Séries',
    streamUrl: 'about:blank',
    isLive: true,
    currentProgram: 'Breaking Bad — S05E14',
    gradientColors: <Color>[
      Color(0xFF455A64), // gris-bleu
      Color(0xFF263238), // anthracite
    ],
  ),
  Channel(
    id: 'demo-doc-1',
    name: 'King Doc',
    category: 'Documentaire',
    streamUrl: 'about:blank',
    isLive: true,
    currentProgram: 'Planète Terre II — Jungles',
    gradientColors: <Color>[
      Color(0xFF8D6E63), // marron clair
      Color(0xFF4E342E), // chocolat
    ],
  ),
  Channel(
    id: 'demo-action-1',
    name: 'King Action',
    category: 'Cinéma',
    streamUrl: 'about:blank',
    isLive: true,
    currentProgram: 'John Wick: Chapter 4',
    gradientColors: <Color>[
      Color(0xFFD32F2F), // rouge sang
      Color(0xFF212121), // noir
    ],
  ),
  Channel(
    id: 'demo-sport-2',
    name: 'King Tennis',
    category: 'Sport',
    streamUrl: 'about:blank',
    isLive: true,
    currentProgram: 'Roland-Garros — 1/2 finale',
    gradientColors: <Color>[
      Color(0xFFFFEB3B), // jaune
      Color(0xFFFF6F00), // orange profond
    ],
  ),
  Channel(
    id: 'demo-discovery-1',
    name: 'King Voyage',
    category: 'Découverte',
    streamUrl: 'about:blank',
    isLive: false,
    currentProgram: 'Reprend à 6h00',
    gradientColors: <Color>[
      Color(0xFF26C6DA), // turquoise
      Color(0xFF00838F), // teal foncé
    ],
  ),
];
