import config from "../aio.config.json";

type Lang = keyof typeof config.i18n;

export const aio = config;
export const defaultLang = config.defaultLang as Lang;

export function faqFor(lang: Lang = defaultLang) {
  return config.i18n[lang].faq;
}

export type Crumb = { name: string; path: string };
type Thing = Record<string, unknown>;

const url = config.siteUrl;
const ORG_ID = `${url}/#org`;
const SITE_ID = `${url}/#website`;

/** Organization + WebSite — emitted once by the root layout (static, no request-time API). */
export function identityJsonLd(lang: Lang = defaultLang): Thing[] {
  const org: Thing = {
    "@type": "Organization",
    "@id": ORG_ID,
    name: config.siteName,
    legalName: config.legalName,
    url,
    logo: { "@type": "ImageObject", url: `${url}/icon.svg` },
    address: {
      "@type": "PostalAddress",
      streetAddress: "131 Continental Dr Suite 305",
      addressLocality: "Newark",
      addressRegion: "DE",
      postalCode: "19713",
      addressCountry: "US",
    },
    contactPoint: {
      "@type": "ContactPoint",
      contactType: "customer support",
      url: config.contact.whatsapp,
      availableLanguage: [lang],
    },
  };
  const website: Thing = {
    "@type": "WebSite",
    "@id": SITE_ID,
    url,
    name: config.siteName,
    inLanguage: lang,
    publisher: { "@id": ORG_ID },
  };
  return [org, website];
}

/** One Product per licence (prices from aio.config.json plans). No ratings, no reviews. */
export function productsJsonLd(lang: Lang = defaultLang): Thing[] {
  const copy = config.i18n[lang];
  return config.plans
    .filter((plan) => plan.price > 0)
    .map((plan) => ({
      "@type": "Product",
      "@id": `${url}/#product-${plan.id}`,
      name: `${config.siteName} – ${plan.name[lang]}`,
      description: copy.productDescription
        .replaceAll("{name}", plan.name[lang])
        .replaceAll("{note}", plan.note),
      brand: { "@type": "Brand", name: config.siteName },
      offers: {
        "@type": "Offer",
        url: `${url}/forfaits`,
        price: plan.price.toFixed(2),
        priceCurrency: config.currency,
        availability: "https://schema.org/InStock",
        seller: { "@id": ORG_ID },
      },
    }));
}

/** FAQPage — only on pages that render <CitationFaq /> (same Q/A visible in HTML). */
export function faqJsonLd(lang: Lang = defaultLang): Thing {
  return {
    "@type": "FAQPage",
    "@id": `${url}/#faq`,
    inLanguage: lang,
    mainEntity: faqFor(lang).map((item) => ({
      "@type": "Question",
      name: item.q,
      acceptedAnswer: { "@type": "Answer", text: item.a },
    })),
  };
}

/** BreadcrumbList — crumbs are the trail after the homepage (prepended as « Accueil »). */
export function breadcrumbJsonLd(crumbs: Crumb[]): Thing {
  const trail: Crumb[] = [{ name: "Accueil", path: "/" }, ...crumbs];
  return {
    "@type": "BreadcrumbList",
    itemListElement: trail.map((c, i) => ({
      "@type": "ListItem",
      position: i + 1,
      name: c.name,
      item: c.path === "/" ? url : `${url}${c.path}`,
    })),
  };
}

/** Full graph (compat): identity + FAQ + products. */
export function buildJsonLd(lang: Lang = defaultLang) {
  return graph(...identityJsonLd(lang), faqJsonLd(lang), ...productsJsonLd(lang));
}

export function graph(...things: Thing[]) {
  return { "@context": "https://schema.org", "@graph": things };
}

/** Sérialisation sûre pour <script type="application/ld+json"> (échappe « < »). */
export function jsonLdString(data: Thing = buildJsonLd()) {
  return JSON.stringify(data).replace(/</g, "\\u003c");
}
