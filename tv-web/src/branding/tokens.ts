// =========================================================
//  tokens.ts — Tokens de design 7 MOTION (Maison Noir)
// =========================================================
//  Miroir TypeScript des constantes Flutter `lib/core/theme/app_colors.dart`.
//  Synchronisation manuelle pour rester DRY : si la palette change cote
//  Flutter, repercuter ici (et inversement). Pas d'import dynamique
//  possible — Dart et TS sont des langages distincts.
//
//  Convention : valeurs hex en lowercase. Aucune valeur magique ne doit
//  apparaitre dans le code UI — toujours passer par ces tokens (AGENTS.md).
// =========================================================

export const colors = {
  /** Fond void Maison Noir (charcoal). */
  background: '#0a0a0c',
  /** Surface basse (cards, tuiles). */
  surface: '#15151a',
  /** Surface haute (modals, popovers). */
  surfaceHigh: '#1f1f26',
  /** Bordure subtile. */
  border: '#2a2a32',

  /** Accent principal — ember (rouge profond signature 7 MOTION). */
  accent: '#d63a30',
  /** Accent hover/focus — ember plus chaud. */
  accentHover: '#ff5a4a',

  /** Texte principal blanc cassé Maison Noir. */
  textPrimary: '#f0ede9',
  /** Texte secondaire (libellés, métadonnées). */
  textSecondary: '#b6b0a8',
  /** Texte mute (caption, états désactivés). */
  textMuted: '#6e6a64',

  /** Badge live rouge — distinct de l'accent ember pour ne pas confondre. */
  live: '#e83740',
  /** Badge succès vert mat. */
  success: '#3fa45b',
} as const;

export const typography = {
  /**
   * Police principale. Inter en first choice (deja embarquee dans
   * Flutter via google_fonts), system fallback pour le 1er paint.
   */
  fontFamily:
    "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif",

  /**
   * Tailles en px. Pensees pour une UX TV (lecture 3m) : on demarre
   * a 14px (caption) et on monte jusqu'a 56px (heros). Sur desktop
   * 1080p ces tailles donnent un rendu confortable a 50cm.
   */
  size: {
    caption: 14,
    body: 18,
    title: 24,
    heading: 36,
    hero: 56,
  },

  /** Poids — Inter supporte 100..900, on en utilise 4. */
  weight: {
    regular: 400,
    medium: 500,
    semibold: 600,
    bold: 700,
  },
} as const;

export const spacing = {
  /** Echelle de 4px — convention Tailwind / iOS HIG. */
  xs: 4,
  sm: 8,
  md: 16,
  lg: 24,
  xl: 40,
  xxl: 64,
} as const;

export const radius = {
  sm: 4,
  md: 8,
  lg: 14,
  pill: 9999,
} as const;
