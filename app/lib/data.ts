/*
 * Mock content model for TV King.
 * The shape follows the researched IA: a universal shell (left nav + horizontal
 * rows) with category-specific metadata on cards — LIVE/score/clock for sport,
 * level/duration/progress/instructor for formation.
 */

export type Section = "home" | "sport" | "formation";

/** A swatch used to render lightweight gradient "artwork" without binary assets. */
export type Art = { from: string; to: string };

export type LiveState = "live" | "upcoming" | "replay";

export interface MediaItem {
  id: string;
  title: string;
  /** 16:9 video, 1:1 logo, 2:3 poster — per Android TV card spec. */
  shape?: "16:9" | "1:1" | "2:3";
  art: Art;
  /** 0..1 resume progress → renders the Continue Watching bar. */
  progress?: number;
  subtitle?: string;
  badge?: string;
  /**
   * Facet keys the item belongs to (discipline for sport, theme for formation).
   * Faceted navigation is the documented depth mechanism on TV shells.
   */
  topics?: string[];
  /** Overrides the default /title/[id] destination (used by facet tiles). */
  href?: string;

  // Sport-specific
  live?: LiveState;
  clock?: string; // e.g. "72'" or "Q3 04:12"
  score?: string; // e.g. "2 - 1"
  league?: string;
  startsIn?: string; // for upcoming, e.g. "Demain 21:00"

  // Formation-specific
  level?: "Débutant" | "Intermédiaire" | "Avancé";
  duration?: string; // e.g. "12 min"
  instructor?: string;
  lessons?: number;

  /** Long synopsis shown on the detail page (optional; a fallback is generated). */
  description?: string;
}

/** Discriminates the content kind from its metadata (drives detail-page UI). */
export type Kind = "sport" | "formation";

export function kindOf(item: MediaItem): Kind {
  if (item.live || item.score || item.clock || item.startsIn) return "sport";
  // No live signal (an analysis, a highlight): the facet tag settles it, so a
  // sport analysis is not mistaken for a course with a lesson programme.
  return item.topics?.some((t) => sportFacets.some((f) => f.key === t)) ? "sport" : "formation";
}

export interface Row {
  id: string;
  title: string;
  /** "ranked" places the most-relevant item to the left (Netflix convention). */
  items: MediaItem[];
}

const g = (from: string, to: string): Art => ({ from, to });

/* ---------------------------------- FACETS --------------------------------- */

/*
 * Faceted navigation is the documented depth mechanism of a TV shell (rows for
 * browse, facets for "I know roughly what I want") — attributed 20-50 % faster
 * finding than free browsing alone (docs/RESEARCH-TV-UX.md §5). Sport is faceted
 * by discipline, formation by theme (and by level inside the facet page).
 */
export interface Facet {
  key: string;
  label: string;
  kind: Kind;
  art: Art;
}

export const sportFacets: Facet[] = [
  { key: "football", label: "Football", kind: "sport", art: g("#1f3a5f", "#0c1622") },
  { key: "basket", label: "Basket", kind: "sport", art: g("#5f3a2b", "#241310") },
  { key: "tennis", label: "Tennis", kind: "sport", art: g("#3a5f2b", "#16240f") },
  { key: "moteur", label: "F1 / Moto", kind: "sport", art: g("#5f2b3a", "#241019") },
  { key: "rugby", label: "Rugby", kind: "sport", art: g("#2b6f4a", "#0f291b") },
  { key: "athletisme", label: "Athlétisme", kind: "sport", art: g("#6f5f2b", "#29240f") },
];

export const formationFacets: Facet[] = [
  { key: "communication", label: "Communication", kind: "formation", art: g("#3a2b5f", "#140f24") },
  { key: "business", label: "Business", kind: "formation", art: g("#2b3a6f", "#0f1629") },
  { key: "forme", label: "Forme physique", kind: "formation", art: g("#5f4a2b", "#241910") },
  { key: "nutrition", label: "Nutrition", kind: "formation", art: g("#2b5f4a", "#10241b") },
  { key: "creativite", label: "Créativité", kind: "formation", art: g("#5f2b4a", "#241019") },
  { key: "finance", label: "Finance", kind: "formation", art: g("#244a4a", "#0c1a1a") },
];

