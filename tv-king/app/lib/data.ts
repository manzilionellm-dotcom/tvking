// =========================================================
//  data.ts — Données MOCK typées (aucune marque réelle)
// =========================================================
//  Tous les titres sont fictifs et génériques. Les « affiches » sont
//  des dégradés CSS (couples from→to), remplaçables plus tard par de
//  vraies images sans changer le reste du code.
//
//  Le type MediaItem est volontairement riche : selon l'univers on
//  remplit des champs différents (un match a un score + une horloge,
//  un cours a un niveau + des leçons, une chaîne a un logo carré…).
// =========================================================

/// Les 5 univers de l'app. Chaque univers a sa couleur, son icône et
/// ses propres rangées de contenu.
export type Universe =
  | "sports"
  | "chaines"
  | "divertissement"
  | "enfants"
  | "journal";

/// Forme d'une vignette :
///   - "wide"   = 16:9 (vidéos, épisodes, directs)
///   - "square" = 1:1  (logos de chaînes, sujets ronds)
///   - "poster" = 2:3  (films, séries — affiches verticales)
export type Shape = "wide" | "square" | "poster";

/// État temporel d'un contenu (pour le badge coloré).
export type BadgeKind = "live" | "upcoming" | "replay" | "new" | "none";

/// Niveau pédagogique (cours, tutoriels).
export type Level = "debutant" | "intermediaire" | "avance";

/// Un dégradé d'« affiche » : deux couleurs CSS.
export interface Art {
  from: string;
  to: string;
}

/// L'unité de contenu universelle de l'app.
export interface MediaItem {
  id: string;
  title: string;
  subtitle?: string;
  universe: Universe;
  shape: Shape;
  art: Art;
  badge?: BadgeKind;
  /// Direct en cours.
  live?: boolean;
  /// Horloge / minute de jeu affichée en overlay (ex. "63'", "20:45").
  clock?: string;
  /// Score d'un match (ex. "2 – 1").
  score?: string;
  /// Démarre dans X (ex. "dans 25 min").
  startsIn?: string;
  /// Progression de lecture 0→1 (barre « Reprendre »).
  progress?: number;
  /// Niveau pédagogique.
  level?: Level;
  /// Durée lisible (ex. "1 h 48").
  duration?: string;
  /// Nombre de leçons (cours).
  lessons?: number;
  /// Nom de chaîne.
  channel?: string;
  /// Ligue / compétition (sport).
  league?: string;
  /// Intervenant / présentateur.
  instructor?: string;
}

// ---------------------------------------------------------
//  Dégradés par univers (désaturés, reposants — cf. design system)
// ---------------------------------------------------------
const G = {
  sports: { from: "#0f3a30", to: "#58c9a3" },
  sports2: { from: "#13322c", to: "#2f8f76" },
  chaines: { from: "#3a2c10", to: "#e3b96b" },
  chaines2: { from: "#2c2410", to: "#c9962f" },
  divert: { from: "#241c4a", to: "#b3a4ff" },
  divert2: { from: "#1c1838", to: "#7c6ce0" },
  enfants: { from: "#123a4a", to: "#7fc7ff" },
  enfants2: { from: "#10303f", to: "#5fb0ef" },
  journal: { from: "#332512", to: "#d8a657" },
  journal2: { from: "#2a2010", to: "#b98a3e" },
} as const;

