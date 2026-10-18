import type { Metadata } from "next";
import PageJsonLd from "../components/site/PageJsonLd";
import { canonicalFor } from "../lib/seo";

export const metadata: Metadata = {
  title: "Devenir revendeur",
  description:
    "Revendez la licence de l'application Zuno (Annuel 9,99 € / an, À vie 15 €) — pas de chaînes. Activation des appareils par S code + M2.",
  ...canonicalFor("/revendeur"),
};

export default function RevendeurLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <PageJsonLd crumbs={[{ name: "Devenir revendeur", path: "/revendeur" }]} />
      {children}
    </>
  );
}
