# Audit A→Z & durcissement — DeFew TV (7 MOTION)

> Branche : `claude/defew-tv-hardening-tbhlrw`
> Méthode : audit exhaustif du périmètre TV par 4 revues parallèles, puis
> corrections par lots compilables (chaque lot : `flutter analyze` 0 erreur +
> `flutter test` verts avant de continuer). Zéro régression cinéma/VOD.
> État de validation local : **analyze 0 erreur**, **645 tests verts**.

Chaque affirmation ci-dessous est vérifiable dans le diff de la branche.

---

## 0. Point de départ — reconstruction de la base de travail

`main` ne contient PAS l'app Flutter (ancien site Next.js). Le code TV vit sur
des branches de travail qui ont divergé. La branche de durcissement a été
reconstruite comme suit :

- **base** : `claude/seven-cinema-vod-venljh` (ligne de production la plus
  récente — correctifs DNS/VOD, EPG courte, premium) ;
- **fusion** des 24 commits de performance TV de
  `claude/tv-seven-perf-audit-troi2a` (rebuilds, caches bornés, release
  ExoPlayer hors main thread).

Deux **régressions de fusion** détectées et corrigées :

| Fichier:ligne | Défaut | Correctif |
|---|---|---|
| `tv_channels_screen.dart` (aperçu En direct) | conflit cadre focusable vs tap tactile + EPG | cadre `_PreviewFrame` focusable D-pad + en-tête « NOS ÉVÉNEMENTS » + cascade EPG fenêtre glissante → EPG courte → catégorie |
| `xtream_client.dart:_parseLiveChannelsIsolate` | le mapping déplacé en isolate court-circuitait la collecte des alias `epg_channel_id` → « Programme non disponible » sur le chemin rapide | l'isolate renvoie `(channels, aliases)`, l'appelant fusionne (borné anti-OOM) — test `epg_alias_short_epg_test` de nouveau vert |

---

## 1. CRITIQUE

### C1 — DoH acceptait n'importe quel certificat TLS (MITM / vol d'identifiants)
`lib/core/net/doh_resolver.dart` — `badCertificateCallback => true`.
Un attaquant on-path (Wi-Fi hostile, ou l'opérateur qui bloque) pouvait se
faire passer pour `1.1.1.1`/`8.8.8.8`, forger la réponse DNS et détourner
l'app vers un serveur pirate — qui recevait alors l'URL Xtream
(**identifiants dans le chemin**) en HTTP clair.
**Correctif** : le certificat des résolveurs DoH est validé NORMALEMENT (leur
IP est dans le SAN → la validation par défaut passe). Un TLS intercepté échoue
proprement et on retombe sur le DNS système. Accessibilité préservée,
authenticité jamais sacrifiée. *(tests DoH verts)*

---

## 2. MAJEUR

### M1 — Chiffrement des identifiants reconstructible (`secret_cipher`)
`lib/core/security/secret_cipher.dart`. La clé AES était dérivée du seul
`ANDROID_ID` + un sel codé en dur — or `ANDROID_ID` est lisible sur l'appareil
(root/backup), soit **exactement le modèle de menace visé**.
**Correctif** : racine de confiance **matérielle** (patron DEK/KEK). Une DEK
aléatoire de 32 octets (utilisée par le Dart en AES-GCM) est conservée
enveloppée par une clé AES-256-GCM du **Android Keystore**, non exportable
(TEE/StrongBox). Root/backup ne récupèrent que le blob enveloppé.
- natif `tvking_device` : `getCredentialKey` (enveloppe/déballe via la KEK) ;
- Dart : marqueur `enc:v2:` préféré, `enc:v1:` conservé pour **lire**
  l'existant (migré en v2 au prochain enregistrement) et comme repli API<23 ;
- fail-open intégral (aucune régression de lecture). *(tests round-trip v2 +
  migration verts)*

### M2 — PIN en clair, sans anti-brute-force (`app_pin_settings`)
Le PIN garde aussi le **Mode Enfants**. Il était stocké **en clair** et
`_tryPin` rejouable à l'infini.
**Correctif** :
- stockage **haché** salé + itéré (HMAC-SHA256 × 20 000, sel `Random.secure`) —
  un accès fichier ne révèle plus le code ; migration du clair au 1er succès ;
- **verrouillage progressif** : 4 essais libres puis blocage croissant
  (30 s, 1 min, 2 min… plafonné 15 min) ; `lock_screen` affiche la durée
  restante (clé i18n `lockPinLocked` ×8 langues). *(11 tests verts)*

### M3 — Fuite d'identifiants dans les journaux (crash/observabilité)
`lib/core/crash/`. Les messages d'erreur (ring de diag, boîte noire sur
**disque**, POST `/api/error-log`) embarquaient l'URI Xtream complète, mot de
passe de l'abonné en clair.
**Correctif** : nouveau `SecretRedactor` (pur, testé) appliqué au point
d'étranglement unique `CrashReporting.recordError` → couvre **tous** les
puits d'un coup. Masque userinfo, chemins `/live/USER/PASS/`, query
`username=`/`password=`/`token=`. *(7 tests verts)*

