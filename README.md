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

## Structure

```
app/
  layout.tsx                  Shell : sidebar + navigation D-pad + préférences
  page.tsx                    Accueil (hero + rangées)
  sport/  formation/          Catégories (live/replay ; niveaux/progression)
  title/[slug]/               Page détail d'un contenu
  watch/[slug]/               Lecteur + « À suivre »
  search/  list/  reglages/   Recherche, Ma liste, Réglages
  components/                 Sidebar, Hero, Row, MediaCard, Badge, Player…
  lib/data.ts                 Modèle de contenu (mock) + lookups
server/edge/                  Proxy de bord : déduplication de flux + cache local
docs/RESEARCH-TV-UX.md        Recherche sourcée (le référentiel de conception)
```

Le proxy de bord (`server/edge/`) est un service Node autonome : une connexion
montante par slot de compte maître (M3U) quel que soit le nombre de lecteurs,
bascule de chaîne sans déconnecter les clients, cache circulaire en mémoire,
diffusion locale sans copie, suppression de toute métadonnée client avant la
sortie WAN, et un tableau de bord d'administration temps réel.
Voir [`server/edge/README.md`](server/edge/README.md).

## Démarrer

```bash
npm install
npm run dev      # http://localhost:3000
npm run build    # build de production
npm run lint
npm test         # suite vitest (app + proxy de bord)
npm run edge     # proxy de bord (voir server/edge/README.md pour la config)
```

> Navigation : flèches (D-pad) pour déplacer le focus, Entrée/Espace pour activer.
> Les visuels sont des dégradés (pas d'images binaires) — à remplacer par de
> vraies affiches/logos et à brancher sur de vraies données (API sport / cours).