// ---------------------------------------------------------
//  Catalogue (~36 entrées réparties sur les 5 univers)
// ---------------------------------------------------------
export const MEDIA: MediaItem[] = [
  // ===== SPORTS =====
  {
    id: "sp-derby-lumiere",
    title: "Derby des Lumières",
    subtitle: "Championnat Étoile · Journée 12",
    universe: "sports",
    shape: "wide",
    art: G.sports,
    badge: "live",
    live: true,
    clock: "63'",
    score: "2 – 1",
    league: "Championnat Étoile",
  },
  {
    id: "sp-tournoi-or",
    title: "Tournoi d'Or — Finale",
    subtitle: "Tennis · Court central",
    universe: "sports",
    shape: "wide",
    art: G.sports2,
    badge: "live",
    live: true,
    clock: "Set 2",
    score: "6-4 · 3-2",
    league: "Grand Circuit",
  },
  {
    id: "sp-marathon-cite",
    title: "Marathon de la Cité",
    subtitle: "Athlétisme",
    universe: "sports",
    shape: "wide",
    art: G.sports,
    badge: "upcoming",
    startsIn: "dans 25 min",
    league: "Course sur route",
  },
  {
    id: "sp-basket-cometes",
    title: "Comètes vs Titans",
    subtitle: "Basket · Demi-finale",
    universe: "sports",
    shape: "wide",
    art: G.sports2,
    badge: "upcoming",
    startsIn: "dans 1 h 10",
    league: "Ligue des Astres",
  },
  {
    id: "sp-rugby-vallee",
    title: "Choc de la Vallée",
    subtitle: "Rugby · Replay",
    universe: "sports",
    shape: "wide",
    art: G.sports,
    badge: "replay",
    duration: "1 h 52",
    progress: 0.35,
    league: "Coupe des Cimes",
  },
  {
    id: "sp-cyclisme-cols",
    title: "La Ronde des Cols",
    subtitle: "Cyclisme · Étape reine",
    universe: "sports",
    shape: "wide",
    art: G.sports2,
    badge: "replay",
    duration: "2 h 30",
    league: "Tour des Massifs",
  },
  {
    id: "sp-natation-bleue",
    title: "Vague Bleue — 200 m",
    subtitle: "Natation",
    universe: "sports",
    shape: "square",
    art: G.sports,
    badge: "upcoming",
    startsIn: "dans 40 min",
    league: "Open Aquatique",
  },

  // ===== CHAÎNES (TV en direct) =====
  {
    id: "ch-or-info",
    title: "Or Info 24",
    subtitle: "Information continue",
    universe: "chaines",
    shape: "square",
    art: G.chaines,
    badge: "live",
    live: true,
    channel: "Canal 1",
  },
  {
    id: "ch-cinema-royal",
    title: "Cinéma Royal",
    subtitle: "Films · maintenant : « L'Aube »",
    universe: "chaines",
    shape: "square",
    art: G.chaines2,
    badge: "live",
    live: true,
    channel: "Canal 7",
  },
  {
    id: "ch-musique-ambre",
    title: "Ambre Musique",
    subtitle: "Clips & concerts",
    universe: "chaines",
    shape: "square",
    art: G.chaines,
    badge: "live",
    live: true,
    channel: "Canal 12",
  },
  {
    id: "ch-doc-monde",
    title: "Monde & Découvertes",
    subtitle: "Documentaires",
    universe: "chaines",
    shape: "square",
    art: G.chaines2,
    badge: "live",
    live: true,
    channel: "Canal 18",
  },
  {
    id: "ch-cuisine-fine",
    title: "Cuisine Fine",
    subtitle: "Émissions culinaires",
    universe: "chaines",
    shape: "square",
    art: G.chaines,
    badge: "live",
    live: true,
    channel: "Canal 22",
  },
  {
    id: "ch-voyage-doree",
    title: "Évasion Dorée",
    subtitle: "Voyages",
    universe: "chaines",
    shape: "square",
    art: G.chaines2,
    badge: "live",
    live: true,
    channel: "Canal 31",
  },

  // ===== DIVERTISSEMENT (films / séries / spectacles) =====
  {
    id: "dv-aube-silence",
    title: "L'Aube du Silence",
    subtitle: "Film · Drame",
    universe: "divertissement",
    shape: "poster",
    art: G.divert,
    badge: "new",
    duration: "1 h 48",
    progress: 0.6,
  },
  {
    id: "dv-cite-verre",
    title: "La Cité de Verre",
    subtitle: "Série · Saison 2",
    universe: "divertissement",
    shape: "poster",
    art: G.divert2,
    badge: "new",
    duration: "8 épisodes",
  },
  {
    id: "dv-derniere-scene",
    title: "La Dernière Scène",
    subtitle: "Spectacle · Théâtre",
    universe: "divertissement",
    shape: "poster",
    art: G.divert,
    duration: "2 h 05",
  },
  {
    id: "dv-ombres-portees",
    title: "Ombres Portées",
    subtitle: "Film · Thriller",
    universe: "divertissement",
    shape: "poster",
    art: G.divert2,
    duration: "2 h 12",
    progress: 0.18,
  },
  {
    id: "dv-melodie-nuit",
    title: "Mélodie de Nuit",
    subtitle: "Concert · Live",
    universe: "divertissement",
    shape: "poster",
    art: G.divert,
    duration: "1 h 30",
  },
  {
    id: "dv-rire-jaune",
    title: "Rire Jaune",
    subtitle: "One-man-show",
    universe: "divertissement",
    shape: "poster",
    art: G.divert2,
    duration: "1 h 15",
  },
  {
    id: "dv-horizon-perdu",
    title: "Horizon Perdu",
    subtitle: "Série · Aventure",
    universe: "divertissement",
    shape: "wide",
    art: G.divert,
    badge: "new",
    duration: "6 épisodes",
  },

  // ===== ENFANTS =====
  {
    id: "en-petits-renards",
    title: "Les Petits Renards",
    subtitle: "Dessin animé",
    universe: "enfants",
    shape: "wide",
    art: G.enfants,
    badge: "new",
    duration: "22 min",
    progress: 0.4,
  },
  {
    id: "en-robot-tournesol",
    title: "Robot Tournesol",
    subtitle: "Aventure rigolote",
    universe: "enfants",
    shape: "wide",
    art: G.enfants2,
    duration: "18 min",
  },
  {
    id: "en-ocean-magique",
    title: "L'Océan Magique",
    subtitle: "Sous la mer",
    universe: "enfants",
    shape: "wide",
    art: G.enfants,
    duration: "24 min",
  },
  {
    id: "en-comptines-or",
    title: "Comptines en Or",
    subtitle: "Chansons à chanter",
    universe: "enfants",
    shape: "square",
    art: G.enfants2,
    duration: "35 min",
  },
  {
    id: "en-dino-copains",
    title: "Dino & ses Copains",
    subtitle: "Dessin animé",
    universe: "enfants",
    shape: "wide",
    art: G.enfants,
    duration: "20 min",
  },
  {
    id: "en-etoiles-rieuses",
    title: "Les Étoiles Rieuses",
    subtitle: "Au pays des rêves",
    universe: "enfants",
    shape: "square",
    art: G.enfants2,
    duration: "16 min",
  },

  // ===== JOURNAL (actu / info) =====
  {
    id: "jo-grand-journal",
    title: "Le Grand Journal",
    subtitle: "Édition du soir",
    universe: "journal",
    shape: "wide",
    art: G.journal,
    badge: "live",
    live: true,
    channel: "Or Info 24",
  },
  {
    id: "jo-eco-matin",
    title: "Éco du Matin",
    subtitle: "Économie",
    universe: "journal",
    shape: "wide",
    art: G.journal2,
    badge: "replay",
    duration: "26 min",
  },
  {
    id: "jo-monde-ce-soir",
    title: "Le Monde ce Soir",
    subtitle: "International",
    universe: "journal",
    shape: "wide",
    art: G.journal,
    badge: "upcoming",
    startsIn: "dans 15 min",
  },
  {
    id: "jo-meteo-doree",
    title: "Météo Dorée",
    subtitle: "Prévisions",
    universe: "journal",
    shape: "square",
    art: G.journal2,
    badge: "live",
    live: true,
  },
  {
    id: "jo-debat-citoyen",
    title: "Le Débat Citoyen",
    subtitle: "Société",
    universe: "journal",
    shape: "wide",
    art: G.journal,
    badge: "replay",
    duration: "52 min",
    progress: 0.22,
  },
  {
    id: "jo-culture-info",
    title: "Culture Info",
    subtitle: "Arts & spectacles",
    universe: "journal",
    shape: "wide",
    art: G.journal2,
    badge: "replay",
    duration: "31 min",
  },

  // ===== Quelques cours (niveau/leçons/intervenant) =====
  {
    id: "dv-cours-guitare",
    title: "Guitare en Douceur",
    subtitle: "Cours · Musique",
    universe: "divertissement",
    shape: "square",
    art: G.divert,
    level: "debutant",
    lessons: 12,
    instructor: "Camille R.",
  },
  {
    id: "sp-cours-yoga",
    title: "Yoga du Matin",
    subtitle: "Cours · Bien-être",
    universe: "sports",
    shape: "square",
    art: G.sports2,
    level: "intermediaire",
    lessons: 8,
    instructor: "Léa M.",
    progress: 0.5,
  },
];

