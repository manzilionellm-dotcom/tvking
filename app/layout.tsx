import type { Metadata, Viewport } from "next";
import { Geist, Playfair_Display } from "next/font/google";
import "./globals.css";
import Sidebar from "./components/Sidebar";
import MobileNav from "./components/MobileNav";
import SpatialNav from "./components/SpatialNav";
import Preferences from "./components/Preferences";
import ConsentGate from "./components/ConsentGate";
import MiniPlayer from "./components/MiniPlayer";
import WhatsAppFab from "./components/WhatsAppFab";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const playfair = Playfair_Display({
  variable: "--font-display",
  subsets: ["latin"],
  weight: ["600", "700", "800", "900"],
});

export const metadata: Metadata = {
  metadataBase: new URL("https://tvking.vercel.app"),
  title: {
    default: "TV King — Sport, films & formation",
    template: "%s | TV King",
  },
  description:
    "Lecteur IPTV personnel : vos playlists M3U, films, sport et formation. Aucun contenu n'est fourni avec l'app.",
  manifest: "/manifest.webmanifest",
  icons: { icon: "/icon.svg" },
  openGraph: {
    title: "TV King — Sport, films & formation",
    description: "Lecteur IPTV personnel. Vos playlists, vos liens.",
    url: "https://tvking.vercel.app",
    siteName: "TV King",
    locale: "fr_FR",
    type: "website",
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 5,
  userScalable: true,
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
        <ConsentGate />
        <Sidebar />
        <MobileNav />
        <SpatialNav />
        <main className="min-h-screen pl-[5.5rem] max-md:pb-[5.5rem] max-md:pl-0">{children}</main>
        <MiniPlayer />
        <WhatsAppFab />
      </body>
    </html>
  );
}
