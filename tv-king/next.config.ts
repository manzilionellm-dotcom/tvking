import type { NextConfig } from "next";

// Configuration Next.js — volontairement minimale.
// - `reactStrictMode` : détecte les effets de bord involontaires en dev.
// - Pas d'images binaires dans ce projet (tous les visuels sont des
//   dégradés CSS), donc aucune config `images` n'est nécessaire.
const nextConfig: NextConfig = {
  reactStrictMode: true,
};

export default nextConfig;