### M4 — Faux positif de l'ABR après le burst de démarrage (`stream_stability_monitor`)
Le débit nominal était un **maximum qui ne redescendait jamais**. La pointe de
remplissage du tampon au démarrage figeait le seuil trop haut → le régime
établi, pourtant sain, passait pour un « déficit » et déclenchait une
**descente de qualité à tort** (à l'encontre de la mission « ne pas dégrader à
tort »).
**Correctif** : fenêtre de **warmup** (12 s) où l'on n'apprend rien et ne juge
rien (la 1re mesure post-warmup amorce le lissage sur le débit RÉEL) +
**enveloppe** du nominal (attaque immédiate, release lente). *(nouveau test
« burst puis régime stable → aucune descente » vert)*

### M5 — Course d'enregistrement → session orpheline (`local_stream_relay`)
`startRecording` posait `recordSink` **après** un `await`. Si le dernier
lecteur se débranchait pendant l'await, la session pouvait être fermée →
le sink s'attachait à une session orpheline (fichier jamais alimenté,
descripteur jamais fermé).
**Correctif** : revérification que la session est toujours enregistrée après
l'await, ré-ouverture propre sinon (REC seul est un cas valide).

### M6 — Double-ouverture du lecteur (écrans TV)
`_openPlayerWith` (tv_live_screen) et `_play` (tv_movie_detail_screen)
n'avaient aucune garde de ré-entrée. Une double-activation rapide empilait
**deux `TvPlayerScreen`** → deux ExoPlayer + une 2e connexion amont, contre la
garantie « 1 flux / 1 connexion ».
**Correctif** : garde `_openingPlayer` posée avant le push, relâchée dans un
`finally` au retour.

### M7 — `country_home` : écran vide sans feedback
`_build` n'avait aucune branche vide → si `channels` était vide (import échoué,
région bloquée), l'écran était quasi blanc — exactement la plainte « ça ne
marche pas » sans indication.
**Correctif** : état vide explicite (icône + titre + message actionnable, clé
`countryHomeEmptyBody` ×8 langues + bouton « Réessayer » optionnel), couleurs
et typo via AppColors/AppTextStyles.

### M8 — Cache DoH non borné (OOM box faible RAM)
Les panels à domaine **wildcard** génèrent des sous-domaines à la volée →
la map de cache grossissait sans fin.
**Correctif** : plafond 256 entrées (purge des périmés + éviction FIFO) +
cache **négatif** (TTL 45 s : un hôte mort coûtait ~14 s à chaque essai) +
repli **AAAA** (réseaux IPv6-only). *(tests dédiés verts)*

---

## 3. MODÉRÉ / MINEUR corrigés

| # | Fichier | Défaut | Correctif |
|---|---|---|---|
| 1 | `local_stream_relay` | `cReq.close()` borné seulement par `connectionTimeout` (TCP) → serveur muet fait pendre jusqu'à 10 min | timeout de réponse 20 s |
| 2 | `local_stream_relay` | back-off de reconnexion déterministe → sessions en phase martèlent le panel | jitter 0-1000 ms |
| 3 | `tv_diagnostics_service` | `stream.listen((_){})` sans `onError` → erreur async non gérée | `onError` + `cancelOnError` |
| 4 | `source_preflight` / `source_link_utils` | `ensureScheme` acceptait tout schéma (`file://`, `gopher://`, `javascript:`) → injection/SSRF | whitelist http/https (`isAllowedSourceUrl`) appliquée avant tout fetch (les URLs de FLUX rtmp/rtsp ne sont pas touchées) |
| 5 | `local_cast_server` (`/current`) | JSON construit à la main → caractères de contrôle d'un titre M3U cassaient le `poll()` | `jsonEncode` |
| 6 | `tv_multiview_screen` | volume non ré-appliqué après `setUrl` au resume → 2 tuiles sonores | `setVolume` par tuile après chaque `setUrl` |
| 7 | `stream_blocked_fallback` | gardes anti-boucle jamais réarmées → un aller-retour de zap partait direct en « bloquée » sans re-sonder | `noteFramesDecoded()` appelé à la 1re image réelle |
| 8 | `cellular_guard` | `checkConnectivity()` sans timeout → lecture jamais démarrée si le plugin pend | timeout 3 s + repli fail-open |

