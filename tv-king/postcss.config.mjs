// Tailwind CSS v4 s'intègre via son plugin PostCSS dédié.
// (En v4, la configuration se fait majoritairement DANS le CSS via
// `@import "tailwindcss"` et `@theme`, plus de gros `tailwind.config.js`.)
const config = {
  plugins: {
    "@tailwindcss/postcss": {},
  },
};

export default config;
