import type { Metadata } from "next";

import PageJsonLd from "../components/site/PageJsonLd";
import { canonicalFor } from "../lib/seo";

export const metadata: Metadata = {
  title: "Réglages",
  description: "Taille du texte, overscan et préférences TV King.",
  ...canonicalFor("/reglages"),
};

export default function SettingsLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <PageJsonLd crumbs={[{ name: "Réglages", path: "/reglages" }]} />
      {children}
    </>
  );
}
