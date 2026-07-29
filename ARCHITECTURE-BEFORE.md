# ARCHITECTURE-BEFORE — État au début de l'audit (2026-07-29)

Branche d'audit : `claude/audit-mobile-tv-delivery-ghn12o`
Base : fusion de `claude/usine-app-v3-iptv-mjbjts` (canonique MOBILE, 37220df)
et `claude/integration-tv-quality-merge-on11p3` (canonique TV, 87d9ef2) —
ancêtre commun `43f751d`, fusion sans conflit (commit `25d7cb3`).

## Les deux applications

| Application | Nom commercial | Point d'entrée | Lecteur vidéo | Canal de release |
|---|---|---|---|---|
| Mobile Android | 7 MOTION (« The Few ») | `lib/main.dart` | media_kit (libmpv) | `prod` (7motion.apk) |
| Android TV / Box | DEFEW TV / SEVEN | `lib/main_tv.dart` | native_video_player (ExoPlayer, package local) | `tv-prod` (defew-tv.apk + .aab) |

Un SEUL projet Flutter (`tv_king`, version 0.3.3+12) porte les deux apps ;
les dossiers natifs Android sont régénérés en CI (`flutter create`) puis
patchés par les workflows (`build-android.yml`, `build-tv.yml`). Le build TV
RETIRE `media_kit` du pubspec avant compilation — aucun code atteignable
depuis `main_tv.dart` ne doit l'importer.

Autres cibles du même code : `main_prive.dart` (édition privée),
`main_windows.dart` (PC), `main_tizen.dart` (Samsung), `tv-tizen-webos/`
(port web Tizen/webOS séparé, JS pur).

## Découpage du code (lib/, 364 fichiers Dart, ≈118 000 lignes)

- `core/` : app, backend (API panel Cloudflare), branding, crash
  (SecretRedactor, reporting), flavor, i18n (8 langues), net (DoH),
  network, notifications, observability (BlackBox, StructuredLogger),
  profiles, realtime, security, theme, update (UpdateService in-app),
  widgets.
- `features/` : playlists (M3U + Xtream Codes, SQLite), channels, epg
  (XMLTV + get_short_epg, isolate de parsing), player (mobile media_kit :
  cascade de fallback, relais HLS local, watchdogs), tv (UI 10-foot :
  focus D-pad, rails, Cinéma VOD, lecteur ExoPlayer, CinePerf,
  TvPosterPrefetch), vod (catalogue, téléchargements série-par-série,
  reprise), cast (Chromecast/DLNA, remux fMP4), recordings,
  subscription, device (identité), settings, sports, admin, hue
  (Philips Hue), sécurité (PIN), stats.
- `packages/native_video_player` : plugin local ExoPlayer (chemin TV).
- `packages/tvking_device` : plugin local identité device.

## Backend / services

- `cloudflare/` : Worker (panel admin, API v1, receiver Cast, portail
  client, PWA) + D1/KV. Déployé par `deploy-worker.yml`.
- `admin-panel/` : SPA Vite/React (Cloudflare Pages).
- `gateway/`, `server/` : composants annexes.

## Chaîne de build & signature (état constaté)

- `build-android.yml` : APK release split-per-abi obfusqué + AAB, signé
  par la clé maîtresse (`ci/release.jks.enc` déchiffré via secret
  `ANDROID_KEYSTORE_PASSWORD`, ou secret base64) ; publication client
  UNIQUEMENT depuis `claude/maison-mere-phone` ET dispatch manuel
  `make_release=true` (canal téléphone volontairement coupé).
- `build-tv.yml` : APK TV universel + AAB TV (target `main_tv.dart`),
  même clé maîtresse, publication `tv-prod`/`tv-latest` UNIQUEMENT depuis
  `claude/maison-mere-phone` ; autres branches → artefacts de run.
- `publish-phone-test.yml` / `publish-cinema-test.yml` : republient
  l'APK d'un run donné en prérelease `phone-test` / `cinema-test` à lien
  direct (jamais `latest`/prod, invisibles de l'updater in-app).
- Barrières qualité : `quality.yml` (analyze + suite complète),
  `tests.yml` (sous-ensemble cœur métier), séparées des builds.

## Tests (avant audit)

76 fichiers de test, ≈806 cas. Dernier état documenté (run-003 usine,
2026-07-25) : 664/664 verts en CI ; les tests sqflite_ffi échouent
localement en sandbox (binaire sqlite3 non téléchargeable) mais passent
en CI.

## Dettes connues héritées (backlog .company avant cet audit)

B1 observabilité vidéo mobile (TTFF/zapping) · B2 watchdogs pistes ·
B3 harnais mock media_kit · B4 audit deps (43 majeures bloquées, un
paquet discontinué) · B5 thème Daylight non branché · B6
home_screen.dart legacy · B7 264 infos analyze · B8 lockfile non commité ·
B9 veille concurrents.
