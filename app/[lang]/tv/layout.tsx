import type { Metadata } from "next";
import { pageI18n } from "../../i18n/server";

export async function generateMetadata({ params }: LayoutProps<"/[lang]/tv">): Promise<Metadata> {
  const { m } = await pageI18n(params);
  return { title: m.meta.tvTitle, description: m.meta.tvDescription };
}

export default function Layout({ children }: { children: React.ReactNode }) {
  return children;
}
