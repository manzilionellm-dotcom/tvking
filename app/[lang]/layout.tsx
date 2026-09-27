import type { Metadata, Viewport } from "next";
import { notFound } from "next/navigation";
import { Geist, Playfair_Display } from "next/font/google";
import "../globals.css";
import Sidebar from "../components/Sidebar";
import MobileNav from "../components/MobileNav";
import SpatialNav from "../components/SpatialNav";
import Preferences from "../components/Preferences";
import ConsentGate from "../components/ConsentGate";
import MiniPlayer from "../components/MiniPlayer";
import WhatsAppFab from "../components/WhatsAppFab";
import { LOCALES, RTL_LOCALES, isLocale } from "../i18n/config";
import { getMessages } from "../i18n/messages";
import { I18nProvider } from "../i18n/provider";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const playfair = Playfair_Display({
  variable: "--font-display",
  subsets: ["latin"],
  weight: ["600", "700", "800", "900"],
});

/* Chaque page est pré-rendue dans les 16 langues. */
export function generateStaticParams() {
  return LOCALES.map((lang) => ({ lang }));
}
export const dynamicParams = false;

export async function generateMetadata({ params }: LayoutProps<"/[lang]">): Promise<Metadata> {
  const { lang } = await params;
  const m = getMessages(isLocale(lang) ? lang : "fr");
  return {
    metadataBase: new URL("https://tvking.vercel.app"),
    title: { default: m.meta.siteTitle, template: "%s | TV King" },
    description: m.meta.siteDescription,
    manifest: "/manifest.webmanifest",
    icons: { icon: "/icon.svg" },
    openGraph: {
      title: m.meta.siteTitle,
      description: m.meta.ogDescription,
      url: "https://tvking.vercel.app",
      siteName: "TV King",
      locale: lang,
      type: "website",
    },
  };
}

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 5,
  userScalable: true,
  themeColor: "#121212",
};

export default async function RootLayout({ children, params }: LayoutProps<"/[lang]">) {
  const { lang } = await params;
  if (!isLocale(lang)) notFound();
  const messages = getMessages(lang);
  return (
    <html
      lang={lang}
      dir={RTL_LOCALES.has(lang) ? "rtl" : "ltr"}
      className={`${geistSans.variable} ${playfair.variable} h-full antialiased`}
    >
      <body className="min-h-full bg-[var(--bg)]">
        <I18nProvider lang={lang} messages={messages}>
          <Preferences />
          <ConsentGate />
          <Sidebar />
          <MobileNav />
          <SpatialNav />
          <main className="min-h-screen pl-[5.5rem] max-md:pb-[5.5rem] max-md:pl-0">{children}</main>
          <MiniPlayer />
          <WhatsAppFab />
        </I18nProvider>
      </body>
    </html>
  );
}
