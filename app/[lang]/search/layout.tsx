import type { Metadata } from "next";
import { pageI18n } from "../../i18n/server";

export async function generateMetadata({ params }: LayoutProps<"/[lang]/search">): Promise<Metadata> {
  const { m } = await pageI18n(params);
  return { title: m.meta.searchTitle, description: m.meta.searchDescription };
}

export default function SearchLayout({ children }: { children: React.ReactNode }) {
  return children;
}
