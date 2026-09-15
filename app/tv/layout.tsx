import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "TV en direct",
  description: "Collez votre playlist M3U. Chaque lien est vérifié avant lecture.",
};

export default function TvLayout({ children }: { children: React.ReactNode }) {
  return children;
}
