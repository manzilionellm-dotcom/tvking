# 7 MOTION — Où est quoi

Document d'orientation pour un ingénieur qui découvre le projet.
Tout ce qui suit a été relevé DANS LE DÉPÔT le 03/09/2026 (commit
`86119c9`), pas de mémoire. Quand une valeur bouge, le fichier qui fait
foi est nommé à côté.

Le contenu de ce fichier est aussi disponible sous forme de **prompt à
coller** à la fin — c'est le même texte, mis en forme pour être donné
à un assistant qui prend le projet en main.

---

## 1. LA CONFUSION À LEVER D'ABORD

**Il n'y a qu'UN SEUL dépôt : `manzilionellm-dotcom/tvking`.**

C'est un *monorepo*. L'application, le back-end, le panneau
d'administration et le site public y vivent ensemble. Il n'existe **pas**
de dépôt `tvking-admin`, `m3u`, `saas` ni `serveur` — chercher un dépôt
séparé pour le panneau est une impasse, et c'est l'erreur que fait tout
le monde en arrivant.

Rien n'est hébergé sur Vercel. Tout est chez **Cloudflare**.

---

## 2. LES QUATRE CHOSES QUI TOURNENT

| Ce que c'est | Dossier | Où c'est en ligne | Déployé par |
|---|---|---|---|
| L'application (mobile + TV) | `lib/` | APK / Play Store | `build-*.yml` |
| Le back-end + le site public | `cloudflare/` | `app.7themotion.com` | `deploy-worker.yml` |
| Le panneau d'administration | `admin-panel/` | `tvking-admin.pages.dev` | `deploy-admin-panel.yml` |
| Le lecteur vidéo TV natif | `packages/native_video_player/` | (compilé dans l'app TV) | — |

### 2.1 L'application — Flutter, cinq points d'entrée

Un seul code, cinq exécutables. Le point d'entrée décide de tout le
reste (moteur vidéo, interface, capacités).

| Fichier | Cible | Moteur vidéo | Identifiant |
|---|---|---|---|
| `lib/main.dart` | Téléphone / tablette Android | media_kit (libmpv) | `com.manzilionellm.tvking` |
| `lib/main_tv.dart` | Android TV, Fire TV, Google TV | plugin natif Media3 | `com.sevenmotion.tv` |
| `lib/main_tizen.dart` | Samsung (Tizen) | AVPlay | — |
| `lib/main_windows.dart` | PC | media_kit | — |
| `lib/main_prive.dart` | variante « Privé » | media_kit | `com.manzilionellm.prive` |

**Le piège :** `main.dart` et `main_tv.dart` ne partagent PAS leur
lecteur. Un correctif posé sur l'un ne s'applique pas à l'autre. C'est
la première cause de « ça marche sur le téléphone mais pas sur la box ».

Organisation interne (`AGENTS.md` fait foi) :

```
lib/
├── core/        transverse : thème, lecture, profils, temps réel, mise à jour
├── features/    une fonctionnalité = un dossier
│   └── <feature>/
│       ├── domain/         modèles purs (aucun import Flutter)
│       ├── data/           sources : parseur M3U, client Xtream, SQLite
│       └── presentation/   écrans et widgets
└── shared/      le peu qui est partagé entre features
```

### 2.2 Le back-end — un Worker Cloudflare

- **Nom du worker** : `seven-motion-backend` (`cloudflare/wrangler.toml`)
- **Domaine** : `app.7themotion.com` (custom domain, pas `workers.dev`)
- **Base** : D1, `tvking_licensing`
- **Temps réel** : Durable Object `RealtimeHub` (`cloudflare/realtime.js`)

Deux gros fichiers, et la distinction compte :

| Fichier | Rôle | Authentification |
|---|---|---|
| `cloudflare/worker.js` (~7 800 l.) | routage général, routes **publiques** appelées par les box, site public, proxy cast, téléchargements | aucune (adresse MK) |
| `cloudflare/api_v1.js` (~6 500 l.) | tout `/api/v1/*` — ce que le **panneau** appelle | jeton JWT (Bearer) |

Le site public (`app.7themotion.com`) est servi par
`cloudflare/landing.js`, appelé à la racine par `worker.js`.

### 2.3 Le panneau d'administration

- **Dossier** : `admin-panel/` — React 18 + Vite + Tailwind
- **En ligne** : `https://tvking-admin.pages.dev` (Cloudflare **Pages**)
- **Projet Pages** : `tvking-admin`
- **Il parle à** : `https://app.7themotion.com/api/v1/*`
  (injecté au build via `VITE_API_BASE`)

Une trentaine de pages dans `admin-panel/src/pages/`. Les points
d'entrée : `App.tsx` (routes), `components/Sidebar.tsx` (menu et droits
par rôle), `lib/api.ts` (tous les appels, typés), `lib/i18n.tsx`
(fr / en / ar).

