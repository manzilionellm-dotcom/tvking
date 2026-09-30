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
affiche sa MAC (= code d'activation). Une seule veille (`RemoteActivationWatch`)
lit `GET /api/status` toutes les 3 s tant qu'on attend, puis toutes les 4 s.
Le bouton « J'ai payé » force une lecture immédiate. Dès que l'admin active
la MAC dans le panel, l'écran bascule seul sur l'accueil.

Retirer une liste (page Sources, ou `DELETE /api/v1/sources/:mac`) pose une
empreinte côté Worker. La même veille la voit : la box enlève cette liste,
ses chaînes, les favoris et l'historique liés, et le mot de passe stocké.
Un message s'affiche par-dessus la lecture ; « Continuer » ramène à
« Ajouter ma liste » s'il ne reste plus rien. Hors ligne, l'ordre s'applique
au retour du réseau. Le détail des preuves et la procédure chronomètre sont
dans `docs/RELEASE-103.md`.

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

## 3 bis. Langues

L'app parle **16 langues** : français, anglais, espagnol, arabe (RTL),
allemand, italien, portugais, néerlandais, turc, russe, chinois simplifié,
hindi, danois, suédois, norvégien, swahili. Fichiers : `lib/l10n/app_<code>.arb`
(modèle = `app_fr.arb`, toutes les clés `tv*` sont celles de l'app box).

- **Automatique** : au démarrage, l'app prend la **langue de la TV**
  (toutes les langues préférées du système sont parcourues, correspondance
  sur le code langue : `pt-BR` → portugais, `zh-Hant` → chinois ; rien de
  connu → anglais). Voir `LocaleRepository.resolve`.
- **Manuel** : Réglages → ligne « Langue » : OK passe à la langue suivante,
  puis revient à « Automatique ». Le choix est mémorisé (survit aux mises
  à jour, même signature).
- **Ajouter une langue** : créer `app_<code>.arb` à partir de `app_fr.arb`
  (mêmes clés, mêmes `{placeholders}`), puis ajouter la `Locale` et son nom
  natif dans `LocaleRepository`. Le CI (`flutter gen-l10n`) génère le reste.

## 3 ter. Cinéma (Films + Séries)

Tuiles **Films** et **Séries** de l'accueil. Tout vient des comptes **Xtream**
du client (tous fusionnés, comme le Direct) ; une source M3U seule n'a pas de
catalogue VOD exploitable. API : `get_vod_categories`, `get_vod_streams`,
`get_vod_info`, `get_series_categories`, `get_series`, `get_series_info`.

| Fonction | Comment |
|---|---|
| Fluidité | catégories d'abord, chaque catégorie chargée à la demande et décodée en isolate ; index complet (recherche, « Récemment ajoutés », compteurs) construit en arrière-plan, borné à 40 000 titres, libéré en quittant |
| Langue | déduite du nom des catégories (`FR |`, `[DE]`, `VOSTFR`, `华语`…) — Xtream n'a pas de champ langue ; par défaut la langue de l'app si le catalogue en a ≥ 3 catégories ; choix retenu |
| Reprise | position enregistrée toutes les 10 s, reprise 5 s avant ; « Continuer à regarder » ; épisode fini → le suivant apparaît |
| Lecteur | même moteur que le Direct (ExoPlayer, décodage matériel) + avance/retour cumulés (10 s → 30 s → 60 s), audio et sous-titres (choix retenu), carte « Épisode suivant » avec compte à rebours, reconnexion à la même seconde |
| Téléchargements | refus si < 3 Go libres ; épisode téléchargé terminé → effacé et suivant téléchargé en Wi-Fi/câble (« téléchargement intelligent ») |
| Enfants / adulte | Mode Enfants = catégories enfants seulement ; catégories adultes verrouillées par le code parental |

Code : `lib/features/cinema/` (données, testées dans `test/features/cinema/`)
et `lib/features/tv/presentation/tv_cinema_*.dart`, `tv_vod_player_screen.dart`.

## 3 quater. Sources, redémarrage, mises à jour automatiques (v93)

- **Mes sources** : chaque ligne affiche l'identifiant (username) et le
  serveur (hôte:port) de la source. Le mot de passe n'est jamais affiché.
- **Plusieurs sources actives en même temps**, sans limite côté app. Leurs
  chaînes sont fusionnées dans Direct, leurs films et séries dans Cinéma.
  « Désactiver » retire une source sans la supprimer, « Activer » la remet
  aussitôt (colonne `hidden`, base v6). Le panel, lui, pousse au maximum
  `MAX_SOURCES_PER_DEVICE` sources par MAC (6 dans le code du dépôt).
- **Redémarrer** fait une vraie mise à jour (`TvContentRefresh`) :
  1. nouvelle source du panel ;
  2. re-téléchargement des chaînes de chaque source active ;
  3. cache Films / Séries vidé.

  Une pastille « Mise à jour… » s'affiche pendant l'opération.
- **Automatique** :
  - panel lu toutes les 3 s (attente) ou 4 s (déjà en service) : activation
    ou liste retirée, sans re-télécharger les chaînes si rien n'a changé ;
  - mise à jour complète 2 min après l'ouverture, puis toutes les 6 h ;
  - jamais pendant Direct ou le lecteur (`TvActivity`).
- **Mise à jour de l'app** : la nouvelle version est pré-téléchargée en
  arrière-plan (3 min après l'ouverture, ou dès l'ouverture des Réglages).
  Le bouton ouvre alors directement l'installateur. Android exige toujours
  la confirmation « Installer » du client pour une app hors Play Store.

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

## Règle de stabilité : box de test d'abord (29/09/2026)

Incident v99–v101 : des changements du lecteur natif, compilés et testés
automatiquement, ont bloqué des chaînes sur l'écran de chargement chez les
clients (retour au lecteur v98 en v102). Désormais, toute modification du
lecteur (`packages/native_video_player`) ou du réseau suit ce circuit :

1. `build-zuno-tv.yml` → Run workflow avec **test_box = true** : l'APK part
   sur la release `zuno-tv-test`. Aucune box client n'est mise à jour
   (elles ne lisent que `zuno-tv/version.json`).
2. Sur UNE box : Downloader → `zuno.7themotion.com/test` → installer.
3. Vérifier : 5 chaînes (dont HD/4K), 1 film, 1 épisode, zapping rapide,
   coupure Wi-Fi de 10 s pendant la lecture.
4. Seulement si tout est bon : Run workflow avec **publish = true**
   (test_box = false) → les clients reçoivent la version.

## Secours du direct (29/09/2026)

Cas terrain : le serveur sert encore le Cinéma mais plus le direct.
`lib/features/player/domain/live_fallback.dart` + `tv_player_screen.dart` :

- Chaîne qui ne démarre pas → le lecteur essaie, 15 s chacun : l'adresse
  d'origine, les autres formats Xtream du même serveur (`.ts`, `.m3u8`,
  ancien chemin sans `/live/`), puis la même chaîne dans une autre source
  active du client (ou une autre qualité : HD ↔ FHD). Le format qui marche
  est retenu pour ce serveur pendant la session.
- Téléchargements du Cinéma mis en pause pendant le direct (abonnements à
  1 connexion), relancés à la sortie du lecteur.
- Correctif : après une 1re reconnexion ratée, le lecteur ne réessayait
  plus (roue infinie). Il réessaie désormais jusqu'au budget puis affiche
  « Réessayer ».
- Limite : si le fournisseur coupe réellement le direct pour ce compte et
  qu'aucune autre source ne contient la chaîne, rien ne peut la lire.
