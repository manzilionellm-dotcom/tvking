import type { Metadata, Viewport } from "next";
import { Geist, Playfair_Display } from "next/font/google";
import "./globals.css";
import Sidebar from "./components/Sidebar";
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
};

// Lock the layout to the device width (1:1 device pixels) so our viewport-based
// scaling controls the size — no pinch-zoom on a TV.
export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
  themeColor: "#121212",
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
        <Sidebar />
        <SpatialNav />
        {/* Content is inset past the collapsed nav rail. */}
        <main className="min-h-screen pl-[5.5rem]">{children}</main>
        {/* Eye-comfort veil — inert, above every surface including the player. */}
        <div className="comfort-veil" aria-hidden />
      </body>
    </html>
  );
}
