import type { Metadata, Viewport } from "next";
import "./globals.css";

// Métadonnées de l'app. Pas de marque réelle, pas de tracking.
export const metadata: Metadata = {
  title: "TV King — Streaming premium",
  description:
    "Application de streaming TV premium et universelle, pensée pour être utilisée à 3 mètres avec une télécommande, par tout le monde.",
};

// Viewport TV : on fige l'échelle (le zoom utilisateur n'a pas de sens
// sur une télé), la mise à l'échelle est gérée par notre design system.
export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  themeColor: "#121212",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  // lang="fr" : narration vocale et lecteurs d'écran utilisent le français.
  return (
    <html lang="fr">
      <body>{children}</body>
    </html>
  );
}
