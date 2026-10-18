import type { Metadata } from "next";

import PageJsonLd from "../components/site/PageJsonLd";
import { canonicalFor } from "../lib/seo";

export const metadata: Metadata = {
  title: "Rechercher",
  description: "Recherchez sport, films et formation dans TV King.",
  ...canonicalFor("/search"),
};

export default function SearchLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <PageJsonLd crumbs={[{ name: "Rechercher", path: "/search" }]} />
      {children}
    </>
  );
}
