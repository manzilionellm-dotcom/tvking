# Durcissement Android TV / Box — rapport de production

> Objectif : app Android TV / Google TV / box de qualité production, taux de
> crash le plus bas possible, démarrage qui ne se ferme **jamais** tout seul.
>
> Ce document est **honnête** : il distingue ce qui est **fait dans le code**,
> ce qui est **partiel**, et ce qui **exige un vrai appareil / un secret** et ne
> peut donc pas être produit depuis le CI seul (on ne fabrique pas de chiffres).

---

## 1. Démarrage — « ne crashe jamais »

| Élément | État | Où |
|---|---|---|
| Filet d'erreurs global (4 niveaux) sur **tous** les flavors | ✅ Fait | `lib/core/app/guarded_main.dart` (`runGuarded`) |
| Mobile (`main.dart`) et Privé (`main_prive.dart`) sous filet | ✅ Fait (corrigé) | avant : non protégés |
| TV (`main_tv.dart`) sous le **même** filet mutualisé | ✅ Fait | dé-duplication |
| `MediaKit.ensureInitialized()` gardé (try/catch) | ✅ Fait | mobile + TV |
| Init lourde **non bloquante** (`unawaited`) | ✅ Déjà en place | boot async |
| Chargements bloquants bornés par `timeout` | ✅ TV (6 s playlist) | anti-ANR |

Les 4 filets : `ErrorWidget.builder` (sous-arbre qui plante → fond noir, le
reste tourne), `FlutterError.onError`, `PlatformDispatcher.onError` (return
`true`), `runZonedGuarded` (filet ultime du boot). Toute erreur captée part
vers `CrashReporting` (journal local + Crashlytics si configuré).

### Exceptions couvertes
Le filet Dart capte : exceptions Dart, `IllegalState/Argument`, `Null`,
`InflateException` (via build/paint), `RuntimeException` remontées au canal
plateforme, erreurs async/coroutines, `Future` non rattrapés. Les crashes
**purement natifs** (NDK/JNI, `UnsatisfiedLinkError` profond, `SIGSEGV`,
`OutOfMemoryError` natif) ne sont **pas** rattrapables en Dart : ils sont
couverts par **Crashlytics** (§4), qui les remonte sans pouvoir les empêcher.

---

## 2. Compatibilité ABI

`flutter build apk` (TV) = **APK universel** ; mobile = `--split-per-abi` (un APK par ABI) + AAB.

| ABI | Livré ? | Note |
|---|---|---|
| `arm64-v8a` | ✅ | box / TV / téléphones modernes |
| `armeabi-v7a` | ✅ | **Fire Stick 32 bits**, vieilles box |
| `x86_64` | ✅ | émulateurs, quelques box Intel |
| `x86` (32 bits) | ❌ | **Limite Flutter** : non supporté par le moteur. Quasi disparu du parc. |

**Conclusion** : couverture maximale possible sous Flutter. Le `x86` 32 bits est
une limite de plateforme, pas un bug.

---

## 3. Vidéo / codecs

| Élément | État | Où |
|---|---|---|
| Décodage matériel (MediaCodec) + **repli logiciel** auto | ✅ Déjà | ExoPlayer `setEnableDecoderFallback(true)` (`packages/native_video_player`) |
| `hwdec=auto-safe` (repli soft) côté mpv | ✅ Déjà | `media_kit` player |
| Re-connexion réseau agressive (IPTV qui coupe) | ✅ Déjà | `DefaultLoadErrorHandlingPolicy(6)`, reconnect mpv |
| HEVC / AVC / MPEG / AC3 / EAC3 | ⚠️ Dépend de l'appareil | MediaCodec liste les codecs matériels ; repli soft sinon. Aucun crash si codec absent (le lecteur émet une erreur captée). |

Aucune incompatibilité de codec ne tue l'app : l'échec passe par le flux
d'erreur du lecteur → message à l'utilisateur, pas de crash.

---

## 4. Rapport de crash — Firebase Crashlytics

