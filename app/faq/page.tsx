import type { Metadata } from "next";
import Link from "next/link";
import AppOnlyNotice from "../components/site/AppOnlyNotice";
import CitationFaq from "../components/site/CitationFaq";
import PageJsonLd from "../components/site/PageJsonLd";
import { canonicalFor } from "../lib/seo";

export const metadata: Metadata = {
  title: "FAQ",
  description:
    "FAQ Zuno : application IPTV uniquement — nous ne vendons pas de chaînes. Activation S+M2, forfaits licence app, appareils.",
  ...canonicalFor("/faq"),
};

export default function FaqPage() {
  return (
    <div className="zuno-page mx-auto max-w-3xl px-4 py-14 sm:px-6">
      <PageJsonLd faq crumbs={[{ name: "FAQ", path: "/faq" }]} />
      <h1 className="text-3xl font-bold text-white">FAQ</h1>
      <div className="mt-6">
        <AppOnlyNotice variant="hero" />
      </div>
      <CitationFaq heading={null} className="mt-10" />
      <p className="mt-8 text-sm text-white/40">
        Voir aussi{" "}
        <Link href="/legal" className="text-[#60a5fa]">
          mentions légales
        </Link>
        .
      </p>
    </div>
  );
}
