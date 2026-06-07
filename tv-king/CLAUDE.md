# NOVA+ — guide du dépôt (architecture & conventions)

Application de **streaming TV premium et universelle** pensée « 10-foot UI »
(utilisée à ~3 m avec une télécommande). Objectif : à la fois **futuriste /
premium** et **radicalement simple** — utilisable sans apprentissage par une
personne âgée, un jeune enfant, ou un adulte amateur de nouveautés.

> Principe directeur : **« personne n'est perdu, jamais »**. À tout instant on
> sait OÙ on est, CE QU'on peut faire, COMMENT revenir. Un seul élément a le
> focus et il est impossible de le perdre. Tout se fait avec 5 touches
> (↑ ↓ ← → + OK) plus une touche RETOUR toujours prévisible.

## Stack

- **Next.js 15** (App Router) + **TypeScript strict** + **Tailwind CSS v4**.
- **Aucune librairie de composants externe** : tout est fait main.
- Visuels = **dégradés CSS** (pas d'images binaires), remplaçables par de
  vraies affiches sans refonte.
- Données = **mock typé** dans `app/lib/data.ts`. Aucune marque réelle, aucun
  secret / token / clé d'API.
- Tests : **vitest** + **jsdom** + **@testing-library/react** + **jest-axe**.
- Cible de déploiement : **Vercel**.

## Comment lancer

```bash
npm install      # installe les dépendances
npm run dev      # serveur de dev (http://localhost:3000)
npm run build    # build de production (type-check + lint inclus)
npm run lint     # ESLint (config next/core-web-vitals + next/typescript)
npm test         # suite de tests (vitest)
```

Navigation **au clavier** : flèches = déplacer le focus, **Entrée/Espace** =
OK, **Échap / Retour arrière** = RETOUR. La souris fonctionne aussi.

## Architecture

```
tv-king/
├── app/
│   ├── globals.css            # DESIGN SYSTEM (tokens, focus, modes, animations)
│   ├── layout.tsx             # <html> + PreferencesProvider + AppFrame
│   ├── page.tsx               # Accueil (Hero + rangées)
│   ├── lib/
│   │   ├── data.ts            # MediaItem + catalogue mock + lookups + UNIVERSES
│   │   ├── preferences.tsx    # Profils + réglages (contexte + localStorage)
│   │   ├── narration.ts       # Narration vocale (Web Speech API)
│   │   ├── sound.ts           # Retours sonores doux (WebAudio, sans binaire)
│   │   ├── spatial.ts         # Scoring de navigation D-pad (PUR, testé)
│   │   └── mylist.ts          # « Ma liste » (favoris localStorage)
│   ├── components/
│   │   ├── SpatialNav.tsx     # Navigation spatiale (D-pad, focus, RETOUR)
│   │   ├── AppFrame.tsx       # Profil → shell ; monte SpatialNav
│   │   ├── Sidebar.tsx        # Rail gauche (collapsable) + 5 univers
│   │   ├── HelpBar.tsx        # Barre d'aide permanente (◀▶ OK ⬅)
│   │   ├── ProfileGate.tsx    # Choix de profil au 1er lancement
│   │   ├── Hero.tsx           # Billboard d'accueil (autoplay maîtrisé)
│   │   ├── Row.tsx            # Rangée horizontale
│   │   ├── MediaCard.tsx      # Vignette (3 formes 16:9 / 1:1 / 2:3)
│   │   ├── Badge.tsx          # LiveBadge + LevelBadge
│   │   ├── Preferences.tsx    # Écran Réglages
│   │   ├── Player.tsx         # Lecteur + « À suivre » annulable
│   │   ├── Multiview.tsx      # Multi-écran sport
│   │   ├── VoiceButton.tsx    # Recherche vocale (repli gracieux)
│   │   └── Splash.tsx         # Écran d'attente bref
│   ├── sports/ chaines/ divertissement/ enfants/ journal/   # 5 univers
│   ├── sports/multiview/      # multi-écran
│   ├── title/[slug]/          # fiche détail
│   ├── watch/[slug]/          # lecteur
│   ├── search/ list/ reglages/
├── docs/RESEARCH-TV-UX.md     # recherche UX/accessibilité/confort (sourcée)
└── test/                      # spatial / data / a11y / smoke
```

## Design system (`app/globals.css`)

Tout passe par des **variables CSS** sur `:root`. Décisions sourcées dans
`docs/RESEARCH-TV-UX.md`.

- **Surfaces** : jamais de noir pur → `--bg:#121212`, surfaces `#1a1a1c` …
  `#36363c`.
- **Texte** : jamais de blanc pur → `--text-high:.92`, `--text-medium:.62`,
  `--text-disabled:.38` (halation évitée).
- **Palette or désaturée** : `--gold`, `--gold-strong`, `--gold-deep`,
  `--gold-grad`, plus `--royal`, `--live` (rouge adouci), `--focus`.
- **Accents par univers** : `--u-sports`, `--u-chaines`, `--u-divertissement`,
  `--u-enfants`, `--u-journal`.
- **Mise à l'échelle globale** : `html { font-size: clamp(...) * var(--ui-scale) }`
  → 720p lisible, 4K net, sans zoomer le layout.
- **Safe-area** : `--safe-x` / `--safe-y` (overscan TV, ajustable).
- **Modes** pilotés par des attributs `data-*` sur `<html>` :
  `data-high-contrast`, `data-reduced-motion`, `data-eye-rest`,
  `data-ambilight`, `data-parallax`, `data-vip`, `data-profile`.

## Accessibilité (prioritaire)

- **Profils** Senior / Enfants / Standard (`app/lib/preferences.tsx`) :
  changent réellement échelle, contraste, densité, animations, narration.
- **Réglages persistés** (localStorage) : taille UI, overscan, contraste élevé
  (cible AAA 7:1), réduction des animations, narration vocale, repos des yeux,
  effets, VIP.
- **Navigation spatiale** (`SpatialNav` + `lib/spatial.ts`) : focus unique,
  jamais perdu, mémoire de focus par page, RETOUR prévisible.
- **Barre d'aide** permanente, **aria-label** clair sur chaque focusable,
  **narration** vocale du focus et des confirmations. Respect de
  `prefers-reduced-motion`.

## Couche futuriste (toutes désactivables, respectent reduced-motion)

Ambilight (lueur de fond adaptative), parallaxe (relief 3D au focus), recherche
/ commande **vocale** (repli gracieux), **multi-écran** sport (un seul audio
actif), retours **sonores** WebAudio, mode **repos des yeux** (tons chauds,
luminance douce), **édition VIP** (or riche, halo, finitions).

## Branchement au panel 7 MOTION (licence / essai)

NOVA+ est une app **web** : elle génère un **MAC virtuel** stable par
installation (`MK:XX:XX:XX:XX:XX`, persisté en localStorage), exactement comme
les apps mobiles du projet.

- `app/lib/license.ts` — MAC virtuel + appels `POST /api/heartbeat` et
  `GET /api/status/:mac` sur le **même backend** que les apps mobiles
  (`NEXT_PUBLIC_LICENSE_BASE`, défaut `https://99999.7themotion.com`) + logique
  PURE de blocage (testée).
- `LicenseProvider` fait un heartbeat au démarrage → l'appareil **apparaît
  automatiquement** dans le panel admin (Clients / Appareils), démarre un
  **essai 7 jours**, puis se bloque.
- `SubscriptionGate` : écran bloquant (essai fini / gelé / banni) qui affiche
  le **code (MAC)** à communiquer pour l'activation + bouton « J'ai payé —
  rafraîchir ». `TrialBadge` : rappel discret des jours d'essai restants.
- **Activation** : depuis le panel, par MAC + plan (crédits) — aucun code panel
  à modifier (l'auto-enregistrement existe déjà). C'est de l'infra de **licence
  / accès**, pas de distribution de contenu/flux.
- Repli **hors-ligne** : si le serveur est injoignable, on ne bloque pas
  (`shouldBlock` est fail-open) pour ne pas punir un utilisateur légitime.

> Suite possible (comme les apps mobiles) : vérifier la **signature Ed25519**
> des réponses (anti-faux-serveur) une fois le secret `LICENSE_SIGNING_KEY`
> posé côté Worker.

## Conventions

- **Commentaires en français**, abondants et explicatifs (support pédagogique).
- **TypeScript strict** (`noUnusedLocals`, etc.). Pas de `any` dans `app/`.
- **Couleurs/tailles uniquement via les variables CSS** du design system — pas
  de `#hex` magique disséminé ni de tailles en dur arbitraires.
- **Aucune marque réelle, aucun contenu protégé, aucun secret** dans le code.
- Composants client (`"use client"`) seulement quand nécessaire (état, effets,
  navigateur) ; le reste reste serveur.

## Tests

- `test/spatial.test.ts` — logique de navigation (scoring directionnel).
- `test/data.test.ts` — intégrité des données et des lookups.
- `test/a11y.test.tsx` — axe (jest-axe) + présence d'aria-label sur les
  focusables.
- `test/smoke.test.ts` — sanity de l'environnement.

Après chaque grande étape : `npm run build`, `npm run lint`, `npm test` doivent
être **verts** avant de continuer.

## Trois scénarios visés (acceptance)

1. **Grand-mère** : trouve et lance le **Journal** en ≤ 3 actions (rail →
   Journal → un programme en direct).
2. **Enfant** : ouvre les **dessins animés** sans savoir lire (icône 🧸 dans le
   rail → grille de gros pictogrammes ▶).
3. **Amateur de tech** : active **multi-écran** + **commande vocale** + **mode
   VIP** dans Réglages.

## Limite connue / honnêteté

Pas de capture d'écran automatisée ici (aucun navigateur headless dans
l'environnement de build) : la validation visuelle se fait via le rendu réel
(`npm run dev`). Les bénéfices « confort visuel » sont formulés sans
surpromesse médicale (cf. nuance AAO dans `docs/RESEARCH-TV-UX.md`).
