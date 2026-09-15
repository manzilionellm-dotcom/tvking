import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Réglages",
  description: "Taille du texte, overscan et préférences TV King.",
};

export default function SettingsLayout({ children }: { children: React.ReactNode }) {
  return children;
}