// ---------------------------------------------------------
//  Lookups
// ---------------------------------------------------------

/// Index id → item (recherche O(1)).
const BY_ID: Map<string, MediaItem> = new Map(MEDIA.map((m) => [m.id, m]));

/// Récupère un item par id (undefined si inconnu).
export function getById(id: string): MediaItem | undefined {
  return BY_ID.get(id);
}

/// Tous les items d'un univers.
export function getByUniverse(u: Universe): MediaItem[] {
  return MEDIA.filter((m) => m.universe === u);
}

/// « Reprendre » : les contenus commencés (0 < progress < 1).
export function getContinueWatching(): MediaItem[] {
  return MEDIA.filter((m) => (m.progress ?? 0) > 0 && (m.progress ?? 0) < 1);
}

/// Directs en cours (tous univers confondus).
export function getLiveNow(): MediaItem[] {
  return MEDIA.filter((m) => m.live === true);
}

/// Sélection « à la une » pour le Hero billboard (3 items marquants).
export function getHeroItems(): MediaItem[] {
  const ids = ["sp-derby-lumiere", "dv-aube-silence", "jo-grand-journal"];
  return ids
    .map((id) => BY_ID.get(id))
    .filter((m): m is MediaItem => m !== undefined);
}

/// Recherche texte simple (titre/sous-titre/chaîne), insensible à la casse.
export function searchMedia(query: string): MediaItem[] {
  const q = query.trim().toLowerCase();
  if (!q) return [];
  return MEDIA.filter((m) =>
    [m.title, m.subtitle, m.channel, m.league, m.instructor]
      .filter(Boolean)
      .some((field) => (field as string).toLowerCase().includes(q)),
  );
}

