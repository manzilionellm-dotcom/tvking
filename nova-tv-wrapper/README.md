# tv-android-wrapper

> APK Android TV / Fire TV minimal qui embarque `tv-web/dist/` dans une
> WebView. Cible Downloader.

---

## Statut : WIP — fichiers de fondation poses

Le projet Gradle est ECRIT mais pas encore BUILD. Pour qu'il compile,
il manque :

- [ ] **Gradle wrapper** (`gradlew`, `gradlew.bat`, `gradle-wrapper.jar`,
      `gradle-wrapper.properties`). A bootstrap au premier build via
      `gradle wrapper` sur une machine avec Gradle 8.5+ installe.
- [ ] **Icones launcher** (`res/mipmap-*/ic_launcher.png` et
      `ic_launcher_round.png`). A generer par ImageMagick depuis
      `../assets/branding/logo_7motion.jpg` au moment du build CI.
- [ ] **Banner Android TV** (`res/drawable/tv_banner.png`, 320x180px
      obligatoire pour Leanback). Idem ImageMagick.
- [ ] **CI workflow** `.github/workflows/build-tv-wrapper.yml` qui :
      1. Lance `npm run build` dans `tv-web/`
      2. Copie `tv-web/dist/*` vers `tv-android-wrapper/app/src/main/assets/web/`
      3. Genere les icones + banner via ImageMagick
      4. Bootstrap le gradle wrapper si absent
      5. Lance `./gradlew assembleDebug`
      6. Upload `app-debug.apk` en GitHub Release `tv-latest`

---

## Architecture

```
tv-android-wrapper/
├── settings.gradle.kts
├── build.gradle.kts             (racine — pin AGP 8.5.2 + Kotlin 1.9.24)
├── gradle.properties            (heap 4 Go, AndroidX activé)
├── app/
│   ├── build.gradle.kts         (minSdk 23, targetSdk 34, AppCompat + androidx.webkit)
│   └── src/main/
│       ├── AndroidManifest.xml  (LEANBACK_LAUNCHER + tactile non requis)
│       ├── kotlin/com/manzilionellm/tvkingtv/
│       │   └── MainActivity.kt  (WebView + WebViewAssetLoader)
│       ├── res/
│       │   ├── values/
│       │   │   ├── strings.xml
│       │   │   ├── themes.xml
│       │   │   └── colors.xml
│       │   └── xml/
│       │       └── network_security_config.xml  (HTTP autorise)
│       └── assets/web/          (vide tant que CI n'a pas tourne)
└── gradle/wrapper/              (a generer)
```

## Strategie d'embedding

`MainActivity` instancie une `WebView` configuree avec
`WebViewAssetLoader` :

- Les assets statiques de `tv-web/dist/` sont servis sous une URL
  synthétique `https://appassets.androidplatform.net/assets/web/...`.
- Pourquoi pas `file:///android_asset/...` ? Parce que les requetes
  XHR vers les serveurs IPTV (Xtream) sont bloquees par la
  Same-Origin Policy quand la page d'origine est en scheme `file:`.
  L'AssetLoader sert sous HTTPS et CORS fonctionne normalement.
- L'APK est donc **autonome / offline-first** pour la partie UI.
  Seuls les flux IPTV (HTTP vers serveur user) sortent vers internet.

## Versions

- AGP 8.5.2 + Kotlin 1.9.24 + Gradle 8.7+ (recommande)
- Android Min SDK 23 (Marshmallow) — couvre les Android TV modernes,
  exclut le Fire TV Stick 1st gen (API 22) volontairement (son WebView
  ne supporte pas MSE → hls.js casse).

## A faire dans une session future

1. Bootstrap le gradle wrapper (`gradle wrapper --gradle-version 8.7`).
2. Ajouter le CI workflow (cf. checklist ci-dessus).
3. Tester le build APK local sur un poste avec Android SDK.
4. Brancher la publication GitHub Release `tv-latest` + URL Downloader
   courte type `https://99999.7themotion.com/tv` qui redirige.
