# 🛠️ MISSION INGÉNIEUR — Crash au changement de chaîne (lecteur TV)

> **Document de référence permanent.** À traiter avec rigueur, dans l'ordre.
> Ne pas supprimer : c'est le brief officiel du bug de stabilité n°1.

---

## 0. Coordonnées du projet

| | |
|---|---|
| **Repo** | `https://github.com/manzilionellm-dotcom/tvking` |
| **Branche de travail** | `claude/iptv-stability-crashes-i58zw6` |
| **App** | Flutter (Dart). Édition **TV** = entrée `lib/main_tv.dart`. |
| **Cibles** | Android TV / Fire TV / Google TV (UI 10-foot, télécommande D-pad). |
| **Build TV (CI)** | `.github/workflows/build-tv.yml` → publie la release `tv-latest`. |
| **Distribution** | `app.7themotion.com/tv` (proxy Cloudflare → `tv-latest`). |

---

## 1. Symptôme (priorité absolue, ouvert depuis ~2 mois)

L'app **se ferme brutalement** (le **process est tué** — ce n'est pas une exception Dart) **quand on change de chaîne**. Reproductible : **après ~5-6 changements de chaîne consécutifs**, l'app « disparaît ».

Pattern « après N zaps » ⇒ **accumulation de ressources** (décodeurs / mémoire) plutôt qu'une simple rafale.

### Repro
1. Installer la dernière TV (`app.7themotion.com/tv`) sur une **box bas de gamme**.
2. Ouvrir une chaîne, puis **zapper Haut/Bas 10-15 fois** (ou rester ~quelques secondes sur chacune).
3. → l'app se ferme avant la 10ᵉ.

---

## 2. Architecture du lecteur (à connaître avant de toucher)

- Le **DIRECT** n'utilise **pas** media_kit/mpv : il passe par le plugin **local**
  **`packages/native_video_player`** = **Media3 / ExoPlayer** rendu sur une vraie
  **`SurfaceView`** Android, en **Hybrid Composition** (`initExpensiveAndroidView`).
- La **VOD** (mobile uniquement) utilise media_kit. Hors sujet ici.

### Fichiers clés
| Rôle | Chemin |
|---|---|
| Écran lecteur TV (zap, overlay, watchdog) | `lib/features/tv/presentation/tv_player_screen.dart` |
| Moteur natif ExoPlayer | `packages/native_video_player/android/src/main/kotlin/com/manzilionellm/native_video_player/NativeVideoView.kt` |
| API Dart du lecteur natif | `packages/native_video_player/lib/native_video_player.dart` |
| Filets d'erreurs **Dart** globaux | `lib/core/app/guarded_main.dart` |
| Disjoncteur anti-boucle (safe mode) | `lib/core/app/boot_guard.dart` |
| Crash reporting (fail-open) | `lib/core/crash/crash_reporting_firebase.dart` |

---

## 3. Ce qui a DÉJÀ été tenté (correctifs à l'aveugle — à valider, pas à refaire)

> Tout ceci est **déjà mergé** sur la branche. À considérer comme l'état de départ.

- **Debounce du zap** (Dart) — `tv_player_screen.dart`, méthode `_zap()` :
  le numéro change tout de suite, mais l'ouverture du flux (`_open()` → `setUrl`)
  est différée de **350 ms** (timer `_zapSettle`) pour éviter la rafale d'ouvertures.
  *(commit `e5c82db`)*
- **Libération du décodeur entre chaînes** (natif) — `NativeVideoView.kt`,
  handler `"setUrl"` : `player.stop()` + `player.clearMediaItems()` **avant**
  `setMediaItem()` + `prepare()`. *(commit `276ed2a`)*
- **Tampon mémoire borné** — `NativeVideoView.kt`, `DefaultLoadControl` :
  `setBufferDurationsMs(2_500, 15_000, 1_000, 2_000)` (max 15 s au lieu de 30 s).
