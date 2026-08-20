// =========================================================
//  tv_tokens.dart — Design System « Maison Noir » (The Few)
// =========================================================
//  Source de vérité UNIQUE des couleurs, rayons, dégradés et styles de
//  texte de DeFew TV. AUCUNE couleur en dur dans les écrans : tout passe
//  par ici. ADN : club privé, noir profond, or discret.
// =========================================================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TvTokens {
  TvTokens._();

  // ---- Couleurs — système de SURFACES en couches (la profondeur naît de
  //  l'empilement, pas des bordures).
  //
  //  THÈME « VERRE NOIR » v1 (demande propriétaire du 20/08 : « je n'aime
  //  pas le thème, je veux du verre ») : on quitte le noir CHAUD + or
  //  champagne pour un VERRE FROID — encre bleutée profonde, surfaces
  //  « givrées » (teintes de verre fumé, opaques pour rester lisibles sur
  //  petite box : le vrai flou temps réel — BackdropFilter — est interdit
  //  ici, il met à genoux les GPU de Fire TV Stick), arêtes claires façon
  //  tranche de verre, accent GLACIER (bleu-argent). Les NOMS de tokens ne
  //  bougent pas (gold = l'accent, quel que soit sa teinte) : 60 écrans
  //  les consomment, la refonte se fait ICI et nulle part ailleurs.
  //  L'ADN Cinéma (rouge braise) est conservé : deux mondes, deux
  //  ambiances — même verre. Jamais #000 pur (banding OLED).
  static const Color bg = Color(0xFF0A0D13); // Surface 0 — encre froide
  static const Color panel = Color(0xFF0F131B); // sidebar (proche du fond)
  static const Color card = Color(0xFF151A24); // Surface 1 — verre au repos
  static const Color tile = Color(0xFF171C26); // fond des vignettes de chaînes
  static const Color tileBorder = Color(0x14FFFFFF); // arête de verre (blanc 8 %)
  static const Color badgeBg = Color(0x1F9FC2E8); // fond badge (glacier ~12 %)
  static const Color sel = Color(0xFF1B2230); // Surface 2 — focus / élevé
  static const Color surface3 = Color(0xFF232B3B); // overlay / menu déployé
  static const Color line = Color(0xFF2A3345); // hairline / bordure subtile
  static const Color lineSoft = Color(0xFF202836); // bordures discrètes (repos)
  static const Color text = Color(0xFFEEF2F8); // texte principal (blanc froid)
  static const Color muted = Color(0xFF97A0AE); // texte secondaire
  static const Color mutedDim = Color(0xFF59616F); // texte tertiaire / hints
  static const Color gold = Color(0xFF9FC2E8); // ACCENT (glacier)
  // Texte/icônes posés SUR une surface d'accent (boutons pleins) : marine
  // profond — le pendant froid de l'ancien brun-noir sur or.
  static const Color onGold = Color(0xFF0A1626);
  static const Color goldBright = Color(0xFFC4DCF5); // GLACIER FOCUS (texte + lueur)
  static const Color goldDeep = Color(0xFF6E93BE); // glacier sombre : dégradés
  static const Color live = Color(0xFFD8453F); // pastille EN DIRECT (rouge vif sobre)

  // ----- CINÉMA : accent ROUGE BRAISE immersif (terrain 2026-07-17) -----
  // Demande client : côté Films & Séries, un rouge profond façon salle de
  // cinéma — moins lumineux que l'or, il « atténue le regard » dans le noir.
  // C'est le rouge ember de la marque 7 MOTION (#D63A30), décliné : accent,
  // variante focus (plus claire), variante sombre (dégradés), texte posé
  // dessus, et fond de badge translucide. Le LIVE garde l'or : deux mondes,
  // deux ambiances — même obsidienne.
  static const Color ember = Color(0xFFD63A30); // ACCENT Cinéma (brand ember)
  static const Color emberBright = Color(0xFFEF6A5E); // focus / texte accent
  static const Color emberDeep = Color(0xFF8E241D); // dégradés, ombres
  static const Color onEmber = Color(0xFFFFF3F0); // texte sur bouton rouge
  static const Color emberBadgeBg = Color(0x1FD63A30); // fond badge (rouge 12 %)

  /// Dégradé des accents Cinéma (barres de progression, bouton REGARDER…) —
  /// l'équivalent rouge du ctaGradient or.
  static const Gradient cineGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[emberBright, ember],
  );
  static const Color success = Color(0xFF5FA975); // ✓ copié

  // ---- Rayons ----
  static const double rCard = 14;
  static const double rButton = 14;
  static const double rMenuItem = 12;
  static const double rSmall = 8;
  static const double rGlass = 16; // rail verre (§3)
  // Hairline d'accent (glacier 18%) — bordure premium (rail verre, badges).
  static const Color hairline = Color(0x2E9FC2E8);

  // ---- Fond global « clair de lune » : lumière froide qui tombe du haut,
  //  s'éteint en encre bleutée puis se referme vers le bas. Trois arrêts —
  //  la profondeur d'une vitre de nuit, pas un aplat. ----
  static const Gradient bgGradient = RadialGradient(
    center: Alignment(0.56, -0.40), // 78% / 30%
    radius: 1.45,
    colors: <Color>[Color(0xFF141B2B), Color(0xFF0D1119), bg],
    stops: <double>[0.0, 0.52, 0.95],
  );

  // ---- VIGNETTAGE cinéma : assombrit très légèrement les bords de l'écran.
  //  Trois effets d'un seul dégradé : (1) le regard est guidé vers le centre,
  //  (2) moins d'éblouissement dans un salon sombre (confort des yeux),
  //  (3) la profondeur « projection » des salles. Discret (≤ 14 %) pour ne
  //  jamais manger le contenu des bords. Posé en foregroundDecoration du
  //  TvShell → aucun widget de plus dans l'arbre. ----
  static const Gradient vignette = RadialGradient(
    center: Alignment.center,
    radius: 1.25,
    colors: <Color>[Color(0x00000000), Color(0x00000000), Color(0x24000000)],
    stops: <double>[0.0, 0.72, 1.0],
  );

  // ---- Halo froid discret derrière le branding (coin haut-gauche) ----
  // Profondeur « premium » : évite le noir plat sous le logo The Few.
  static const Gradient brandGlow = RadialGradient(
    center: Alignment.topLeft,
    radius: 1.1,
    colors: <Color>[Color(0x149FC2E8), Color(0x00000000)],
  );

  // ---- Filet d'accent glacier (haut de carte) ----
  static const Gradient goldHairline = LinearGradient(
    colors: <Color>[Color(0x009FC2E8), gold, Color(0x009FC2E8)],
  );

  // ---- CTA principal (dégradé or) ----
  static const Gradient ctaGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[goldBright, gold],
  );

  // ---- Pastille prix ----
  static const Gradient pillGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0x0F9FC2E8), Color(0x009FC2E8)],
  );

  // =========================================================
  //  TYPOGRAPHIE — 3 rôles, jamais plus.
  //   • display = Oswald (titres d'accent, sobriété TV)
  //   • ui      = Inter  (tout le reste)
  //   • mono    = JetBrains Mono (code d'activation / identifiants UNIQUEMENT)
  // =========================================================
  // MÉMOÏSATION (revue perf) : ces helpers sont appelés dans les builders
  // de focus, exécutés à CHAQUE cran de D-pad (tuiles du Modèle B, boutons
  // Channels, rails…). Chaque appel GoogleFonts.xxx() refait un lookup de
  // cache de police + alloue un TextStyle : on fige le résultat par
  // combinaison (taille/graisse/couleur/espacement) — bornée par le design
  // system (3 rôles × quelques tailles), donc sans dérive mémoire.
  // Clé RECORD (égalité par valeur) et non un hash : une collision de hash
  // aurait renvoyé silencieusement le mauvais style.
  static final Map<(int, double, FontWeight, Color, double), TextStyle>
      _styleMemo = <(int, double, FontWeight, Color, double), TextStyle>{};

  static TextStyle _memo(
      int font, double size, FontWeight weight, Color color, double spacing,
      TextStyle Function() build) {
    return _styleMemo[(font, size, weight, color, spacing)] ??= build();
  }

  static TextStyle display(double size,
          {FontWeight weight = FontWeight.w600, Color color = text, double spacing = 0}) =>
      _memo(0, size, weight, color, spacing,
          () => GoogleFonts.cormorantGaramond(
              fontSize: size, fontWeight: weight, color: color, letterSpacing: spacing));

  static TextStyle ui(double size,
          {FontWeight weight = FontWeight.w400, Color color = text, double spacing = 0}) =>
      _memo(1, size, weight, color, spacing,
          () => GoogleFonts.manrope(
              fontSize: size, fontWeight: weight, color: color, letterSpacing: spacing));

  static TextStyle mono(double size,
          {FontWeight weight = FontWeight.w600, Color color = goldBright, double spacing = 0}) =>
      _memo(2, size, weight, color, spacing,
          () => GoogleFonts.jetBrainsMono(
              fontSize: size, fontWeight: weight, color: color, letterSpacing: spacing));
}
