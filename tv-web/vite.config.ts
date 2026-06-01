// =========================================================
//  vite.config.ts — Configuration Vite + Vitest
// =========================================================
//  Pour qu'on puisse packager ensuite vers Tizen (.wgt) et webOS
//  (.ipk), on a deux contraintes :
//
//    1. Output STATIQUE (HTML + JS + CSS dans dist/) — c'est ce que
//       les SDKs Tizen / webOS empaquetent. Pas de SSR, pas de
//       Node.js cote runtime.
//
//    2. Pas de chemins absolus dans l'HTML genere — `base: './'`
//       force des chemins relatifs pour que l'app charge correctement
//       depuis n'importe quelle racine (file:// sur certaines TVs).
//
//  Vitest est configure en jsdom pour les tests DOM legers (parser
//  M3U, models, etc.). Pour les tests qui touchent hls.js, on garde
//  l'env browser et on mocke.
// =========================================================

import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  base: './',
  build: {
    outDir: 'dist',
    sourcemap: true,
    target: 'es2020',
    // Limite la taille du chunk pour eviter de pousser des fichiers
    // > 4 Mo dans les .wgt Tizen (limite de plusieurs TV anciennes).
    rollupOptions: {
      output: {
        manualChunks: {
          'react-vendor': ['react', 'react-dom'],
          'player-vendor': ['hls.js'],
        },
      },
    },
  },
  server: {
    host: true, // dispo sur le LAN — pratique pour tester depuis une TV en local
    port: 5173,
  },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./test/setup.ts'],
    include: ['test/**/*.test.ts', 'test/**/*.test.tsx'],
  },
});
