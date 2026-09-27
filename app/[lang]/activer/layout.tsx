import type { Metadata } from "next";
import { pageI18n } from "../../i18n/server";

export async function generateMetadata({ params }: LayoutProps<"/[lang]/activer">): Promise<Metadata> {
  const { m } = await pageI18n(params);
  return {
    title: m.meta.activateTitle,
    description: m.meta.activateDescription,
    robots: { index: false, follow: false }, // outil client, pas de référencement
  };
}

export default function Layout({ children }: { children: React.ReactNode }) {
  return children;
}
