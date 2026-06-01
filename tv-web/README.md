# 7 MOTION — version TV (`tv-web/`)

> Lecteur IPTV multi-plateformes, **web-first**. Une seule base
> React + TypeScript empaquetée pour 4 cibles : navigateur desktop /
> Electron, Android TV (WebView), LG webOS, Samsung Tizen.

---

## Statut

**v0.1.0 — Fondation (commit en cours)**.

| Brique | Statut |
|---|---|
| Squelette Vite + React + TS + lint + tests | ✅ |
| Parser M3U / M3U8 extended | ✅ (13 tests) |
| Modèle `Channel` | ✅ |
| Abstraction `MediaPlayer` | ✅ |
| Implémentation `WebMediaPlayer` (hls.js + `<video>`) | ✅ |
| UI shell minimal (input URL → liste → lecteur) | ✅ |
| Branding tokens 7 MOTION (palette ember/charcoal) | ✅ |
| Client Xtream Codes | ⏳ Phase 2 |
| EPG XMLTV | ⏳ Phase 2 |
| TMDB enrichissement films/séries | ⏳ Phase 2 |
| D-pad navigation spatiale | ⏳ Phase 2 |
| Empaquetage Electron | ⏳ Phase 2 |
| Empaquetage Tizen `.wgt` | ⏳ Phase 3 |
| Empaquetage webOS `.ipk` | ⏳ Phase 3 |
| Empaquetage Android TV WebView wrapper | ⏳ Phase 3 |

---

## Démarrage rapide (dev local)

Prérequis : Node.js ≥ 20, npm ≥ 10.

```bash
cd tv-web
npm install
npm run dev        # serveur Vite, http://localhost:5173
npm run test       # 13 tests parser M3U
npm run typecheck  # tsc --noEmit
npm run lint       # eslint
npm run build      # bundle de prod dans dist/
```

Pour tester sur une TV en LAN :

1. `npm run dev` (le serveur écoute sur 0.0.0.0:5173).
2. Sur la TV, ouvre le navigateur intégré et tape
   `http://<IP-de-ton-pc>:5173/`.
3. Colle ton URL M3U → la liste s'affiche → un clic lance la lecture.

---

## Architecture

```
tv-web/
├── public/                    Assets statiques (favicon, etc.)
├── src/
│   ├── core/                  Logique métier — 100% pure TS, testable
│   │   ├── models/            Channel, Movie, Series (immuables)
│   │   ├── parsers/           M3U, XMLTV (à venir)
│   │   ├── clients/           Xtream Codes API, TMDB (à venir)
│   │   └── player/            Abstraction MediaPlayer + impl Web
│   ├── branding/              Palette 7 MOTION (miroir Flutter)
│   ├── ui/                    Composants React (à étoffer Phase 2)
│   ├── hooks/                 useFocus, useChannel, etc. (Phase 2)
│   ├── App.tsx                Shell de l'app
│   └── main.tsx               Bootstrap React
└── test/                      Vitest — tests purs, jsdom pour les DOM-light
```

### Pourquoi une **abstraction MediaPlayer** ?

Le lecteur vidéo est LE point qui diverge le plus selon la plateforme :

| Plateforme | Lecteur natif |
|---|---|
| Desktop / Electron / Android TV WebView | `<video>` + **hls.js** (fonctionne via Media Source Extensions) |
| LG webOS | `<video>` HTML5 natif (pipeline média webOS) |
| Samsung Tizen | API **AVPlay** (obligatoire pour certaines TVs anciennes) |
| Android TV natif (Phase 3+) | **ExoPlayer / Media3** via bridge JS |

`src/core/player/player_interface.ts` définit le contrat commun
(`open / pause / resume / seek / getAudioTracks / …`). Le reste de
l'app ne dépend QUE de cette interface — quand on portera sur Tizen,
on écrira `TizenAvPlayer.ts` sans toucher au reste.

### Pourquoi cibler **ES2020** dans `tsconfig.json` ?

Les WebViews Tizen/webOS sont **figées à la fabrication du téléviseur**
et ne se mettent jamais à jour. Un TV de 2020 a un Chromium ~84.
ES2020 est supporté stable depuis Chromium 80 → marge confortable.
ES2022 (top-level await, error cause, etc.) casserait sur ces TVs.

### Branding

`src/branding/tokens.ts` est le miroir TypeScript de
`lib/core/theme/app_colors.dart` du projet Flutter. Si la palette
phone change, il faut **manuellement** répercuter ici (et inversement) —
Dart et TS ne peuvent pas se partager un fichier source. À l'avenir
on pourra générer les deux depuis un fichier YAML/JSON unique si la
dérive devient un problème.

---

## Tests

`vitest` + `jsdom`. 13 tests couvrant les cas standard et edge du
parser M3U (BOM, CRLF, EXTGRP override, virgules dans le nom, etc.).

```bash
npm run test           # une fois
npm run test:watch     # mode développeur
```

Pas de test du `WebMediaPlayer` pour l'instant (nécessite mocking
de `<video>` et de hls.js — Phase 2 quand on aura des bugs concrets
à reproduire).

---

## Phase 2 (roadmap court terme)

1. **Client Xtream Codes** (`src/core/clients/xtream.ts`) — endpoints
   `player_api.php?action=get_live_streams` etc.
2. **Parser XMLTV** pour EPG, mappé sur `tvg-id`.
3. **Persistance LocalStorage** : dernière playlist, favoris, dernière
   chaîne jouée.
4. **D-pad navigation** : intégrer `react-tv-space-navigation` (Lib
   LRUD-based). Première intégration sur la liste de chaînes.
5. **Empaquetage Electron** : `electron-builder` config pour
   `.exe` / `.dmg` / `.AppImage`.

## Phase 3 (TVs natives)

1. **Tizen** : `ares-package` config + `config.xml`, soumission Samsung
   Seller Office.
2. **webOS** : `ares-package` + `appinfo.json`, soumission LG Seller
   Lounge.
3. **Android TV** : WebView wrapper Kotlin minimal + intent handlers
   pour la télécommande.

## Phase 4 (enrichissement)

- TMDB metadata pour films/séries (clé API user-fournie ou via env
  côté backend).
- Contrôle parental (PIN, masquage de catégories).
- Reprise de lecture (`continuer à regarder`).
- Recherche full-text.
- Multi-piste audio / sous-titres exposés dans l'UI.

---

## Conventions de code

- Commentaires en français, abondants, pédagogiques (cf. `AGENTS.md` racine).
- TS strict (`noUncheckedIndexedAccess`, `strict`, etc.).
- Aucune valeur magique (couleur, taille) — toujours via les tokens.
- Aucune URL IPTV en dur dans le code de prod.
- Pas de `console.log` — utiliser le logger (à brancher Phase 2).

---

## Rappels juridiques (cf. `AGENTS.md` du repo racine)

- Le produit est un **lecteur uniquement**. Il ne fournit / ne diffuse
  AUCUN contenu. L'utilisateur apporte ses URLs M3U ou ses identifiants
  Xtream Codes.
- Code 100 % original, pas de copie d'app existante.
- Politique de confidentialité requise dès qu'on soumet aux stores
  Samsung / LG / Google Play.
