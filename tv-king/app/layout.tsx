import type { Metadata, Viewport } from "next";
import "./globals.css";
import { AppFrame } from "./components/AppFrame";
import { LicenseProvider } from "./components/LicenseProvider";
import { PreferencesProvider } from "./lib/preferences";

// Métadonnées de l'app. Pas de marque réelle, pas de tracking.
export const metadata: Metadata = {
  title: "NOVA+ — Streaming premium",
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
      <body>
        <PreferencesProvider>
          <LicenseProvider>
            <AppFrame>{children}</AppFrame>
          </LicenseProvider>
        </PreferencesProvider>
      </body>
    </html>
  );
}
