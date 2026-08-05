/*
 * Chaîne CSS orientée box TV : Tailwind v4 vise Chrome 111+, mais la majorité
 * des box Android ont un WebView bien plus ancien. Après Tailwind :
 * - color-mix résolu en couleurs statiques quand c'est possible (preserve:
 *   la version moderne reste pour les navigateurs récents) ;
 * - @layer aplati en cascade classique (les WebView < Chrome 99 ignorent
 *   totalement les règles posées dans @layer, donc TOUS les utilitaires) ;
 * - autoprefixer selon browserslist (package.json).
 */
const config = {
  plugins: {
    "@tailwindcss/postcss": {},
    "@csstools/postcss-color-mix-function": { preserve: true },
    "@csstools/postcss-cascade-layers": {},
    autoprefixer: {},
  },
};

export default config;
