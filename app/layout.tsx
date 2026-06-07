import type { Metadata, Viewport } from "next";
import { Geist, Playfair_Display } from "next/font/google";
import "./globals.css";
import Sidebar from "./components/Sidebar";
import SpatialNav from "./components/SpatialNav";
import Preferences from "./components/Preferences";
import ActivationGate from "./components/ActivationGate";
import TrialBanner from "./components/TrialBanner";
import LiveAlerts from "./components/LiveAlerts";
import LocaleSetup from "./components/LocaleSetup";
import { KeyboardProvider } from "./components/Keyboard";
import BackController from "./components/BackController";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

// Elegant high-contrast serif for display titles. Used only at large sizes
// (legible at TV distance); body stays in the sans for clarity.
const playfair = Playfair_Display({
  variable: "--font-display",
  subsets: ["latin"],
  weight: ["600", "700", "800", "900"],
});

export const metadata: Metadata = {
  title: "NOVA+ — Live TV",
  description:
    "NOVA+ : la télévision en direct pensée pour le grand écran — chaînes, guide TV et favoris, en un coup de télécommande.",
};

// Lock the layout to the device width (1:1 device pixels) so our viewport-based
// scaling controls the size — no pinch-zoom on a TV.
export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
  themeColor: "#101418",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="fr" className={`${geistSans.variable} ${playfair.variable} h-full antialiased`}>
      <body className="min-h-full bg-[var(--bg)]">
        <Preferences />
        <LocaleSetup />
        {/* SpatialNav stays outside the gate so the D-pad also drives the
            activation/lock screen. The gate blocks the app (sidebar + content)
            until this device is activated. */}
        <SpatialNav />
        {/* BackController : la touche BACK ferme d'abord clavier/fenêtres, puis
            revient à l'accueil, et ne quitte l'app que depuis l'accueil. */}
        <BackController />
        {/* KeyboardProvider englobe l'app : tout champ texte ouvre le clavier
            à l'écran intégré (plus de clavier système « mobile device »). */}
        <KeyboardProvider>
          <ActivationGate>
            <TrialBanner />
            <LiveAlerts />
            <Sidebar />
            {/* Content is inset past the collapsed nav rail (player pages opt out). */}
            <main className="min-h-screen">{children}</main>
          </ActivationGate>
        </KeyboardProvider>
      </body>
    </html>
  );
}
