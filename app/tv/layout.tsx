import type { Metadata } from "next";

import PageJsonLd from "../components/site/PageJsonLd";
import { canonicalFor } from "../lib/seo";

export const metadata: Metadata = {
  title: "TV en direct",
  description: "Collez votre playlist M3U. Chaque lien est vérifié avant lecture.",
  ...canonicalFor("/tv"),
};

export default function TvLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <PageJsonLd crumbs={[{ name: "TV en direct", path: "/tv" }]} />
      {children}
    </>
  );
}
