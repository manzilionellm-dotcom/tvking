import type { Metadata } from "next";
import PageJsonLd from "../components/site/PageJsonLd";
import { canonicalFor } from "../lib/seo";

export const metadata: Metadata = {
  title: "Connexion",
  description: "Espace compte Zuno (démo). Licence application uniquement — nous ne vendons pas de chaînes.",
  ...canonicalFor("/connexion"),
};

export default function ConnexionLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <PageJsonLd crumbs={[{ name: "Connexion", path: "/connexion" }]} />
      {children}
    </>
  );
}
