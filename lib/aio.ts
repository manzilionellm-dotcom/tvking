import config from "../aio.config.json";

type Lang = keyof typeof config.i18n;

export const aio = config;
export const defaultLang = config.defaultLang as Lang;

export function faqFor(lang: Lang = defaultLang) {
  return config.i18n[lang].faq;
}

/**
 * JSON-LD Schema.org rendu dans app/layout.tsx.
 * FAQPage + Product (licences d'application). Pas de HowTo : le site n'a pas
 * de tutoriel d'installation détaillé (voir aio.todo.md).
 */
export function buildJsonLd(lang: Lang = defaultLang) {
  const url = config.siteUrl;
  const copy = config.i18n[lang];
  const org = {
    "@type": "Organization",
    "@id": `${url}/#org`,
    name: config.siteName,
    legalName: config.legalName,
    url,
    address: {
      "@type": "PostalAddress",
      streetAddress: "131 Continental Dr Suite 305",
      addressLocality: "Newark",
      addressRegion: "DE",
      postalCode: "19713",
      addressCountry: "United States",
    },
    contactPoint: {
      "@type": "ContactPoint",
      contactType: "customer support",
      url: config.contact.whatsapp,
    },
  };
  const products = config.plans.map((plan) => ({
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
      seller: { "@id": `${url}/#org` },
    },
  }));
  const faq = {
    "@type": "FAQPage",
    "@id": `${url}/#faq`,
    inLanguage: lang,
    mainEntity: faqFor(lang).map((item) => ({
      "@type": "Question",
      name: item.q,
      acceptedAnswer: { "@type": "Answer", text: item.a },
    })),
  };
  return { "@context": "https://schema.org", "@graph": [org, faq, ...products] };
}

/** Sérialisation sûre pour <script type="application/ld+json"> (échappe « < »). */
export function jsonLdString(lang: Lang = defaultLang) {
  return JSON.stringify(buildJsonLd(lang)).replace(/</g, "\\u003c");
}
