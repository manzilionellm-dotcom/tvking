// =========================================================
//  tailwind.config.cjs — Admin panel design tokens
// =========================================================
//  Palette alignee avec FlavorConfig cote Flutter pour
//  garder une coherence visuelle entre le panel admin et
//  les apps mobiles 7 MOTION / Red Room.
// =========================================================

/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  darkMode: 'class', // panel est dark-only en Phase 1
  theme: {
    extend: {
      colors: {
        // Surfaces (alignees sur lib/core/theme/app_colors.dart)
        obsidian: '#0E0E12',
        midnight: '#16161C',
        slate: '#1F1F26',
        ash: '#2A2A33',
        // Accent ember (CTA primaires, focus, danger)
        accent: {
          DEFAULT: '#D63A30',
          bright: '#FF5A4A',
          deep: '#8E1F1D',
        },
        // Texte chaud (jamais blanc pur)
        ink: {
          primary: '#F0EDE9',
          secondary: '#B6B0A8',
          tertiary: '#7E7872',
          muted: '#4E4A45',
        },
        // Champagne (accents non-critiques, badges editoriaux)
        champagne: {
          DEFAULT: '#E8D9C0',
          deep: '#B39B7C',
        },
        // Etats semantiques — utilises partout (bg-success/15,
        // text-warning…) mais historiquement JAMAIS definis ici :
        // les classes se compilaient en transparent. Corrige.
        success: {
          DEFAULT: '#3FA860', // vert chaud (assorti a la palette braise)
          bright: '#5BC97E',
        },
        warning: {
          DEFAULT: '#D69A30', // ambre (echo du champagne, plus saturee)
          bright: '#F0B95A',
        },
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        mono: ['ui-monospace', 'SFMono-Regular', 'Menlo', 'monospace'],
      },
      borderRadius: {
        DEFAULT: '8px',
        lg: '12px',
        xl: '16px',
        '2xl': '22px',
      },
    },
  },
  plugins: [],
};