**Deux rôles**, et le menu s'adapte : propriétaire (`super_admin`,
`admin`) et revendeur (`reseller`, avec des capacités cochées une par
une — `activate`, `sources`, `transfer`, `devices`…).

> ⚠ Un ancien panneau HTML vivait DANS `worker.js` sur `/admin/panel`.
> Il a été **supprimé le 31/08/2026** ; l'adresse redirige en 301 vers
> le panneau React. Si un document le mentionne, il est périmé.

---

## 3. LA CONTRAINTE QUI EXPLIQUE LA MOITIÉ DU CODE

**La plupart des clients ont un abonnement fournisseur limité à UNE
connexion simultanée.**

Chaque seconde où deux sockets vers le fournisseur se chevauchent, le
client voit « connexion déjà utilisée » et ne regarde plus rien. C'est
le pire symptôme du produit, et c'est pour l'éviter qu'existent :

- `lib/core/playback/stream_slot.dart` — le **créneau** : un seul
  consommateur à la fois. `claim` / `register` / `handOff`, avec des
  groupes (`solo`, `multiview`, `downloads`) et un budget de démontage.
- `lib/features/player/data/local_stream_relay.dart` — le **relais
  local** : la lecture en direct passe par `127.0.0.1`, ce qui permet à
  UNE connexion amont d'alimenter plusieurs lecteurs de la **même**
  chaîne sur le **même** appareil.
- `packages/native_video_player/` — `closeOtherPlaybacks`,
  `awaitNetworkIdle` : la preuve que la socket est vraiment fermée, pas
  seulement que l'objet est détruit.

**Lis ces trois fichiers avant de toucher au lecteur.** Un correctif
posé sans les avoir lus rouvre le défaut ailleurs.

**Ce que les profils ne font PAS :** ils isolent les données (historique,
PIN, catégories), pas les connexions. Sur une ligne à une connexion,
deux profils ne peuvent pas regarder deux chaînes différentes.

**Le magnétoscope vit sous la même contrainte** (05/09/2026,
`docs/recording-architecture.md` §13) :

- `lib/features/recordings/data/recording_scheduler.dart` — les
  **enregistrements programmés** depuis le guide. Le créneau est capté
  par le natif du plugin `packages/tvking_device/` (alarme exacte +
  service au premier plan, sans Flutter, survit à la veille et au
  redémarrage) ; le Dart réconcilie au boot et toutes les 30 s. Deux
  créneaux qui se chevauchent sur deux chaînes sont **refusés** : une
  connexion. Si le client regarde une autre chaîne pendant la capture,
  l'app prévient, elle ne peut pas empêcher le fournisseur de couper.
- `LocalStreamRelay.startTimeshift` — le **différé** : la pause du direct
  tamponne le flux sur disque **sur la même connexion** (tee) ; la
  reprise rejoue le tampon (`/shift`), « Retour au direct » le jette.
  Lecteur TV seulement ; plafonds 1,5 Go / 90 min.
- `RecordingStoragePolicy` — la limite d'espace choisie par le client et
  la purge des plus anciens (jamais un enregistrement en cours).

