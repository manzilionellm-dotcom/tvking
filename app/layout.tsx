import type { Metadata, Viewport } from "next";
import { Geist, Playfair_Display } from "next/font/google";
import "./globals.css";
import Sidebar from "./components/Sidebar";
import MobileNav from "./components/MobileNav";
import SpatialNav from "./components/SpatialNav";
import Preferences from "./components/Preferences";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

// Elegant high-contrast serif for display titles — the "royal" voice. Used only
// at large sizes (legible at TV distance); body stays in the sans for clarity.
const playfair = Playfair_Display({
  variable: "--font-display",
  subsets: ["latin"],
  weight: ["600", "700", "800", "900"],
});

export const metadata: Metadata = {
  title: "TV King — Sport & Formation",
  description:
    "Application de streaming pensée pour la télévision : sport en direct et formation, en grand écran.",
  applicationName: "TV King",
  // Installed-to-home-screen feel on iOS: full-screen, translucent status bar.
  appleWebApp: {
    capable: true,
    title: "TV King",
    statusBarStyle: "black-translucent",
  },
  formatDetection: { telephone: false },
};

// Lock the layout to the device width (1:1 device pixels) so our viewport-based
// scaling controls the size — no pinch-zoom, app-like on phone and TV alike.
// viewportFit "cover" lets the pocket UI draw edge-to-edge behind the notch
// (safe distances come back via env(safe-area-inset-*) in globals.css).
export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
  viewportFit: "cover",
  themeColor: "#121212",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="fr" className={`${geistSans.variable} ${playfair.variable} h-full antialiased`}>
      {/* No bg utility here: the throne-room ambience (body::before) sits on a
          negative z layer and must not be painted over — html carries #121212. */}
      <body className="min-h-full">
        <Preferences />
        <Sidebar />
        <MobileNav />
        <SpatialNav />
        {/* Content is inset past the collapsed nav rail; on mobile the rail is
            replaced by the bottom tab bar, whose height is reserved instead. */}
        <main className="min-h-screen pl-[5.5rem] max-md:pb-[var(--tabbar-h)] max-md:pl-0">
          {children}
        </main>
      </body>
    </html>
  );
}
