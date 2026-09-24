# TV King 👑

> **But ultime : devenir l'application IPTV mobile n°1 au monde.**

Application de streaming **mobile-first et télévision** (« 10-foot UI »), centrée
sur quatre univers : **TV en direct (IPTV)** — vos chaînes, vos playlists M3U —
**Films** (téléchargés sur l'appareil, lecture instantanée), **Sport** (direct,
scores, replays) et **Formation** (parcours par niveau, progression, intervenants).

## Les trois engagements TV King

1. **Conditions acceptées avant tout** — au premier lancement, l'application ne
   s'utilise qu'après acceptation des conditions : TV King ne fournit aucun
   contenu ; les liens et playlists appartiennent à l'utilisateur, qui en est
   responsable.
2. **Chaque lien est vérifié avant lecture** — un lien invalide est signalé avec
   sa raison et n'est jamais envoyé au lecteur : aucune attente sans fin.
3. **Zéro roue qui tourne** — les films se téléchargent d'eux-mêmes (progression
   déterminée, en %) et se lisent depuis l'appareil : démarrage immédiat, aucune
   mise en mémoire tampon, aucun spinner nulle part dans l'application.
4. **La lecture vous suit** — bouton « Réduire » façon YouTube : la vidéo continue
   dans une petite fenêtre flottante pendant que vous naviguez, avec tous les
   contrôles dedans (écouteurs = audio seulement, lecture/pause, suivant,
   agrandir, fermer).

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
  layout.tsx                  Shell : CGU + sidebar (TV) + tabs (mobile) + D-pad
  page.tsx                    Accueil (hero + rangées)
  tv/                         TV en direct (IPTV) : playlist M3U, liens vérifiés
  films/                      Films (téléchargés → lecture instantanée)
  sport/  formation/          Catégories (live/replay ; niveaux/progression)
  title/[slug]/               Page détail d'un contenu
  watch/[slug]/               Lecteur + « À suivre »
  search/  list/  reglages/   Recherche, Ma liste, Réglages
  components/                 ConsentGate, Sidebar, MobileNav, Player, MiniPlayer,
                              FilmActions…
  lib/data.ts                 Modèle de contenu (mock) + lookups
  lib/mini.ts                 État global du mini-lecteur flottant
  lib/m3u.ts  lib/playlist.ts Parseur M3U + playlist persistée (IPTV)
  lib/consent.ts              Acceptation des CGU, versionnée
  lib/downloads.ts            Films téléchargés (lecture instantanée)
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

---

## Application Android (Flutter) — dossier `android-app/`

Le dépôt héberge aussi l'application mobile / Android TV **7 MOTION** (projet
Flutter, codename `tv_king`) dans le dossier [`android-app/`](android-app/).
Elle est indépendante du site Next.js ci-dessus : chaque projet a ses propres
dépendances, son propre `.gitignore` et sa propre documentation.

```bash
cd android-app
flutter pub get
flutter build apk --debug     # APK de test
```

- Documentation de l'app : [`android-app/README.md`](android-app/README.md)
- Conventions de code de l'app : [`android-app/AGENTS.md`](android-app/AGENTS.md)
- Package / applicationId actuel : `com.example.tv_king` (voir
  `android-app/android/app/build.gradle.kts`).
- Les workflows CI historiques de l'app sont conservés dans
  `android-app/.github/workflows/` mais ne sont **pas** exécutés par GitHub
  (seul `.github/` à la racine l'est). À adapter avec `working-directory: android-app`
  si on veut les réactiver.
- Aucun keystore ni secret n'est versionné : la signature release se fait
  via les secrets GitHub Actions (`ANDROID_KEYSTORE_BASE64`, etc.).