---

## 4. LA CHAÎNE DE LIVRAISON

26 workflows dans `.github/workflows/`. Les six qui comptent :

| Workflow | Ce qu'il fait | Cible |
|---|---|---|
| `deploy-worker.yml` | `wrangler deploy` | `app.7themotion.com` |
| `deploy-admin-panel.yml` | `npm run build` + `pages deploy` | `tvking-admin.pages.dev` |
| `build-seventv.yml` | APK Android TV | release `seventv-latest` |
| `build-android.yml` | APK téléphone | artifact |
| `build-windows.yml` | installeur `.exe` | release `windows-latest` |
| `build-tizen.yml` / `build-webos.yml` | Samsung / LG | `tizen-latest` / `webos-latest` |

Les canaux de release GitHub (ce que servent les liens publics) :
`seventv-latest`, `windows-latest`, `tizen-latest`, `webos-latest`,
`play-aab`, `test`.

### Les liens que le client reçoit

| Adresse | Sert |
|---|---|
| `app.7themotion.com` | le site public |
| `app.7themotion.com/tv` | APK TV / Fire TV |
| `app.7themotion.com/install` | redirige vers Google Play |
| `app.7themotion.com/win` | installeur Windows |
| `app.7themotion.com/samsung` · `/lg` | Tizen · webOS |
| `app.7themotion.com/mon-espace` | le client gère ses playlists |

`ci/distribution_lock.sh` **verrouille** ces valeurs : les changer fait
échouer la publication tant que le verrou n'a pas été rescellé avec la
phrase secrète du propriétaire. C'est délibéré — un lien de mise à jour
cassé coupe tout le parc.

### Secrets attendus par la CI

`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` (16 workflows),
`ANDROID_KEYSTORE_BASE64` + `ANDROID_KEYSTORE_PASSWORD`,
`GOOGLE_SERVICES_JSON`, `SAMSUNG_AUTHOR_P12_BASE64`, la famille
`APPLE_*` / `ASC_*` (iOS, pas encore publié), `DIST_LOCK_PASSPHRASE`.

Côté Worker, posés par `wrangler secret put` : **`ADMIN_SECRET`** et
**`JWT_SECRET`**.
⚠ **Sans l'un des deux, l'API répond 503** — c'est voulu depuis le
03/09 : elle signait auparavant avec une constante publique.

---

## 5. LES TESTS, ET CE QU'ILS PROUVENT

| Commande | Ce que ça couvre |
|---|---|
| `flutter test` | 906 tests Dart |
| `flutter analyze` | doit être propre |
| `node cloudflare/<nom>.smoke.mjs` | 18 suites, sur le **vrai** worker avec une base D1 simulée |
| `cd admin-panel && npm run build` | le panneau compile |

Les suites smoke à connaître :

