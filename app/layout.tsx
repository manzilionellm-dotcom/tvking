import type { Metadata, Viewport } from "next";
import { Geist, Playfair_Display } from "next/font/google";
import "./globals.css";
import "./zuno.css";
import Preferences from "./components/Preferences";
import ConsentGate from "./components/ConsentGate";
import AppChrome from "./components/site/AppChrome";

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
  metadataBase: new URL("https://zuno.7themotion.com"),
  title: {
    default: "Zuno — TV, films & multi-appareils",
    template: "%s | Zuno",
  },
  description:
    "Zuno : TV en direct, films & séries, multi-appareils. Forfaits Annuel 9,99 € ou À vie 15 €.",
  manifest: "/manifest.webmanifest",
  icons: { icon: "/icon.svg" },
  openGraph: {
    title: "Zuno",
    description: "Lecteur premium multi-appareils. Forfaits simples.",
    url: "https://zuno.7themotion.com",
    siteName: "Zuno",
    locale: "fr_FR",
    type: "website",
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 5,
  userScalable: true,
  themeColor: "#0a0a0c",
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
        <AppChrome>{children}</AppChrome>
      </body>
    </html>
  );
}
