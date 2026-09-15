import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Rechercher",
  description: "Recherchez sport, films et formation dans TV King.",
};

export default function SearchLayout({ children }: { children: React.ReactNode }) {
  return children;
}
