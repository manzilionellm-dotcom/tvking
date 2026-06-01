import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'node:path';

// =========================================================
//  vite.config.ts — Admin panel build config
// =========================================================
//  Sortie : dist/ (consommee par Cloudflare Pages).
//  Alias @/ → src/ pour des imports propres dans le code.
//  Proxy dev : /api/* → Worker local (wrangler dev sur :8787)
//  pour pouvoir tester en local sans deploy.
// =========================================================

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:8787',
        changeOrigin: true,
      },
    },
  },
  build: {
    outDir: 'dist',
    sourcemap: false,
    target: 'es2022',
  },
});
