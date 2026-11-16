// =========================================================
//  tv_novatube_palette.dart — Palette « vert pétrole » de NovaTube TV
// =========================================================
//  Utilisée UNIQUEMENT quand l'app est compilée avec
//  `--dart-define=NOVATUBE_TV=true` (voir core/app/novatube_tv_edition.dart).
//  Le build Zuno ne lit jamais ces valeurs.
//
//  D'où viennent ces couleurs ? Elles ont été RELEVÉES pixel par pixel sur
//  la capture de référence fournie par le propriétaire (le 16/11/2026),
//  puis ajustées pour garantir la lisibilité à 3 m (contrastes WCAG
//  vérifiés par test/novatube_tv/novatube_palette_test.dart) :
//
//    capture            → jeton
//    fond   #04100C     → bg        #050F0C  noir à peine teinté de vert
//    rail   #151B19     → panel     #0D1513  (un cran au-dessus du fond)
//    carte  #182020     → card      #131C1A
//    ligne sélectionnée #22312E → sel  #22312E
//    bord de focus #73CDC3     → accentBright (turquoise vif)
//    texte « ALL » / icônes #4EA89C → accent (turquoise discret)
//    pastille « Live TV » #00594B  → accentDeep
//
//  Pourquoi pas du noir pur ? Sur les écrans OLED, #000 crée du « banding »
//  et fatigue l'œil. Un noir légèrement vert donne la profondeur
//  « cinéma » demandée, et le turquoise devient le SEUL signal coloré :
//  l'œil sait toujours où est le focus de la télécommande.
// =========================================================
import 'package:flutter/painting.dart';

abstract final class TvNovatube {
  // ---- Surfaces empilées (du plus sombre au plus clair) ----
  static const Color bg = Color(0xFF050F0C); // Surface 0 — fond de scène
  static const Color panel = Color(0xFF0D1513); // rail / colonnes
  static const Color card = Color(0xFF131C1A); // carte au repos
  static const Color tile = Color(0xFF16201E); // vignette de chaîne
  static const Color sel = Color(0xFF22312E); // ligne sélectionnée / focus
  static const Color surface3 = Color(0xFF2A3431); // menu déployé, barre de recherche
  static const Color line = Color(0xFF2B3835); // filet / bordure subtile
  static const Color lineSoft = Color(0xFF1B2523); // bordure au repos

  // ---- Texte (jamais de blanc pur : anti-halo à distance) ----
  static const Color text = Color(0xFFE6EFEC);
  static const Color muted = Color(0xFF9DACA8);
  static const Color mutedDim = Color(0xFF7D8E8A);

  // ---- Accent turquoise (un seul accent dans toute l'app) ----
  static const Color accent = Color(0xFF4EA89C); // repos : texte « ALL », icônes
  static const Color accentBright = Color(0xFF73CDC3); // focus télécommande
  static const Color accentDeep = Color(0xFF00594B); // pastilles, dégradés
  static const Color onAccent = Color(0xFF04100C); // texte posé SUR le turquoise

  // ---- Transparences dérivées (déclarées ici : règle n°5 d'AGENTS.md) ----
  static const Color badgeBg = Color(0x1F4EA89C); // fond de badge (≈ 12 %)
  static const Color accentClear = Color(0x004EA89C); // bord de dégradé
  static const Color glow = Color(0x184EA89C); // halo derrière le logo
  static const Color pillTop = Color(0x124EA89C); // haut de la pastille prix
  static const Color sceneHalo = Color(0xFF0B2A24); // halo lointain du fond
}