- **Anti-OOM codec** — `NativeVideoView.kt`, `MediaCodecSelector` custom :
  refuse le décodage **logiciel** de HEVC/AV1/VP9 (liste vide ⇒ `DECODER_INIT_FAILED`
  propre au lieu d'un OOM/segfault).
- **Gardes de cycle de vie** — `NativeVideoView.kt` : drapeau `@Volatile isReleased`,
  anti-double-`release()`, `stop()` + `clearVideoSurface()` avant `release()` dans `dispose()`.
- **Filets Dart** — `guarded_main.dart` : `ErrorWidget.builder`, `FlutterError.onError`,
  `PlatformDispatcher.onError`, `runZonedGuarded`.
- **Safe mode** — `boot_guard.dart` : si l'app reboucle, on saute les étapes lourdes.

---

## 4. ⛔ Le vrai blocage (à lever EN PREMIER)

**Aucun rapport de crash natif n'est actif en production.** Les 4 filets Dart de
`guarded_main.dart` **ne capturent PAS** les crashs **natifs** (ExoPlayer / MediaCodec /
SurfaceView / NDK). Donc **on n'a jamais la stack du vrai crash** → chaque correctif
ci-dessus est une **hypothèse**. Il faut arrêter de deviner.

---

## 5. Mission — dans l'ordre, avec rigueur

### Étape 1 — Voir le crash (débloquant)
- `firebase_crashlytics` est déjà au `pubspec.yaml` et câblé en **fail-open**
  (`lib/core/crash/crash_reporting_firebase.dart` ; activé par `attachCrashlytics()`
  dans `guarded_main.dart`). Il ne s'active qu'avec le secret CI **`GOOGLE_SERVICES_JSON`**.
- **À faire** : créer le projet Firebase, poser le secret dans le repo
  (Settings → Secrets → Actions), vérifier que les crashs **NDK/natifs** remontent
  (Crashlytics NDK). Confirmer un taux **crash-free** visible.

### Étape 2 — Reproduire + capturer la stack native
- Sur la box la plus faible, zapper en boucle jusqu'au crash.
- Récupérer la **stack native exacte** (Crashlytics, ou `adb logcat` filtré sur
  `DEBUG`/`AndroidRuntime`/`libc`/`MediaCodec` en secours).

### Étape 3 — Corriger la cause RACINE (confirmée par la stack)
Pistes probables à **valider** (ne pas implémenter à l'aveugle) :
- **Épuisement des instances MediaCodec** (limite très basse sur box d'entrée de gamme)
  — vérifier que le décodeur précédent est *réellement* relâché entre deux `setUrl`.
- **OOM** lors des `prepare()` répétés / tampon trop gros.
- **Cycle de vie SurfaceView / PlatformView** (Hybrid Composition) lors des
  changements rapides — recréation/détachement de la surface pendant un `prepare`.

### Étape 4 — Empêcher la régression
- **Test de charge automatisé** : « zapper N chaînes en boucle » (widget/integration test).
- Tests widget du lecteur (états buffering/erreur/zap), à exécuter en CI
  (`flutter test` + `flutter analyze` bloquants).

---

## 6. ✅ Definition of Done (mesurable)

- [ ] **Crashlytics actif**, crashs natifs remontés, taux crash-free **> 99,5 %**.
- [ ] **Zapper 50+ chaînes d'affilée** sur la box cible **sans aucune fermeture**.
- [ ] Cause racine **identifiée par la stack** (pas par hypothèse) et **corrigée**.
- [ ] **Test de charge zapping** + tests lecteur **qui passent en CI**.
- [ ] Aucune régression sur les acquis : pas d'ANR au boot, pas d'OOM grosse liste,
      reprise des enregistrements OK.

---

## 7. Contraintes projet (à respecter — cf. `AGENTS.md`)

- Commentaires **en français**, abondants et pédagogiques.
- **Aucune** playlist / URL de flux IPTV en dur dans le code de production.
- Toute dépendance ajoutée à `pubspec.yaml` doit être **documentée** (quoi + pourquoi).
- Couleurs / tailles via les tokens (`TvTokens` / `TvDimens`), pas de valeurs magiques.
- `android/` est **régénéré** à chaque build CI (`flutter create`) → tout natif custom
  doit vivre dans `packages/` (plugins locaux), jamais dans `android/app`.

---

*Document maintenu dans le repo : `docs/MISSION_INGENIEUR_CRASH_ZAP.md`.*
