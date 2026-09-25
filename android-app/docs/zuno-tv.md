# Zuno (app box) ↔ panel admin — comment l'app est reliée au panel

> Marque : **Zuno** (logo calligraphie or sur noir, `assets/branding/zuno_*`).
> L'ancienne release `7motion-tv-panel` (même app, ancienne marque) n'est plus
> alimentée. Lien client :
> `https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-tv/zuno-tv.apk`
>
> La release `7motion-tv` reste celle de l'APK 4K Player rebrandé : ce
> workflow n'y écrit jamais. Les deux apps ont des packages différents et
> cohabitent sur la même box.

## 1. Ce qui est publié sous ce lien

Le workflow racine `.github/workflows/build-zuno-tv.yml` compile l'app
Flutter **`android-app/lib/main_tv.dart`** (interface 10-foot, D-pad) et
dépose l'APK sur la release `zuno-tv`.

Le 4K Player rebrandé (release `7motion-tv`) est un binaire tiers fermé : il
s'active sur le serveur de son fournisseur, pas sur notre panel. C'est pour
ça que l'app reliée au panel est cette app Flutter, publiée à part.

## 2. La connexion au panel, concrètement

L'app TV et le panel parlent au **même Worker Cloudflare**
(`https://app.7themotion.com`, code dans `android-app/cloudflare/`). Rien à
configurer côté box : tout est automatique au premier démarrage.

| Étape | Côté app (`main_tv.dart`) | Côté panel / Worker |
|---|---|---|
| Identité | `DeviceIdentity` dérive une MAC stable `MK:XX:XX:XX:XX:XX` de l'ANDROID_ID | La MAC est la clé de la fiche appareil (table `devices`) |
| Présence | `POST /api/heartbeat` au boot, `platform=tv` | Page **Appareils** : la box apparaît avec 📺, modèle, version, chaîne en cours |
| Licence | `GET /api/status/:mac` + heartbeat → `paid / trial / frozen / banned` | Page **Activer** : `POST /api/v1/activate {mac, plan}` |
| Sources | `RemoteSourceRepository.sync()` lit `GET /api/device-source/:mac` et importe les playlists M3U / Xtream | Page **Appareils → Sources** : `PUT /api/v1/sources/:mac` |
| Thème | `GET /api/theme?platform=tv` | Page **Thème** |
| Annonces | `GET /api/announcement` | Page **Notifications** |
| Mise à jour forcée | `GET /api/app-version?build=<APP_BUILD_TS>&platform=tv` | Page **Forcer la MAJ** |
| Historique multi-box | heartbeat `recent[]` / `GET /api/history/:mac` | restauré sur une 2ᵉ box |

Écran d'activation : tant que la box n'est ni activée ni en essai, l'app
affiche sa MAC (= code d'activation) et interroge le serveur toutes les 5 s
(`tv_activation_screen.dart`). Dès que l'admin active la MAC dans le panel,
l'écran bascule seul sur l'accueil.

## 3. Publier une nouvelle version

- **Automatique** : tout push sur `main` qui touche `android-app/` recompile
  et **publie** sur `zuno-tv` (versionCode = secondes epoch, donc toujours
  croissant → la mise à jour s'installe par-dessus).
- **Manuel** : Actions → « Build Zuno TV » → *Run workflow* →
  `publish = true`. Avec `publish = false` (défaut), le run compile, vérifie
  et laisse l'APK en artefact sans toucher au lien clients.
- **Autre backend** (staging, second panel) : input `backend_url` →
  `--dart-define=BACKEND_URL=…` (constante `kSubscriptionBaseUrl`).

Le workflow vérifie **sur l'APK produit** : applicationId
`com.sevenmotion.tv.seven_tv` (identité historique conservée : même
package que les box déjà équipées, la mise à jour s'installe par-dessus), catégorie `LEANBACK_LAUNCHER`, et la
présence de l'URL du Worker dans le code compilé. Un APK qui ne pointe pas
sur le panel n'est pas publié.

## 4. Signature (à faire une fois, recommandé)

Poser les secrets GitHub (Settings → Secrets and variables → Actions) :

| Secret | Contenu |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | le keystore du propriétaire (`base64 -w0 release.jks`) |
| `ANDROID_KEYSTORE_PASSWORD` | mot de passe du keystore |
| `ANDROID_KEY_ALIAS` | alias de la clé (défaut si absent : `sevenmotion`) |
| `ANDROID_KEY_PASSWORD` | mot de passe de la clé (défaut : celui du keystore) |

Sans ces secrets, le workflow signe avec le keystore **fixe** historique du
projet (stable entre builds, donc mises à jour possibles), mais ce n'est pas
la clé maîtresse : une box qui a une version signée avec la clé maîtresse
devra désinstaller une fois. Il refuse en revanche de signer avec la clé
jetable du runner.

## 5. Worker : route `/tv`

`android-app/cloudflare/worker.js` (`TV_APK_URL`) proxifie
`https://app.7themotion.com/tv` vers l'APK de la release `7motion-tv`
(fichier `7MotionTV.apk`). Après modification, redéployer le Worker :

```bash
cd android-app/cloudflare
npx wrangler deploy
```

(ou réactiver `android-app/.github/workflows/deploy-worker.yml` à la racine
avec `working-directory: android-app/cloudflare`).