export const allFacets: Facet[] = [...sportFacets, ...formationFacets];

/** Route of a facet page — one static page per facet. */
export function facetHref(f: Facet): string {
  return `/${f.kind === "sport" ? "sport" : "formation"}/${f.key}`;
}

export function getFacet(kind: Kind, key: string): Facet | undefined {
  return allFacets.find((f) => f.kind === kind && f.key === key);
}

/** A 1:1 tile (Android TV logo card) that opens the facet page, not a detail page. */
export function facetTile(f: Facet): MediaItem {
  return { id: `facet-${f.key}`, title: f.label, shape: "1:1", art: f.art, href: facetHref(f) };
}

/* ----------------------------------- HERO ---------------------------------- */

export const heroSlides: MediaItem[] = [
  {
    id: "hero-ucl", topics: ["football"],
    title: "Champions League — Finale en direct",
    subtitle: "Le sommet du football européen, ce soir à 21h00",
    art: g("#1f3a5f", "#0c1622"),
    live: "live",
    league: "UEFA Champions League",
    badge: "ÉVÉNEMENT",
  },
  {
    id: "hero-masterclass", topics: ["communication"],
    title: "Formation — Maîtriser la prise de parole",
    subtitle: "12 leçons avec une oratrice de renommée mondiale",
    art: g("#3a2b5f", "#140f24"),
    level: "Intermédiaire",
    lessons: 12,
    badge: "NOUVEAU",
  },
  {
    id: "hero-marathon", topics: ["forme"],
    title: "Marathon de préparation physique",
    subtitle: "Programme guidé 6 semaines, tous niveaux",
    art: g("#244a3a", "#0c1a14"),
    level: "Débutant",
    badge: "TENDANCE",
  },
];

/* ----------------------------------- HOME ---------------------------------- */

export const homeRows: Row[] = [
  {
    id: "continue",
    title: "Reprendre",
    items: [
      { id: "c1", topics: ["football"], title: "Tactique défensive moderne", art: g("#2b4a6f", "#101b29"), progress: 0.45, subtitle: "Sport · Analyse" },
      { id: "c2", topics: ["business"], title: "Négociation : les fondamentaux", art: g("#4a3a6f", "#191229"), progress: 0.7, subtitle: "Formation · 8 min restantes", level: "Débutant" },
      { id: "c3", topics: ["basket"], title: "NBA — Lakers vs Celtics", art: g("#5f3a2b", "#241310"), progress: 0.3, subtitle: "Sport · Replay", live: "replay" },
      { id: "c4", topics: ["forme"], title: "Yoga du matin", art: g("#2b5f4a", "#10241b"), progress: 0.6, subtitle: "Formation · 14 min", level: "Débutant" },
      { id: "c5", topics: ["moteur"], title: "Grand Prix — Résumé", art: g("#5f2b3a", "#241019"), progress: 0.2, subtitle: "Sport · Replay", live: "replay" },
    ],
  },
  {
    id: "live-now",
    title: "En direct maintenant",
    items: [
      { id: "l1", topics: ["football"], title: "Real Madrid — Man City", art: g("#1f3a5f", "#0c1622"), live: "live", clock: "72'", score: "2 - 1", league: "Champions League" },
      { id: "l2", topics: ["tennis"], title: "Roland-Garros — Demi-finale", art: g("#3a5f2b", "#16240f"), live: "live", clock: "Set 3", score: "6-4 3-6 2-1", league: "Tennis" },
      { id: "l3", topics: ["basket"], title: "NBA Playoffs — Game 5", art: g("#5f3a2b", "#241310"), live: "live", clock: "Q3 04:12", score: "78 - 74", league: "Basket" },
      { id: "l4", topics: ["moteur"], title: "MotoGP — Course", art: g("#5f2b3a", "#241019"), live: "live", clock: "Tour 18/24", league: "Moto" },
    ],
  },
  {
    id: "trending",
    title: "Tendances",
    items: [
      { id: "t1", topics: ["forme"], title: "Préparation mentale du champion", art: g("#3a2b5f", "#140f24"), subtitle: "Formation", level: "Avancé", duration: "22 min" },
      { id: "t2", topics: ["football"], title: "Les plus beaux buts de la saison", art: g("#244a3a", "#0c1a14"), subtitle: "Sport · Replay", live: "replay" },
      { id: "t3", topics: ["forme"], title: "HIIT — 20 minutes", art: g("#5f4a2b", "#241910"), subtitle: "Formation", level: "Intermédiaire", duration: "20 min" },
      { id: "t4", topics: ["football"], title: "Analyse : la possession", art: g("#2b4a6f", "#101b29"), subtitle: "Sport · Analyse" },
      { id: "t5", topics: ["nutrition"], title: "Cuisine du sportif", art: g("#5f2b4a", "#241019"), subtitle: "Formation", level: "Débutant", duration: "15 min" },
    ],
  },
];