---

## 4. Sécurité — ce qui protège, et contre quoi

| Menace | Protection en place |
|---|---|
| **Décompilation / vol de code** | build TV : `--obfuscate --split-debug-info=build/symbols` (APK **et** AAB), R8 `isMinifyEnabled` + `isShrinkResources` + ProGuard (`build-tv.yml`). Symboles de debug non publiés (seuls APK/AAB le sont). |
| **Vol des identifiants d'abonné au repos** | chiffrement AES-GCM avec **racine matérielle** Android Keystore non exportable (M1) ; anciennes valeurs migrées v1→v2. |
| **Fuite d'identifiants par les journaux** | caviardage au point d'étranglement `CrashReporting.recordError` (M3) — disque ET réseau. |
| **MITM / empoisonnement DNS** | validation TLS des résolveurs DoH (C1). |
| **Forçage du PIN (app + Mode Enfants)** | hachage salé itéré + verrouillage progressif (M2). |
| **Injection / SSRF via URL collée** | whitelist de schéma http/https sur les sources (Minor 4). |
| **Injection JSON (cast)** | sérialisation `jsonEncode` (Minor 5). |
| **URL de flux / playlist en dur** | aucune trouvée dans `lib/` (audit : seules URLs = backend maison, GitHub Releases, placeholders UI). Règle n°2 AGENTS.md respectée. |

Absence de secret/clé en dur confirmée par l'audit ; les logs touchant des
credentials les masquaient déjà (`StreamDiagnostics.maskCredentials`), désormais
complétés par le caviardage global.

---

## 5. Résiduels documentés (non corrigés — compromis assumé)

- **BootGuard — faux déclenchement du mode sans échec sur réseau lent**
  (`boot_guard.dart` + `main_tv.dart`). L'analyse montre que
  `RemoteSourceRepository.sync()` **ne bloque jamais** (retourne un résultat
  même réseau KO → `markBootSucceeded` se déclenche après ~16 s), donc la
  fenêtre de faux positif est étroite, pas indéfinie. Le seul correctif propre
  (distinguer « crash natif » d'« utilisateur qui ferme » via un flag de sortie
  propre) exige de câbler un observateur de cycle de vie dans le **chemin de
  boot critique**, non testable dans cet environnement. **Compromis** : ne pas
  toucher au boot au risque de réintroduire l'ancien flaw (reset-par-timer qui
  ratait les crashes d'import). Recommandé pour une session dédiée avec appareil
  de test.
- **Credentials Xtream base64 (non chiffré) vers le Worker sur le chemin
  Chromecast** (`cast_manager.dart`). Par design (backend maison). Recommandé :
  HMAC + token court-vécu plutôt qu'un base64 réversible.
- **`LocalCastServer.stop()` jamais appelé** — hygiène de ressources (la socket
  d'écoute LAN reste ouverte après un cast) ; les tokens de relais sont bien
  purgés (pas de fuite du flux abonné). À brancher quand plus aucune session de
  cast/browser n'est active.

---

## 6. Récapitulatif des livraisons (par commit)

1. Fusion base Cinéma + 24 commits perf TV (résolution de conflit).
2. Pont EPG : alias `epg_channel_id` survivent au mapping en isolate.
3. Sécurité réseau : DoH authentifié + anti-fuite d'identifiants + DoH robuste.
4. Sécurité stockage : clé matérielle Keystore + PIN durci.
5. Robustesse lecture : anti-faux-positif ABR, course REC, timeouts, jitter.
6. UX TV : garde anti-double-lecteur + état vide actionnable.
7. Sécurité entrées + cast : whitelist schéma, JSON échappé, volume multiview.
8. Robustesse : réarmement fallback zap + timeout cellular_guard.

Aucune release créée (conformément à la consigne).