| Élément | État |
|---|---|
| Abstraction `CrashReporting` (provider-agnostique) | ✅ Fait |
| Branchement Crashlytics **fail-open** | ✅ Fait |
| Remontée crashes Dart + natifs (JNI/NDK) | ✅ via Crashlytics |
| Contexte appareil (modèle, fabricant, OS, ABI, RAM…) | ✅ collecté **automatiquement** par le SDK natif |
| Actif par défaut | ❌ **Désactivé tant que le secret n'est pas posé** |

### Activer Crashlytics (3 étapes)
1. Créer un projet Firebase, ajouter une app Android par `applicationId`
   (`com.manzilionellm.tvking`, `…prive`), télécharger `google-services.json`.
2. Déposer son **contenu** dans le secret GitHub `GOOGLE_SERVICES_JSON`.
3. Relancer un build : les workflows écrivent le fichier et appliquent le
   plugin Gradle ; `attachCrashlytics()` s'active au démarrage.

Sans ces étapes : aucun changement de comportement, build vert, journal local
uniquement (`CrashReporting.recentErrors`).

> Note : le même secret doit être ajouté au workflow `build-prive.yml` si on
> veut Crashlytics sur le flavor Privé (patch identique à `build-tv.yml`).

---

## 5. Android TV — ergonomie 10-foot

| Élément | État |
|---|---|
| Manifest **Leanback** + `LEANBACK_LAUNCHER` | ✅ Workflow TV |
| `touchscreen` / `leanback` `required="false"` | ✅ (s'installe partout) |
| Bannière Android TV de marque | ✅ Workflow TV |
| Paysage verrouillé sur TV | ✅ `main_tv.dart` |
| Clamp du `textScaler` (accessibilité TV ne casse plus les layouts) | ✅ Déjà |
| Navigation D-pad / gestion du focus | ⚠️ Couverte par les écrans `features/tv/` — **à valider sur vrai matériel** |

---

## 6. Build / réduction

| Élément | État |
|---|---|
| Obfuscation Dart (`--obfuscate` + `--split-debug-info`) | ✅ Déjà |
| Signature **stable** (update sans désinstaller) | ✅ Déjà (keystore fixe) |
| `versionCode` strictement croissant | ✅ Déjà |
| R8 / shrink ressources / ProGuard | ⚠️ Par défaut Flutter release (R8 actif). **Pas de règles keep custom auditées** — à faire si on ajoute des libs réfléchies par réflexion. |

---

## 7. Ce qui exige un vrai appareil (non produit ici)

Honnêteté : ces livrables **ne peuvent pas** être générés depuis un runner CI
sans matériel ni secrets. Ils se produisent en test terrain.

- **APK/AAB signés** : produits par les workflows GitHub (artefacts/Release),
  pas par cette session.
- **Rapport Crashlytics réel** : se remplit avec le trafic de production une
  fois le secret posé (§4).
- **Matrice d'appareils testés** : se construit depuis Crashlytics + tests
  manuels. On ne **fabrique pas** de liste fictive.
- **Benchmarks démarrage / mémoire** : à mesurer sur cible avec
  `flutter run --profile --trace-startup` (sort `start_up_info.json` :
  `timeToFirstFrameMicros`, etc.) et le **Memory view** de DevTools. Aucun
  chiffre n'est inventé ici.
- **LeakCanary** : outil **Kotlin natif** (pas Flutter). Sur Flutter, la
  détection de fuites passe par DevTools (Memory) ; LeakCanary n'a de sens
  que si on ajoute du code natif Android custom. Marqué **N/A** pour l'instant.

### Procédure de profilage démarrage (à exécuter sur la box cible)
```bash
flutter run --profile --trace-startup -t lib/main_tv.dart
# → build/start_up_info.json : engineEnterTimestampMicros,
#   timeToFirstFrameRasterizedMicros, timeToFirstFrameMicros
```

---

## 8. Limitations connues

- `x86` 32 bits non supporté (limite Flutter).
- Crashes **natifs** non *empêchables* en Dart (seulement *rapportés* via
  Crashlytics).
- Codecs matériels = dépendants de l'appareil (repli logiciel sinon).
- Règles ProGuard/R8 custom non auditées (R8 par défaut actif).
- Validation D-pad / focus TV à confirmer sur vrai matériel.
- Crashlytics **désactivé** tant que `GOOGLE_SERVICES_JSON` n'est pas posé.