/// Métadonnées d'affichage de chaque univers (label, icône, couleur).
export interface UniverseMeta {
  id: Universe;
  label: string;
  /// Pictogramme emoji (lisible même par un enfant qui ne lit pas).
  icon: string;
  /// Variable CSS de l'accent de l'univers.
  accentVar: string;
  /// Phrase d'accueil explicite (narration / sous-titre).
  hint: string;
}

export const UNIVERSES: UniverseMeta[] = [
  {
    id: "sports",
    label: "Sports",
    icon: "🏆",
    accentVar: "var(--u-sports)",
    hint: "Matchs en direct, à venir et en rediffusion",
  },
  {
    id: "chaines",
    label: "Chaînes",
    icon: "📺",
    accentVar: "var(--u-chaines)",
    hint: "La télévision en direct, chaîne par chaîne",
  },
  {
    id: "divertissement",
    label: "Divertissement",
    icon: "🎬",
    accentVar: "var(--u-divertissement)",
    hint: "Films, séries et spectacles",
  },
  {
    id: "enfants",
    label: "Enfants",
    icon: "🧸",
    accentVar: "var(--u-enfants)",
    hint: "Dessins animés et chansons, tout en images",
  },
  {
    id: "journal",
    label: "Journal",
    icon: "🗞️",
    accentVar: "var(--u-journal)",
    hint: "L'actualité et l'information en continu",
  },
];

/// Métadonnées d'un univers par id.
export function getUniverseMeta(u: Universe): UniverseMeta {
  // Le `!` est sûr : UNIVERSES couvre tous les membres de l'union Universe.
  return UNIVERSES.find((x) => x.id === u)!;
}
