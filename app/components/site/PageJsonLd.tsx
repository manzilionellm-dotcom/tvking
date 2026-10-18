import {
  breadcrumbJsonLd,
  faqJsonLd,
  graph,
  jsonLdString,
  productsJsonLd,
  type Crumb,
} from "../../../lib/aio";

type Props = {
  /** Product × licences (pages that show the Forfaits prices). */
  products?: boolean;
  /** FAQPage — only where <CitationFaq /> renders the same Q/A. */
  faq?: boolean;
  /** Trail after the homepage, e.g. [{ name: "Forfaits", path: "/forfaits" }]. */
  crumbs?: Crumb[];
};

/**
 * Page-level Schema.org graph. Organization + WebSite live in app/layout.tsx;
 * this component never re-emits them.
 */
export default function PageJsonLd({ products = false, faq = false, crumbs }: Props) {
  const things = [
    ...(products ? productsJsonLd() : []),
    ...(faq ? [faqJsonLd()] : []),
    ...(crumbs && crumbs.length > 0 ? [breadcrumbJsonLd(crumbs)] : []),
  ];
  if (things.length === 0) return null;
  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: jsonLdString(graph(...things)) }}
    />
  );
}
