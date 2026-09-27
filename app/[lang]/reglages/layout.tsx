import type { Metadata } from "next";
import { pageI18n } from "../../i18n/server";

export async function generateMetadata({ params }: LayoutProps<"/[lang]/reglages">): Promise<Metadata> {
  const { m } = await pageI18n(params);
  return { title: m.meta.settingsTitle, description: m.meta.settingsDescription };
}

export default function Layout({ children }: { children: React.ReactNode }) {
  return children;
}