- `security_wave1.smoke.mjs` — **rejoue de vraies attaques** (vol
  d'abonnement, essai de cent ans, jeton forgé, SSRF). C'est le premier
  fichier à lire pour comprendre le modèle de menace.
- `device_profiles.smoke.mjs` — les profils, côté panneau ET côté app.
- `lab_sources.smoke.mjs` — l'étanchéité du labo du maître.
- `sports_big.smoke.mjs` — le classement des ligues sur données réelles.

**La règle de la maison** : un correctif se prouve par un test qui
échoue AVANT et passe APRÈS. Pas « ça devrait marcher ».

---

## 6. CE QUI EST FAIT, CE QUI RESTE

Un audit externe a produit un plan en sept vagues.

**Vague 1 — sécurité : FAITE** (03/09/2026, commits `48bb270`→`86119c9`)
- transfert / prêt / reclaim / auto-détachement famille → **410** : ils
  ne demandaient qu'une adresse MK, qui n'est pas un secret ;
- essais bornés par liste fermée (`trial_876000h` valait cent ans
  gratuits) ; revendeurs cloisonnés sur leurs propres licences ;
- plus de repli `dev-secret` ; l'identité est **relue en base** à chaque
  requête (un revendeur suspendu perdait ses droits… sept jours plus
  tard) ;
- quatre workflows qui publiaient le mot de passe admin : supprimés ;
- écriture publique de `latest_build_ts` retirée ; anti-SSRF sur `/cs/`.

**Vagues 2 à 7 — à faire**, dans l'ordre :
2. la ligne unique (8 fuites du créneau identifiées) — 2 j
3. le jeton d'appareil (`/api/device-source/:mac` livre encore les
   identifiants du fournisseur à qui connaît l'adresse) — 2 j
4. le contrôle parental réellement incontournable — 1 j
5. la livraison (clé de secours, branches, atomicité) — 1 j
6. le socle (une seule session de lecture, un seul boot) — 3 sem.
7. le futur (auto frame-rate, HDR, accessibilité) — le timeshift et
   l'enregistrement programmé sont FAITS (05/09/2026, voir §3)

`docs/SECURITE_A_FAIRE_PROPRIETAIRE.md` liste ce qui reste au
propriétaire : passer le dépôt en privé, tourner les secrets.

---

# LE PROMPT À COLLER

Ce qui suit est à donner tel quel à un ingénieur ou à un assistant qui
prend le projet en main.

```
Tu prends en main 7 MOTION, un lecteur IPTV multi-plateforme en
production avec de vrais clients payants. Voici la carte du terrain.
Tout a été vérifié dans le dépôt le 03/09/2026.

UN SEUL DÉPÔT : manzilionellm-dotcom/tvking. C'est un monorepo.
L'application, le back-end, le panneau d'administration et le site
public y vivent ensemble. Il n'existe PAS de dépôt tvking-admin, m3u,
saas ni serveur — chercher un dépôt séparé pour le panneau est une
impasse. Rien n'est sur Vercel : tout est chez Cloudflare.

QUATRE CHOSES TOURNENT
1. L'application — lib/ — Flutter, CINQ points d'entrée :
   • lib/main.dart        téléphone Android   (media_kit/libmpv)
   • lib/main_tv.dart     Android TV, Fire TV (plugin natif Media3)
   • lib/main_tizen.dart  Samsung             (AVPlay)
   • lib/main_windows.dart PC                 (media_kit)
   • lib/main_prive.dart  variante « Privé »
   PIÈGE : le téléphone et la TV ne partagent PAS leur lecteur. Un
   correctif posé sur l'un ne s'applique pas à l'autre. C'est la
   première cause de « ça marche sur le téléphone, pas sur la box ».

2. Le back-end — cloudflare/ — un Worker nommé seven-motion-backend,
   sur app.7themotion.com, base D1 « tvking_licensing », temps réel par
   Durable Object RealtimeHub.
   • worker.js  (~7 800 l.) : routes PUBLIQUES appelées par les box,
     site public, proxy cast, téléchargements. Pas de jeton.
   • api_v1.js  (~6 500 l.) : tout /api/v1/*, ce que le PANNEAU appelle.
     Jeton JWT Bearer.
   • landing.js : le site public servi à la racine.

3. Le panneau d'administration — admin-panel/ — React 18 + Vite +
   Tailwind, déployé sur Cloudflare PAGES, projet « tvking-admin »,
   en ligne sur https://tvking-admin.pages.dev. Il appelle
   app.7themotion.com/api/v1/* (VITE_API_BASE, injecté au build).
   Entrées : App.tsx (routes), components/Sidebar.tsx (menu + droits),
   lib/api.ts (appels typés), lib/i18n.tsx (fr/en/ar).
   Deux rôles : propriétaire (super_admin, admin) et revendeur, ce
   dernier avec des capacités cochées une par une.
   ⚠ Un ANCIEN panneau HTML vivait dans worker.js sur /admin/panel. Il
   a été supprimé le 31/08/2026 ; l'adresse redirige en 301. Tout
   document qui le mentionne est périmé.

4. Le lecteur vidéo TV — packages/native_video_player/ — plugin Kotlin
   local, Media3/ExoPlayer 1.8.0.

LA CONTRAINTE QUI EXPLIQUE LA MOITIÉ DU CODE
La plupart des clients ont un abonnement fournisseur limité à UNE
connexion simultanée. Chaque seconde où deux sockets se chevauchent, le
client voit « connexion déjà utilisée » et ne regarde plus rien. C'est
pour l'éviter qu'existent :
  • lib/core/playback/stream_slot.dart          le créneau unique
  • lib/features/player/data/local_stream_relay.dart  le relais 127.0.0.1
  • packages/native_video_player/ (closeOtherPlaybacks, awaitNetworkIdle)
LIS CES TROIS FICHIERS avant de toucher au lecteur. Un correctif posé
sans les avoir lus rouvre le défaut ailleurs.
Les profils isolent les DONNÉES, pas les connexions : sur une ligne à
une connexion, deux profils ne regardent pas deux chaînes différentes.

LIVRAISON — 26 workflows. Les six qui comptent :
  deploy-worker.yml        → app.7themotion.com
  deploy-admin-panel.yml   → tvking-admin.pages.dev
  build-seventv.yml        → APK TV (release seventv-latest)
  build-android.yml        → APK téléphone
  build-windows.yml        → installeur (windows-latest)
  build-tizen / build-webos → Samsung / LG
Liens clients : /tv (APK TV), /install (Google Play), /win, /samsung,
/lg, /mon-espace. ci/distribution_lock.sh les VERROUILLE : les changer
fait échouer la publication tant que le verrou n'est pas rescellé avec
la phrase du propriétaire. C'est délibéré — un lien cassé coupe le parc.
Secrets Worker : ADMIN_SECRET et JWT_SECRET, posés par
`wrangler secret put`. Sans l'un des deux, l'API répond 503 : c'est
voulu depuis le 03/09 (elle signait avant avec une constante publique).

TESTS
  flutter test                        863 tests
  flutter analyze                     doit être propre
  node cloudflare/<nom>.smoke.mjs     18 suites, vrai worker + D1 simulée
  cd admin-panel && npm run build     le panneau compile
Commence par lire cloudflare/security_wave1.smoke.mjs : il rejoue de
vraies attaques et c'est le meilleur résumé du modèle de menace.

ÉTAT
La Vague 1 d'un audit externe (sécurité) est FAITE le 03/09/2026 :
routes de transfert fermées, essais bornés, revendeurs cloisonnés,
secret obligatoire, identité relue en base à chaque requête, workflows
fuiteurs supprimés, anti-SSRF. Restent les vagues 2 à 7, dans l'ordre :
la ligne unique, le jeton d'appareil, le contrôle parental, la
livraison, le socle, le futur.

RÈGLES DE TRAVAIL
1. Tu lis la fonction ET ses appelants avant d'écrire.
2. Un correctif = un commit + le test qui le prouve. Le test doit
   ÉCHOUER avant et PASSER après. Jamais « ça devrait marcher ».
3. Tu ne désactives jamais un test pour passer au vert.
4. Tu ne touches pas à ce qui marche : StreamSlot, le relais, le
   lecteur natif, le parseur EPG en isolate, les huit langues.
5. Aucun secret dans le dépôt. Si tu en vois un, tu le retires et tu le
   dis.
6. Tu ne publies jamais : pas de wrangler deploy, pas de release. Tu
   prépares, tu prouves, le propriétaire appuie sur le bouton.
7. Si tu n'as pas pu vérifier, tu écris « supposition non vérifiée ».
   Si un indicateur te surprend, tu vérifies l'indicateur d'abord.
8. Commentaires en FRANÇAIS, abondants, qui expliquent le POURQUOI. Le
   projet sert aussi de support d'apprentissage à son propriétaire.
   Pas de print() : debugPrint(). Couleurs et tailles uniquement via
   AppColors / AppTextStyles.
```
