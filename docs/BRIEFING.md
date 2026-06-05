# Briefing — état du projet & mission Cast

> Document de passation. À jour au 2026-06-05.

---

## 0. Où tout se trouve (espace de travail)

| Élément | Emplacement |
|---|---|
| **Dépôt** | `manzilionellm-dotcom/tvking` |
| **Branche de travail** | `claude/github-commit-access-YDUAv` (= **PR #4** vers `main`) |
| **App mobile** | Flutter — dossier `lib/` (Dart) + `android_overlay/google_cast/` (Kotlin natif, injecté au build par `android_overlay/google_cast/apply_cast_patch.sh`) |
| **Backend** | Cloudflare Worker — `cloudflare/worker.js` + `cloudflare/api_v1.js` (base **D1** `tvking_licensing`) |
| **Panneau revendeur** | `admin-panel/` (React) → déployé sur **`https://tvking-admin.pages.dev`** |
| **APK (toujours à jour)** | `https://github.com/manzilionellm-dotcom/tvking/releases/download/latest/7motion.apk` |

**Workflows CI (déclenchés au push sur `claude/**`) :**
- `build-android.yml` → build l'APK + publie la release `latest`.
- `deploy-worker.yml` → déploie le Worker (worker `seven-motion-backend`, URL `https://seven-motion-backend.manzilionel-lm.workers.dev`).
- `deploy-admin-panel.yml` → déploie le panel sur `tvking-admin.pages.dev`.

**Point d'architecture important :** l'app ET le panel pointent désormais sur le **même** backend `seven-motion-backend.manzilionel-lm.workers.dev` (l'ancien `99999.7themotion.com` n'est plus utilisé). KV désactivé → **tout passe par D1**.

---

## 1. Ce qui a été fait (par thème)

### Abonnement / activation revendeur (chaîne complète réparée ✅)
- `524fc6c` — l'activation admin écrit en **D1** (la source que l'app lit), plus en KV → l'activation à distance refonctionne.
- `520ff08` — l'app pointe sur le **même worker** que le panel (corrige « l'app ne voit pas mon panel »).
- `d0b3e86` — `/api/device-source/:mac` lit aussi le KV en repli.
- `28581ea` — **décodage de la MAC** dans `/api/v1/sources/:mac` (corrige « mac must be MK:… »).
- `5ff843f` — clé maître `ADMIN_SECRET` pour le super_admin (anti lock-out).
- `eb0ba4b` — **MAC stable** entre réinstallations (dérivée d'ANDROID_ID) — sinon le client perdait son abo en réinstallant.
- `1df1b6f` / `66566cc` / `92c6ef8` — bouton + sondage auto « Vérifier mon abonnement » (chargement instantané).
- `524fc6c` / `1fffe32` — affichage **à vie / 1 an** + écran d'accueil adaptatif (premium vs essai).
- `e40bf69` / `a29a8a7` — messages de diagnostic précis (aucune source / source reçue mais 0 chaîne / appareil inconnu).

### Panel revendeur (admin-panel)
- `ae85a01` — page **« Pousser une playlist »** (assigner une source sans le piège « Aucune »).
- `637edd1` — **éditer une app** (changer le lien de téléchargement client).
- `406a625` — login Admin/Revendeur clairement distingués.
- `44ae66f` — bouton **Déconnexion** visible dans l'en-tête de toutes les pages.

### App — divers
- `8dd0094` / `1e2e60d` — **i18n** : toute l'UI traduite en 8 langues (le changement de langue ne faisait rien avant).
- `e8b2587` — thème verrouillé **Cinema** (sombre) — le mode clair cassait l'affichage.
- `740618e` — mention **VPN** retirée.
- `e8ea1ff` / `70e6a56` — export galerie : **remux TS→MP4 réel** (corrige « format non supporté »).
- `779b1ab` — watermark **THE FEWS** sur les enregistrements.
- `bdc4b60` — bascule entre plusieurs playlists.
- `aad998a` — verrouillage biométrique obligatoire au démarrage.
- `f7ae330` — fetcher M3U plus robuste.
- `251f682` — accueil : emojis géants animés + cartes compactes.

---

## 2. ⚠️ MISSION DE L'INGÉNIEUR : le CAST

**Objectif UNIQUE : faire que l'application CAST (diffusion vers une TV / Chromecast / Google TV) fonctionne.**

**Règle stricte : ne toucher QUE le code du Cast.** Ne pas modifier l'abonnement, l'activation, l'i18n, le panel, l'enregistrement, etc. — tout ça fonctionne et a demandé beaucoup de travail. Le périmètre se limite aux fichiers Cast ci-dessous.

### Fichiers concernés (et UNIQUEMENT ceux-là)
**Natif (Kotlin)** — `android_overlay/google_cast/` :
- `GoogleCastApi.kt` — pont natif vers le Google Cast SDK (sessions, loadMedia, play/pause…).
- `CastOptionsProviderImpl.kt` — config du SDK (App ID du receiver).
- `MulticastLockBridge.kt` — lock multicast pour la découverte (mDNS/SSDP).
- `MainActivity.kt` — câblage des MethodChannels.

**Dart** — `lib/features/cast/` :
- `cast_manager.dart`, `google_cast_api.dart`, `google_cast_transport.dart`, `cast_transport.dart`
- `local_cast_server.dart`, `dlna_*.dart`, `roku_ecp_transport.dart`, `upnp_av_transport.dart`
- `presentation/cast_button.dart`, `cast_picker_sheet.dart`, `cast_diagnostics_screen.dart`

### État actuel du Cast
- Le receiver Google Cast a été basculé du receiver brandé **non publié** `46F815A5` vers le **Default Media Receiver public `CC1AD845`** (commit `08c6d61`), pour qu'il marche sur n'importe quelle TV sans publication. → vérifier que c'est toujours le bon choix.

### Pistes connues à investiguer (par ordre de probabilité)
1. **Google Play Services (GMS)** : le Cast SDK l'exige. Sur les téléphones sans GMS (Huawei récents, ROMs AOSP), `isCastAvailable()` renvoie `false` → pas de cast possible. Vérifier sur un appareil **avec** GMS.
2. **Découverte réseau** : le téléphone et la TV doivent être sur le **même réseau Wi-Fi**, sans **isolation des points d'accès** (AP isolation) sur la box. Le `MulticastLockBridge` doit être actif pendant la découverte (permission `CHANGE_WIFI_MULTICAST_STATE`).
3. **Format du flux** : le Default Media Receiver lit HLS/MP4 ; un flux IPTV **MPEG-TS brut** peut ne pas être lu par la TV. Tester avec un flux HLS (`.m3u8`).
4. **Receiver** : si on veut le branding, il faudra **publier** `46F815A5` dans la Google Cast SDK Developer Console, puis remettre cet App ID dans `CastOptionsProviderImpl.kt`.
5. Utiliser l'écran **`cast_diagnostics_screen.dart`** (déjà présent dans l'app) pour voir l'état réel de la découverte/session.

### Comment tester / déployer
- Modifier les fichiers Cast → push sur `claude/github-commit-access-YDUAv` → le workflow `build-android.yml` produit l'APK sur la release `latest`.
- Tester sur un **téléphone avec GMS** + une **Chromecast/Google TV sur le même Wi-Fi**.

---

## 3. En résumé pour l'ingénieur

> Toute l'app fonctionne (abonnement, activation, playlists, i18n, enregistrement, panel). **La seule chose à faire : le CAST.** Tu ne touches QUE les fichiers Cast listés en §2. Mission : **l'application doit pouvoir caster sur une TV.**
