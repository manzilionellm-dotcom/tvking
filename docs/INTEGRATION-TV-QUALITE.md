# Intégration « qualité TV » dans la maison mère

Branche de travail : `claude/integration-tv-quality-merge-on11p3`
Base : `claude/maison-mere-phone` (HEAD `43f751d`) — **aucun build supprimé**.

## 1. Constat de reconnaissance (mesuré, non présumé)

| Branche | HEAD | Pile | Produit | Signé |
|---|---|---|---|---|
| `claude/maison-mere-phone` | `43f751d` | **Flutter/Dart** + TV web `tv-tizen-webos/` (JS pur) + `admin-panel` (TS) + `gateway` + worker CF | android, tv, tizen, ios, ios-release, windows, prive, admin-panel | ✅ via GitHub Secrets |
| `main` | `59cbb86` | **Next.js/TypeScript** | — (workflows réduits) | — |
| `claude/tv-box-version-tv-6m5rph` (PR #6) | `78ffe8e` | **Next.js/TS** (= `main` + correctifs TV) | ci.yml (tests web) | — |

**Cause racine du blocage d'un merge naïf** : `main` n'est **pas** un snapshot réduit
de la maison mère. `git merge-base claude/maison-mere-phone main` ne renvoie **rien** —
histoires **non liées**, **piles différentes** (Flutter vs Next.js). Les correctifs TV
sont des composants React (`SpatialNav.tsx`, `Player.tsx`, `app/lib/*.ts`) : **aucun
fichier correspondant** dans la maison mère. Merger l'arbre Next.js dans le Flutter
supprimerait des fichiers ou ajouterait une app parallèle non testée. → **On porte le
comportement, on ne copie pas** (LOI 3).

De plus : **aucun SDK Flutter/Tizen dans l'environnement** (`node`/`java`/`gradle`
seulement) → impossible de compiler les apps de la maison mère localement. La preuve
« verte » locale se limite à la surface JS ; les builds signés relèvent de la CI
(VALIDATION_HUMAINE).

## 2. Où vit la « vraie » app TV dans la maison mère

Deux surfaces TV réelles : le Flutter `lib/` (Android TV) et **`tv-tizen-webos/`
(JS pur, embarqué dans les .tpk Tizen / .ipk webOS)**. Cette dernière est la
correspondance directe des correctifs TV Next.js et reçoit le portage.

## 3. Correctifs portés (fidèles, additifs, vérifiés)

| Correctif Next.js d'origine | État dans la maison mère | Action |
|---|---|---|
| SpatialNav — navigation D-pad | **déjà présent** (`nav.js` `move()`) | rien (parité constatée) |
| SpatialNav — touche RETOUR | **déjà présent** (`DFT.isBack` + `onBack`) | rien (parité constatée) |
| **SpatialNav — restauration du focus** | **manquant** (`focusFirst()` perdait la place) | **porté** → `focusKey.js` + `nav.enterScene()` + clés `data-fk` |
| **Player — touches média télécommande** | **bug latent** : `platform.js` déclare `MediaPlayPause/Play/Pause/Stop`, **rien ne les consommait** | **porté** → `mediaKeys.js` + dispatch `nav.onMedia()` + `player.toggle()/setPaused()` |
| tests + CI | absents pour la TV web | **ajoutés** → `node --test` + `.github/workflows/tv-web-tests.yml` |

### Écarté volontairement (ZÉRO FABRICATION — LOI 4)
- **Player seek ±10s / épisode suivant** : mappe un lecteur VOD ; la TV web est du
  **direct** (AVPlay/HLS) sans seek ni épisode → porter serait inventer une fonction.
  `mediaKeys.js` ne mappe donc que `toggle` (play/pause) et `stop`.
- **Error boundaries / télémétrie PII-free** : `lib/` Flutter a ses propres surfaces
  d'erreur ; ajouter des handlers globaux non testables sur un chemin de build signé
  risquerait de masquer des erreurs. À traiter en suivi ciblé si souhaité.
- **Bump Next 16.2.11 / budget de bundle** : sans objet (pas de Next dans la maison mère).

## 4. Fichiers touchés

Nouveaux (purs, ES5, `require()`-ables) :
`tv-tizen-webos/shared/js/focusKey.js`, `tv-tizen-webos/shared/js/mediaKeys.js`,
`tv-tizen-webos/test/focusKey.test.js`, `tv-tizen-webos/test/mediaKeys.test.js`,
`.github/workflows/tv-web-tests.yml`.

Modifiés (additifs) : `tv-tizen-webos/shared/js/{platform,nav,player,app}.js`,
`tv-tizen-webos/shared/index.html` (2 balises `<script>`).

**Non touchés** : aucun `config.xml`, `appinfo.json`, `AndroidManifest`, `pubspec`,
`Info.plist`, applicationId, permission — vérifié. Aucun secret dans le diff — vérifié.

## 5. Vérification (preuves locales)

```
# baseline AVANT modif : les 9 fichiers JS TV parsent → OK
# après modif :
node --check tv-tizen-webos/shared/js/*.js        # tous OK
node --test  tv-tizen-webos/test/*.test.js         # tests 9 / pass 9 / fail 0
```

Ce qui ne peut PAS être prouvé localement (SDK absent) → **CI / VALIDATION_HUMAINE** :
compilation .tpk (Tizen), .ipk (webOS) et les builds Flutter/mobile signés.

## 6. VALIDATION_HUMAINE — workflows signés à lancer (Actions → Run workflow)

À déclencher sur cette branche d'intégration ; la signature se fait DANS les workflows
via les secrets déjà configurés (non touchés) :

- `build-tizen.yml` — .tpk signé (secrets `SAMSUNG_AUTHOR_P12_BASE64` / `SAMSUNG_AUTHOR_PASSWORD`) ← **couvre le code TV porté**
- `build-tv.yml` — Android TV (APK/AAB, `ANDROID_KEYSTORE_*`)
- `build-android.yml`, `build-prive.yml` — mobiles (`ANDROID_KEYSTORE_*`)
- `build-ios-release.yml` — iOS signé → TestFlight (`APPLE_*`, `ASC_*`)
- `build-windows.yml`, `build-admin-panel.yml`, `deploy-worker.yml` — selon besoin

Non-signé mais utile en preuve verte : `tv-web-tests.yml` (ce PR), `quality.yml`
(analyze + tests Flutter).