/* ----------------------------------- SPORT --------------------------------- */

export const sportRows: Row[] = [
  {
    id: "sport-live",
    title: "En direct",
    items: [
      { id: "sl1", topics: ["football"], title: "Real Madrid — Man City", art: g("#1f3a5f", "#0c1622"), live: "live", clock: "72'", score: "2 - 1", league: "Football · Champions League" },
      { id: "sl2", topics: ["tennis"], title: "Roland-Garros — Demi", art: g("#3a5f2b", "#16240f"), live: "live", clock: "Set 3", score: "6-4 3-6 2-1", league: "Tennis · Grand Chelem" },
      { id: "sl3", topics: ["basket"], title: "Lakers — Celtics", art: g("#5f3a2b", "#241310"), live: "live", clock: "Q3 04:12", score: "78 - 74", league: "Basket · NBA" },
      { id: "sl4", topics: ["moteur"], title: "MotoGP — Le Mans", art: g("#5f2b3a", "#241019"), live: "live", clock: "Tour 18/24", league: "Moto · MotoGP" },
    ],
  },
  {
    id: "sport-upcoming",
    title: "À venir",
    items: [
      { id: "su1", topics: ["football"], title: "PSG — Bayern", art: g("#2b3a6f", "#0f1629"), live: "upcoming", startsIn: "Aujourd'hui 21:00", league: "Football" },
      { id: "su2", topics: ["athletisme"], title: "Finale 100m", art: g("#6f2b3a", "#290f16"), live: "upcoming", startsIn: "Demain 20:30", league: "Athlétisme" },
      { id: "su3", topics: ["rugby"], title: "Six Nations — France/Irlande", art: g("#2b6f4a", "#0f291b"), live: "upcoming", startsIn: "Samedi 15:00", league: "Rugby" },
      { id: "su4", topics: ["moteur"], title: "Grand Prix de Monaco", art: g("#6f5f2b", "#29240f"), live: "upcoming", startsIn: "Dimanche 14:00", league: "F1" },
    ],
  },
  {
    id: "sport-replay",
    title: "Replays & temps forts",
    items: [
      { id: "sr1", topics: ["football"], title: "Les plus beaux buts", art: g("#244a3a", "#0c1a14"), live: "replay", league: "Football" },
      { id: "sr2", topics: ["basket"], title: "Game 4 — Intégrale", art: g("#5f3a2b", "#241310"), live: "replay", league: "NBA" },
      { id: "sr3", topics: ["moteur"], title: "Résumé Grand Prix", art: g("#5f2b3a", "#241019"), live: "replay", league: "F1" },
      { id: "sr4", topics: ["tennis"], title: "Top 10 échanges", art: g("#3a5f2b", "#16240f"), live: "replay", league: "Tennis" },
    ],
  },
  {
    id: "sport-leagues",
    title: "Par discipline",
    items: sportFacets.map(facetTile),
  },
];

/* --------------------------------- FORMATION ------------------------------- */

