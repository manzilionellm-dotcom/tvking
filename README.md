# TV King 👑

Application de streaming **pensée pour la télévision** (expérience « 10-foot UI »),
centrée sur deux univers : **Sport** (direct, scores, replays) et **Formation**
(parcours par niveau, progression, intervenants).

Le design n'est pas inventé : il applique des normes officielles et des bonnes
pratiques documentées. Le référentiel complet, sourcé, est dans
[`docs/RESEARCH-TV-UX.md`](docs/RESEARCH-TV-UX.md).

## Principes appliqués

- **Adaptation à toute TV** — canvas 1920×1080 (16:9) ; la taille de police racine
  est fonction de `100vw`, donc tout (en `rem`) scale proportionnellement du 720p
  au 4K, sans zoom. Zone de sécurité ~5 % par bord (Android TV 48dp/27dp, tvOS 90pt/60pt).
- **Couleurs reposantes** — fond `#121212` (jamais de noir pur), texte blanc à
  87/60/38 % d'opacité (jamais de blanc pur, anti-halation), accents désaturés,
  contraste WCAG AA (≥ 4.5:1).
- **Navigation D-pad** — déplacement du focus vers l'élément le plus proche
  (`SpatialNav`), état de focus net (anneau + agrandissement + élévation).
- **UX engageante mais maîtrisée** — hero billboard, rangées personnalisées,
  « Reprendre », autoplay « À suivre » **avec compte à rebours annulable**.
- **Réglages** — taille du texte et compensation d'overscan ajustables par
  l'utilisateur (persistés), avec aperçu de la zone de sécurité.

## Expérience mobile (« pocket UI »)

Sous 768 px, la même app devient une application de poche premium — le rendu
TV est inchangé au-delà :

- **Coquille native** — tab bar inférieure en verre dépoli (5 onglets, état
  actif doré), header translucide qui laisse le hero passer dessous, zones
  sûres du notch et de la barre d'accueil (`viewport-fit=cover` +
  `env(safe-area-inset-*)`).
- **Gestes** — hero **swipeable**, rangées en carrousels à **scroll-snap**
  avec carte suivante qui dépasse (invitation au geste), retour tactile
  (`:active`) sur chaque élément.
- **Lecteur tactile** — tap pour afficher/masquer les contrôles (auto-masqués
  après 3 s), **double-tap ±10 s** avec flash visuel et retour haptique,
  timeline **scrubbable** au doigt.
- **Recherche réelle** — champ de saisie avec résultats instantanés,
  insensibles aux accents (le clavier est gratuit sur téléphone).
- **Installable (PWA)** — `manifest.webmanifest` + icône couronne (SVG),
  plein écran une fois épinglée à l'écran d'accueil.

## Structure

```
app/
  layout.tsx                  Shell : sidebar TV + coquille mobile + D-pad + préférences
  page.tsx                    Accueil (hero + rangées)
  sport/  formation/          Catégories (live/replay ; niveaux/progression)
  title/[slug]/               Page détail d'un contenu
  watch/[slug]/               Lecteur + « À suivre »
  search/  list/  reglages/   Recherche, Ma liste, Réglages
  components/                 Sidebar, MobileNav, Hero, Row, MediaCard, Player…
  lib/data.ts                 Modèle de contenu (mock) + lookups
  manifest.webmanifest        PWA (installation sur l'écran d'accueil)
  icon.svg                    Icône couronne (favicon + icône d'app)
docs/RESEARCH-TV-UX.md        Recherche sourcée (le référentiel de conception)
```

## Démarrer

```bash
npm install
npm run dev      # http://localhost:3000
npm run build    # build de production
npm run lint
```

> Navigation : flèches (D-pad) pour déplacer le focus, Entrée/Espace pour activer.
> Les visuels sont des dégradés (pas d'images binaires) — à remplacer par de
> vraies affiches/logos et à brancher sur de vraies données (API sport / cours).
