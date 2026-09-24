/// <reference types="vite/client" />

// =========================================================
//  vite-env.d.ts — Types Vite pour import.meta.env
// =========================================================
//  Sans cette directive, TypeScript ne connait pas l'extension
//  Vite `import.meta.env.VITE_*` et le build casse avec
//  TS2339: Property 'env' does not exist on type 'ImportMeta'.
//
//  On declare aussi nos variables custom (prefixe VITE_) pour
//  beneficier de l'autocompletion et du type-checking quand on
//  les lit depuis le code.
// =========================================================

interface ImportMetaEnv {
  /// URL de base du Worker API. Vide en dev (le proxy Vite
  /// redirige /api → :8787). Renseigne via VITE_API_BASE en prod
  /// dans Cloudflare Pages (Settings → Environment variables).
  readonly VITE_API_BASE?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