export const formationRows: Row[] = [
  {
    id: "form-continue",
    title: "Continuer ma progression",
    items: [
      { id: "fc1", topics: ["business"], title: "Négociation : les fondamentaux", art: g("#4a3a6f", "#191229"), progress: 0.7, level: "Débutant", duration: "8 min restantes", instructor: "C. Laurent" },
      { id: "fc2", topics: ["forme"], title: "Préparation mentale", art: g("#3a2b5f", "#140f24"), progress: 0.35, level: "Avancé", duration: "14 min restantes", instructor: "M. Diallo" },
      { id: "fc3", topics: ["forme"], title: "Yoga du matin", art: g("#2b5f4a", "#10241b"), progress: 0.6, level: "Débutant", duration: "6 min restantes", instructor: "A. Roy" },
    ],
  },
  {
    id: "form-paths",
    title: "Parcours recommandés",
    items: [
      { id: "fp1", topics: ["communication"], title: "Devenir un meilleur orateur", shape: "2:3", art: g("#3a2b5f", "#140f24"), level: "Intermédiaire", lessons: 12, instructor: "E. Martin" },
      { id: "fp2", topics: ["business"], title: "Leadership & management", shape: "2:3", art: g("#2b3a6f", "#0f1629"), level: "Avancé", lessons: 9, instructor: "S. Petit" },
      { id: "fp3", topics: ["nutrition"], title: "Nutrition du sportif", shape: "2:3", art: g("#2b5f4a", "#10241b"), level: "Débutant", lessons: 7, instructor: "L. Bernard" },
      { id: "fp4", topics: ["creativite"], title: "Photographie créative", shape: "2:3", art: g("#5f4a2b", "#241910"), level: "Intermédiaire", lessons: 14, instructor: "N. Dubois" },
      { id: "fp5", topics: ["finance"], title: "Finances personnelles", shape: "2:3", art: g("#244a4a", "#0c1a1a"), level: "Débutant", lessons: 10, instructor: "R. Garcia" },
    ],
  },
  {
    id: "form-fitness",
    title: "Sport & bien-être",
    items: [
      { id: "ff1", topics: ["forme"], title: "HIIT — 20 minutes", art: g("#5f4a2b", "#241910"), level: "Intermédiaire", duration: "20 min", instructor: "T. Moreau" },
      { id: "ff2", topics: ["forme"], title: "Renforcement complet", art: g("#5f2b3a", "#241019"), level: "Avancé", duration: "35 min", instructor: "K. Lefèvre" },
      { id: "ff3", topics: ["forme"], title: "Étirements & mobilité", art: g("#2b5f4a", "#10241b"), level: "Débutant", duration: "18 min", instructor: "A. Roy" },
      { id: "ff4", topics: ["forme"], title: "Course : plan 5 km", art: g("#244a3a", "#0c1a14"), level: "Débutant", duration: "30 min", instructor: "P. Simon" },
    ],
  },
  {
    id: "form-topics",
    title: "Par thème",
    items: formationFacets.map(facetTile),
  },
];

/* ------------------------------- Lookups ----------------------------------- */

/** Every unique item across hero + all rows, keyed by id (first occurrence wins). */
export const allItems: MediaItem[] = (() => {
  const map = new Map<string, MediaItem>();
  for (const it of [...heroSlides, ...homeRows, ...sportRows, ...formationRows].flatMap(
    (x) => ("items" in x ? x.items : [x])
  )) {
    // Facet tiles carry their own href (a browse destination): they are not
    // content and must never get a /title detail page.
    if (!it.href && !map.has(it.id)) map.set(it.id, it);
  }
  return [...map.values()];
})();

export function getItem(id: string): MediaItem | undefined {
  return allItems.find((it) => it.id === id);
}

/** Same-kind items as a "More like this" rail (excludes the current item & logos). */
export function relatedTo(item: MediaItem): MediaItem[] {
  const kind = kindOf(item);
  return allItems
    .filter((it) => it.id !== item.id && it.shape !== "1:1" && kindOf(it) === kind)
    .slice(0, 8);
}

/** Content of a facet, newest-first is meaningless on mock data → source order. */
export function itemsInFacet(f: Facet): MediaItem[] {
  return allItems.filter((it) => it.topics?.includes(f.key));
}

/** Items of a kind that carry no facet tag — used to prove the tagging is complete. */
export function untaggedItems(): MediaItem[] {
  return allItems.filter((it) => !it.topics || it.topics.length === 0);
}
