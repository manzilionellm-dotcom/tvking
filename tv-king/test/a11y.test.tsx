import { render } from "@testing-library/react";
import { axe } from "jest-axe";
import { describe, expect, it, vi } from "vitest";

// next/link a besoin du runtime Next ; en test on le remplace par un
// simple <a> qui propage les attributs (href, aria-label, data-*).
vi.mock("next/link", () => ({
  default: (
    props: { children?: React.ReactNode; href?: string } & Record<
      string,
      unknown
    >,
  ) => {
    const { children, href, ...rest } = props;
    return (
      <a href={typeof href === "string" ? href : "#"} {...rest}>
        {children}
      </a>
    );
  },
}));

import { LevelBadge, LiveBadge } from "../app/components/Badge";
import { MediaCard } from "../app/components/MediaCard";
import { Row } from "../app/components/Row";
import { getByUniverse, MEDIA } from "../app/lib/data";

describe("accessibilité (axe)", () => {
  it("les badges ne produisent aucune violation", async () => {
    const { container } = render(
      <div>
        <LiveBadge kind="live" />
        <LevelBadge level="debutant" />
      </div>,
    );
    const results = await axe(container);
    expect(results.violations).toEqual([]);
  });

  it("une MediaCard expose un lien avec aria-label et passe axe", async () => {
    const { container } = render(<MediaCard item={MEDIA[0]} />);
    const link = container.querySelector("[data-focusable]");
    expect(link).not.toBeNull();
    expect(link?.getAttribute("aria-label")).toBeTruthy();
    const results = await axe(container);
    expect(results.violations).toEqual([]);
  });
});

describe("contrat d'accessibilité de la navigation", () => {
  it("chaque élément focusable d'une rangée porte un aria-label", () => {
    const { container } = render(
      <Row title="Sports" items={getByUniverse("sports")} />,
    );
    const focusables = container.querySelectorAll("[data-focusable]");
    expect(focusables.length).toBeGreaterThan(0);
    focusables.forEach((el) => {
      expect(el.getAttribute("aria-label")).toBeTruthy();
    });
  });
});
