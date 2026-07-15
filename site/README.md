# Site officiel SEVEN

Site statique (HTML/CSS/JS, zéro build) — page de présentation de l'app SEVEN.
Design : police **Inter**, accent bleu, look épuré (mêmes tokens que la fiche
d'analyse). Marque = SEVEN ; textes reformulés ; aucun asset tiers copié.

## Lancer en local
Ouvre simplement `index.html` dans un navigateur (ou `python3 -m http.server`
dans ce dossier).

## Déployer (Cloudflare Pages recommandé)
1. Cloudflare → Pages → Create → Direct upload (ou connecter le repo).
2. Répertoire de sortie / build : **aucun build**, servir le dossier `site/`.
3. Domaine : brancher `7themotion.com` (ou le domaine choisi).

## À REMPLACER par de vrais assets SEVEN (placeholders actuels)
| Fichier | Rôle | Remplacer par |
|---|---|---|
| `assets/logo.svg` | logo header | logo SEVEN définitif (320×80) |
| `assets/favicon.svg` | favicon | favicon SEVEN |
| `assets/og.svg` | aperçu réseaux | image OG 1200×630 |
| `assets/screen_01..06.svg` | carrousel | **captures réelles de l'app** (1920×1080) |
| `assets/google-play.svg` | badge Play | badge **officiel** Google Play (play.google.com/intl/en_us/badges) |

## À RENSEIGNER (valeurs à confirmer)
- Lien **Download APK** (bouton) → URL réelle de l'APK.
- Code / URL Downloader (`SEVEN-TV` / `7themotion.com/apk`) → valeurs réelles.
- Liens **Terms of Use** / **Privacy Policy** (footer) → pages réelles.
- Contact WhatsApp : déjà réglé sur **+1 807 788 8909** (wa.me/18077888909).

## Structure
```
site/
  index.html   — structure (header, hero, notice, carrousel, features, download, footer)
  styles.css   — tokens + composants (Inter, accent #0288D1, boutons #1976D2)
  app.js       — features (icônes Material, Apache 2.0) + défilement carrousel
  assets/      — logo, favicon, og, captures, badge (placeholders)
```
