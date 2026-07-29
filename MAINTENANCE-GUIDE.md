# MAINTENANCE-GUIDE — TV King / 7 MOTION / DEFEW TV

## Vue d'ensemble

Un seul projet Flutter (`tv_king`) porte plusieurs apps via des points
d'entrée distincts et l'injection de plateforme du lecteur :

| Entrée | App | Lecteur injecté |
|---|---|---|
| `lib/main.dart` | 7 MOTION mobile | media_kit (par défaut) |
| `lib/main_tv.dart` | DEFEW TV (Android TV/box) | ExoPlayer (native_video_player) |
| `lib/main_prive.dart` | Édition privée | media_kit |
| `lib/main_windows.dart` | Windows | media_kit (DesktopPlayerScreen) |
| `lib/main_tizen.dart` | Samsung Tizen | AVPlay (TizenPlayerScreen) |

Backend : Cloudflare Worker (`cloudflare/worker.js` + `api_v1.js`, D1/KV),
panel admin SPA (`admin-panel/`), déployés par `deploy-worker.yml` /
`deploy-admin-panel.yml`.

## Règle d'or : media_kit et le build TV

Le build TV **retire media_kit du pubspec**. Rien d'atteignable depuis
`main_tv.dart` ne doit l'importer (le lecteur TV passe par
`registerTvPlayer`). Le test `test/features/tv/tv_media_kit_import_guard_test.dart`
recalcule la fermeture d'imports et échoue si la règle est violée — il tourne
en CI (`quality.yml`). Si tu ajoutes un écran TV qui a besoin de vidéo, passe
par l'abstraction `TvPlayerScreen`, jamais par un import media_kit direct.

## Développement quotidien

```bash
export PATH=<flutter>/bin:$PATH
flutter pub get
flutter gen-l10n
flutter analyze --no-fatal-infos --no-fatal-warnings   # 0 erreur exigé
flutter test                                            # suite complète
bash scripts/qa-gates.sh   # (le cas échéant) la porte de merge
```

CI (barrières de merge, séparées des builds) : `quality.yml` (analyze +
tests), `tests.yml` (cœur métier). Les builds APK/AAB sont dans
`build-android.yml` / `build-tv.yml` / `build-prive.yml` / `build-tizen.yml`
/ `build-windows.yml`.

## Base de données locale (SQLite)

- Fichier : `tv_king.db`. Migrations dans
  `lib/features/playlists/data/playlist_database.dart` (`_onUpgrade`),
  **version actuelle 7**. Toute migration DOIT être idempotente (leçon du
  bug « duplicate column » du 2026-07-08) et les index créés en `try/catch`
  (un accélérateur ne doit jamais faire échouer une migration).
- EPG : table `epg_programs` avec index UNIQUE `(channel_id, start_time)`
  (import en REPLACE — voir EpgRepository). Le guide garde ~48 h de futur ;
  `resyncEpgAll()` (main_tv, 12 h) le rafraîchit — la clé de chaîne est
  `external_id` (= `Channel.id`), PAS `id` (colonne inexistante).

## Sécurité — invariants à ne pas casser

- Tout secret d'abonné passe par `SecretRedactor` avant le moindre puits de
  log/crash (point d'étranglement : `CrashReporting.recordError`, y compris
  le backend distant). Ajoute les nouveaux noms de paramètres/en-têtes
  sensibles à `secret_redactor.dart` (couvert par tests).
- Identifiants Xtream chiffrés au repos via `SecretCipher` (Keystore). Un
  point d'écriture, un point de lecture — ne les contourne pas.
- Côté Worker : `ADMIN_SECRET` est obligatoire (fail-closed, pas de repli).
  Sans lui, aucun JWT n'est valide et aucun super_admin n'est créé. Pose-le
  via `set-admin-password.yml` ou `wrangler secret put`.
- Les workflows publiant une release CLIENTE (`prod`, `tv-prod`,
  `prive-latest`) sont gardés sur `claude/maison-mere-phone`/`main`. Ne
  publie jamais un canal client depuis une branche de feature.

## Lecteur vidéo — points de vigilance

- Mobile (media_kit) : instance jetable recyclée avant chaque ouverture
  (`_recyclePlayer`) ; le recyclage vérifie `mounted`/`_disposed` pour ne pas
  fuiter une instance après fermeture. Cycle de vie géré
  (`WidgetsBindingObserver`) : pause hors PiP/cast/audio-only, position VOD
  sauvée au zap/arrière-plan/dispose.
- TV (ExoPlayer) : les écrans qui poussent une route par-dessus le lecteur
  (Guide, Multi-vue) doivent le mettre en pause et libérer les timers avant
  le push, puis recharger le flux au retour. Le watchdog anti-gel est
  suspendu en veille et ne s'applique qu'au live.
- Ouverture du lecteur TV : toujours via `openTvPlayer` (verrou anti
  double-ouverture partagé).

## Où trouver quoi

- Audits : `AUDIT-MOBILE.md`, `AUDIT-TV.md`, `SECURITY-AUDIT.md`.
- Perf : `PERFORMANCE-BEFORE.md` / `PERFORMANCE-AFTER.md`.
- Ce qui a été corrigé : `FIXES-APPLIED.md`. Reste à faire : backlog
  `.company/backlog.json`.
- Rollback : `ROLLBACK-PLAN.md`. Release : `RELEASE-CHECKLIST.md`.
- Matrices de test : `TEST-MATRIX-MOBILE.md`, `TEST-MATRIX-TV.md`.
