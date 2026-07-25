import Link from "next/link";
import { type Facet, facetHref } from "../lib/data";

/*
 * Facet chips — the horizontal "narrow it down" strip at the top of a category.
 * Kept to one row of large targets (Hick's law: few primary options), with the
 * current facet highlighted and an "all" chip back to the full category.
 */
export default function FacetNav({
  facets,
  current,
  allHref,
  allLabel,
}: {
  facets: Facet[];
  current?: string;
  allHref: string;
  allLabel: string;
}) {
  return (
    <nav aria-label="Filtrer" className="mb-[1.8rem] flex flex-wrap gap-[0.7rem]">
      <Chip href={allHref} label={allLabel} active={!current} />
      {facets.map((f) => (
        <Chip key={f.key} href={facetHref(f)} label={f.label} active={current === f.key} />
      ))}
    </nav>
  );
}

function Chip({ href, label, active }: { href: string; label: string; active: boolean }) {
  return (
    <Link
      href={href}
      data-focusable
      data-focus-key={`facet:${href}`}
      aria-current={active ? "page" : undefined}
      className="focusable rounded-full px-[1.3rem] py-[0.6rem] text-[1.1rem] font-semibold"
      style={
        active
          ? { background: "var(--gold-grad)", color: "#000" }
          : { background: "var(--surface-2)", color: "var(--text-high)" }
      }
    >
      {label}
    </Link>
  );
}
