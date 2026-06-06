# NOVA+ — Live TV

Lecteur **IPTV pensé pour la télévision** (expérience « 10-foot UI », télécommande
D-pad), reconstruisant l'expérience de référence **TiViMate** avec une identité
propre. NOVA+ lit une source **M3U / Xtream Codes** et un guide **XMLTV (EPG)**.

> ⚠️ Propriété intellectuelle : NOVA+ reproduit les **fonctionnalités et la qualité
> d'expérience** de l'app de référence, **pas** ses logos, marques ou assets.

Le design applique des normes officielles et des bonnes pratiques documentées :
- [`docs/RESEARCH-IPTV-NOVA.md`](docs/RESEARCH-IPTV-NOVA.md) — référentiel IPTV (UX live/EPG, palette, engagement)
- [`docs/RESEARCH-TV-UX.md`](docs/RESEARCH-TV-UX.md) — normes plateformes TV, scaling, safe-areas
- [`docs/NOVA-RECONSTRUCTION-TIVIMATE.md`](docs/NOVA-RECONSTRUCTION-TIVIMATE.md) — plan de reconstruction écran par écran

## Fonctionnalités (V1 — cœur live)

- **Chaînes & catégories** — rail des groupes (issus de la playlist) + grille de chaînes,
  avec **Favoris** et **Récemment vues** (virtuels, par appareil).
- **Lecteur plein écran** — HLS via `hls.js` (WebView/Chromium n'ont pas de HLS natif),
  barre d'info **now/next**, **zapping** Haut/Bas, **liste de chaînes** en surimpression.
- **Guide TV (EPG)** — grille temps × chaînes, programme en cours mis en évidence.
- **Recherche** de chaînes, **Favoris**, **Réglages** (source + affichage).

### Télécommande (D-pad) dans le lecteur
`▲▼` chaîne ± · `◀▶` / `L` liste des chaînes · `OK`/`Espace` infos · `F` favori · `Retour`/`Échap` quitter.

## Principes appliqués

- **Adaptation à toute TV** — canvas 1920×1080 (16:9), police racine fonction de `100vw` :
  tout (en `rem`) scale du 720p au 4K sans zoom. Safe-area ~5 % par bord.
- **Couleurs reposantes** — fond `#101418` (jamais de noir pur, légère teinte bleue),
  texte off-white via opacité (jamais de blanc pur), accents **désaturés**, rouge réservé
  au badge LIVE. Contraste WCAG AA.
- **Navigation D-pad** — focus vers l'élément le plus proche (`SpatialNav`), état net
  (anneau + agrandissement + élévation).
- **Réglages** — taille du texte et overscan ajustables (persistés).

## Configurer la source

Dans **Réglages** : URL **M3U** + URL **XMLTV** (optionnelle), ou identifiants
**Xtream Codes** (serveur / utilisateur / mot de passe → convertis en `get.php` / `xmltv.php`).
Le choix est mémorisé par appareil (cookies). On peut aussi fixer un défaut au déploiement :

```bash
NOVA_PLAYLIST_URL=...   # URL M3U/get.php par défaut
NOVA_EPG_URL=...        # URL XMLTV par défaut (optionnel)
```

À défaut, une playlist publique (iptv-org) est utilisée pour que l'app tourne d'emblée.

## Structure

```
app/
  layout.tsx                 Shell : sidebar + D-pad + préférences
  page.tsx                   Accueil — navigateur de chaînes (groupes + grille)
  watch/[slug]/              Lecteur plein écran (HLS, now/next, zapping, overlay)
  guide/                     Guide TV (grille EPG)
  favorites/  search/        Favoris, Recherche
  settings/                  Source (M3U/Xtream + XMLTV) + affichage
  api/channels/  api/nownext/  Lookups JSON pour les écrans client
  components/                Sidebar, ChannelBrowser, ChannelCard, Player, GuideGrid…
  lib/                       m3u.ts, xmltv.ts, epg.ts, source.ts, config.ts, favorites.ts…
docs/                        Référentiels de conception sourcés
```

## Démarrer

```bash
npm install
npm run dev      # http://localhost:3000
npm run build    # build de production
npm run lint
```
