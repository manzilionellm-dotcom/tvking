# Cast — Architecture actuelle

> **Statut du document** : audit Phase 0 (lecture seule). Aucune
> recommandation, aucune proposition de refactor — uniquement la
> description **factuelle** de ce qui existe dans le code au
> 2026-05-31. Toutes les conclusions pointent vers le fichier et
> la ligne. Toute affirmation non vérifiée empiriquement est
> préfixée par **[HYPOTHÈSE]**.

---

## 1. Vue d'ensemble

Le sous-système Cast permet à l'app 7 MOTION / Red Room d'envoyer
un flux IPTV vers un récepteur réseau (TV connectée, Chromecast,
Roku, ou navigateur web via QR code). Il vit principalement dans
deux dossiers :

| Couche | Chemin | Contenu |
|---|---|---|
| Dart — données | `lib/features/cast/data/` | 16 fichiers, ~3 800 LoC |
| Dart — UI | `lib/features/cast/presentation/` | 6 fichiers |
| Native Kotlin | `android_overlay/google_cast/` | 3 fichiers Cast (+ MainActivity wiring) |
| Cloudflare Worker | `cloudflare/worker.js` | route `/cast-receiver` + `/cast-skin.css` |

Quatre **transports** distincts, sélectionnés par device :

- **DLNA / UPnP AVTransport** → la majorité des Smart TV
  (Samsung, LG, Sony, Philips). Pile SOAP custom + chaîne de
  failover 5 niveaux.
- **Google Cast SDK natif** → Chromecast, Google TV. Bridge
  Kotlin (`GoogleCastApi.kt`) qui parle au SDK Google Play
  Services. Receiver custom App ID `46F815A5` (publié).
- **Roku ECP** → TVs et dongles Roku (endpoint `:8060`).
- **Web Browser (QR code)** → fallback universel. L'app héberge
  un mini serveur HTTP local qui sert une page HTML5 `<video>` ;
  l'utilisateur scanne le QR sur sa TV.

---

## 2. Composants — inventaire

### 2.1 Couche Dart (`lib/features/cast/data/`)

| Fichier | Rôle | LoC |
|---|---|---|
| `cast_manager.dart` | Singleton `ChangeNotifier`, orchestre tout le cycle de vie d'une session. Contient l'état (`CastState`), la chaîne de failover DLNA 5 niveaux, le ring buffer diagnostics. | 607 |
| `cast_transport.dart` | Interface abstraite + factory `forDevice(device)` qui dispatch par `CastDeviceKind`. | 59 |
| `upnp_av_transport.dart` | Client SOAP UPnP AVTransport:1. Trois `MetadataMode`, polling `GetTransportInfo`, détection LG/Samsung pour User-Agent custom. | 439 |
| `google_cast_transport.dart` | Wrapper Dart du MethodChannel Cast. Polling `hasActiveSession()` 30s. | 132 |
| `roku_ecp_transport.dart` | Client HTTP de l'API ECP Roku. | — |
| `web_browser_transport.dart` | Délègue à `LocalCastServer` + QR code. | — |
| `local_cast_server.dart` | Mini HTTP server `dart:io` sur 0.0.0.0:<random>. Sert la page HTML5 + les relays DLNA pass-through. | 554 |
| `stream_probe.dart` | Pré-vol HTTP `GET Range:0-0` avec follow-redirects manuel. Détermine MIME, redirects, TTFB, auth. | 276 |
| `dlna_profiles.dart` | Catalogue des profils DLNA + heuristique `select(url, mime, isLive)`. | 283 |
| `dlna_capabilities.dart` | `GetProtocolInfo` du récepteur, cache par device id. | ~150 |
| `ssdp_discovery.dart` | M-SEARCH UDP 239.255.255.250:1900, parse descripteur XML. | 294 |
| `mdns_discovery.dart` | mDNS lookup `_googlecast._tcp.local`. | 121 |
| `google_cast_api.dart` | MethodChannel Dart côté app. | 147 |
| `cast_progress.dart` | Enum + factory de messages français pour l'UI. | 161 |
| `cast_diagnostics.dart` | Batch runner pour la matrice de compat (presets Rapide/Standard/Complet). | 239 |
| `cast_session_diagnostic.dart` | Modèle de télémétrie d'UNE session. Ring buffer keys. | 260 |

### 2.2 Couche UI

| Fichier | Rôle |
|---|---|
| `cast_picker_sheet.dart` | Bottom sheet de sélection device (~760 LoC). |
| `cast_button.dart` | Icône AppBar (état idle / actif). |
| `cast_mini_bar.dart` | Mini-barre persistante "Cast vers TV X". |
| `cast_diagnostics_screen.dart` | Écran dédié au testing matrice. |
| `qr_cast_sheet.dart` | Bottom sheet QR code (fallback web). |
| `web_cast_setup_sheet.dart` | Onboarding du mode web. |

### 2.3 Native Kotlin (`android_overlay/google_cast/`)

| Fichier | Rôle |
|---|---|
| `MainActivity.kt` | `FlutterFragmentActivity`. Wire 4 channels (cast, gallery, recording, pip) — chacun dans son try/catch (cf. `MainActivity.kt:71-142`). |
| `GoogleCastApi.kt` | Bridge `com.manzilionellm.tvking/cast`. 8 méthodes : `isCastAvailable`, `hasActiveSession`, `showRoutePicker`, `loadMedia`, `play`, `pause`, `stop`, `disconnect`. |
| `CastOptionsProviderImpl.kt` | Config statique du SDK Cast. Receiver App ID `46F815A5` (cf. `CastOptionsProviderImpl.kt:69`). |

---

## 3. Modèle de domaine

### 3.1 `CastDevice` (`lib/features/cast/domain/cast_device.dart`)

```dart
@immutable class CastDevice {
  final String id;
  final String name;
  final CastDeviceKind kind;   // dlna | roku | chromecast | googleCast | webBrowser
  final String host;
  final int port;
  final String controlUrl;
  final String? manufacturer;
  final String? model;
}
```

### 3.2 `CastState` (`cast_manager.dart:31-38`)

```dart
enum CastState { idle, discovering, connecting, casting, paused, error }
```

État **global** à l'app entière (singleton). Pas de support
multi-session simultanée — un seul cast actif à la fois.

### 3.3 `CastProgress` (`cast_progress.dart:18-54`)

Stage **fin** indépendant de `CastState`, exposé en `ChangeNotifier`
séparé pour les messages UI :

```
idle → validatingStream → detectingReceiver → startingRelay
    → connectingToReceiver → retryingWithFallback
    → switchingToWebFallback → streaming → paused → failed
```

### 3.4 Séparation `_device` vs `_selectedDevice` (`cast_manager.dart:78`)

Deux champs distincts dans le singleton, **conceptuellement
différents** :

- **`_device`** : récepteur sur lequel un cast est ACTUELLEMENT
  en cours (transport actif).
- **`_selectedDevice`** : récepteur "épinglé" par l'utilisateur
  via le picker global, sans flux à envoyer pour l'instant.
  Quand l'utilisateur zappe une chaîne ensuite, `playChannel()`
  route le flux vers `_selectedDevice` au lieu d'ouvrir le
  player local.

Modèle Netflix/YouTube : "connecte ta TV une fois, ensuite tout
y va". `disconnect()` clear les **deux**.

---

## 4. Cycle de vie d'une session — flux normal

### 4.1 Discovery (`cast_manager.dart:108-197`)

```
[ouverture picker]
   │
   ▼
startDiscovery(timeout=5s, keepExisting=true)
   │
   ├─► SsdpDiscovery.discover()  ─┐ (M-SEARCH UDP, parse descripteur XML)
   ├─► MdnsDiscovery.discover()  ─┤
   │                              │ onDevice(d) → dedup id||host+port
   │                              └─► _discovered.add(d) + notifyListeners
   │
   └─► Timer(timeout) → _state = idle/casting + notifyListeners
```

Un **warmup** (`startWarmup`, ligne 177-192) lance un scan toutes
les 60 s en arrière-plan dès que l'app est ouverte, pour que le
picker s'ouvre déjà rempli.

### 4.2 Cast vers DLNA (chaîne de failover 5 niveaux, `cast_manager.dart:341-505`)

```
castTo(device, streamUrl, title)
   │
   ▼
(1) StreamProbe.probe(url)        ── GET Range:0-0 + follow redirects
   │   ├─ success ────────────────┐
   │   └─ failure ──► throw       │
   │                              ▼
(2) DlnaCapabilities.fetchSink()  ── SOAP GetProtocolInfo (cached)
   │
(3) profile = DlnaProfiles.select(url, finalMime, isLive)
   │     │
   │     └─ LG-special : remap video/mp2t → video/vnd.dlna.mpeg-tts
   │        si la Sink LG annonce ce MIME (cast_manager.dart:381-392)
   │
(4) Loop s = 0..4 :
   │     s=0 : direct + metadata FULL  (PN DLNA complet)
   │     s=1 : direct + metadata MIN   (juste MIME)
   │     s=2 : direct + metadata NONE  (CurrentURIMetaData vide)
   │     s=3 : relay  + metadata FULL
   │     s=4 : relay  + metadata MIN
   │     │
   │     ▼
   │   transport.playStream(url, title)
   │     ├─ Stop best-effort
   │     ├─ SetAVTransportURI(uri, didl)
   │     ├─ _waitOutOfTransition(2s)
   │     ├─ Play
   │     └─ _waitForPlaying(4s) → PLAYING | PAUSED_PLAYBACK | RECORDING
   │
   │   ─► succès : break, return
   │   ─► failure : log AttemptResult, retry s+1
   │
(5) _archiveDiagnostic(diag) dans le ring buffer 20 slots
```

**Note empirique** (commentaire `cast_manager.dart:416-422`) :
sur la TV LG QNED816QA de l'utilisateur, le relay timeout
systématiquement (la TV n'arrive pas à joindre le serveur local
— probable VLAN/firewall). Du coup le code essaie TOUJOURS les 3
stratégies directes d'abord, MÊME si `probe.shouldUseRelay`
renvoie `true`.

### 4.3 Cast vers Google Cast SDK (`google_cast_transport.dart:36-94`)

```
playStream(url, title)
   │
   ▼
api.isCastAvailable()
   │
   ├─ false ──► throw "Google Cast indisponible"
   │
   ▼
api.hasActiveSession()
   │
   ├─ true ──┐
   │         │
   ├─ false ─► api.showRoutePicker()
   │            │
   │            ▼ (ouvre MediaRouteChooserDialog NATIF)
   │            │
   │            ▼ polling 500ms × 60 (max 30s)
   │            │
   │            ├─ session OK ─┐
   │            └─ timeout ──► throw "Aucune TV sélectionnée"
   │                           │
   ▼                           ▼
api.loadMedia(url, title, mime=_guessMime(url))
   │
   └─ false ──► throw "La TV a refusé le flux"
```

### 4.4 Disconnect (`cast_manager.dart:589-606`)

```
disconnect()
   │
   ├─ transport?.stop() (best-effort, try/catch)
   ├─ LocalCastServer.clearRelay(currentRelayUrl)
   ├─ _transport = _device = _selectedDevice = null
   ├─ _state = CastState.idle
   └─ _setProgress(CastProgress.idle)
```

---

## 5. Pile native Android (Google Cast SDK)

### 5.1 Init du `CastContext` (`GoogleCastApi.kt:62-72`)

```kotlin
private val castContext: CastContext? = try {
    if (isGmsAvailable(activity)) {
        CastContext.getSharedInstance(activity)
    } else null
} catch (e: Exception) { null }
```

→ Tolérant aux téléphones sans Google Play Services (Huawei
récents, ROMs sans GMS). Quand `castContext == null`, toutes les
méthodes Dart retournent `false` et le CastManager retombe
gracieusement sur DLNA / QR code.

### 5.2 Dialog natif — fix theme translucide (`GoogleCastApi.kt:141-173`)

`MediaRouteChooserDialog` refuse de s'afficher sur un Context
translucide (Flutter MainActivity hérite d'un thème translucide
par défaut pour permettre les transitions splash). Crash observé :

> `IllegalStateException: background can not be translucent: #0`

**Fix appliqué** (lignes 161-164) :

```kotlin
val themedContext = ContextThemeWrapper(
    fragmentActivity,
    androidx.appcompat.R.style.Theme_AppCompat_Light_Dialog_Alert,
)
val dialog = MediaRouteChooserDialog(themedContext)
```

**Vérification post-fix** : diagnostic utilisateur a montré que le
message d'erreur a basculé de "background translucent" vers
"Aucune TV sélectionnée" (= comportement attendu si user n'a pas
tapé sur sa TV dans le dialog).

### 5.3 Wiring des channels (`MainActivity.kt:59-143`)

Quatre channels distincts, chacun wired dans son propre `try/catch`
(commentaire `MainActivity.kt:65-69` explique pourquoi) :

```
com.manzilionellm.tvking/cast               → GoogleCastApi.kt
com.manzilionellm.tvking/gallery            → GalleryExporter.kt
com.manzilionellm.tvking/recording_service  → RecordingServiceBridge.kt
com.manzilionellm.tvking/pip                → inline dans MainActivity
```

### 5.4 Receiver Cast custom

App ID `46F815A5` configuré dans `CastOptionsProviderImpl.kt:69`.
Status Console au 2026-05-31 : **Published** (Styled Media
Receiver, Unlisted). Skin servi par le Worker Cloudflare à
`https://99999.7themotion.com/cast-skin.css`. Page receiver à
`/cast-receiver`.

---

## 6. Failure modes — recensement

Pour chaque mode d'échec : description, **code de référence**,
classification de gravité (P0 critique / P1 majeur / P2 mineur).
Le détail des choix de gravité est dans `phase-0-audit-cast-recording.md`.

### 6.1 Le Cast SDK ne s'initialise pas

**Cause** : pas de Google Play Services (Huawei, ROM custom).
**Code** : `GoogleCastApi.kt:62-72`. `castContext` reste `null`.
**Comportement** : `isCastAvailable()` retourne `false`. UI doit
proposer DLNA / QR à la place.
**Gravité** : **P2** — gracieusement géré.

### 6.2 MediaRouteChooserDialog crash sur Context translucide

**Cause** : thème Flutter par défaut.
**Code** : `GoogleCastApi.kt:141-173`.
**Statut** : **FIXÉ** (vérifié empiriquement).
**Gravité** : (était P0, désormais résolu).

### 6.3 L'utilisateur n'a pas tapé sur sa TV dans le dialog Cast

**Cause** : polling `hasActiveSession()` timeout après 30s.
**Code** : `google_cast_transport.dart:67-78`.
**Comportement** : throw `"Aucune TV sélectionnée."`. UI affiche
le message tel quel.
**Gravité** : **P2** — UX correcte mais le message est laconique.

### 6.4 DLNA — TV refuse toutes les stratégies

**Cause** : codec non supporté, format mal annoncé, TV strictement
non-compatible.
**Code** : `cast_manager.dart:428-504`.
**Comportement** : `throw lastError ?? Exception('Cast DLNA échec
inconnu')`. UI montre `_friendlyMessageFor(e)` (cast_manager.dart:547-562).
**Gravité** : **P1** — l'utilisateur n'a aucune action de
remédiation actionable à part essayer le QR code.

### 6.5 DLNA — TV en TRANSITIONING infini

**Cause** : TV occupée par un autre cast, ou bug firmware.
**Code** : `upnp_av_transport.dart:260-270` (`_waitOutOfTransition`,
max 2s).
**Mitigation existante** : Stop best-effort AVANT `SetAVTransportURI`
(`upnp_av_transport.dart:135-142`).
**Gravité** : **P2**.

### 6.6 DLNA — TV répond `STOPPED` juste après Play

**Cause typique** : codec non supporté (la TV rejette silencieusement).
**Code** : `upnp_av_transport.dart:291-295`. On lève
explicitement pour déclencher le failover suivant.
**Gravité** : **P2** — bien géré par le failover.

### 6.7 DLNA — TV répond 500 sur `SetAVTransportURI`

**Cause** : MIME non reconnu, DLNA.ORG_PN absent ou incorrect,
state pas STOPPED.
**Code** : `upnp_av_transport.dart:329-346` (`_soapCall`). Lève
avec faultString parsé.
**Mitigation existante** : 5 stratégies (full → minimal → none
→ relay+full → relay+min) couvrent la grande majorité.
**Gravité** : **P2**.

### 6.8 Relay HTTP — TV n'arrive pas à joindre le serveur local

**Cause** : VLAN, firewall, AP isolation activée sur le routeur.
**Code** : `local_cast_server.dart`, déclenchement dans
`cast_manager.dart:454-470`.
**Comportement** : `_ensureRelayUrl` retourne une URL mais la TV
fait un timeout sur le SOAP `SetAVTransportURI` (15s, cf.
`upnp_av_transport.dart:97`). Stratégies 3 et 4 échouent toutes
les deux.
**Code** : commentaire `cast_manager.dart:416-422` documente
le cas (LG QNED816QA observé). **[HYPOTHÈSE]** : le pattern est
représentatif d'une fraction non négligeable des LANs grand
public (Freebox/Livebox avec multi-VLAN par défaut).
**Gravité** : **P1**. Le message UX final
("Cette TV n'a pas accepté ce flux. Essaie une autre chaîne ou
le mode QR code.") est correct mais ne dirige pas vers le bon
levier (changer la config WiFi de l'invité).

### 6.9 Probe — token Xtream expiré

**Cause** : abonnement IPTV expiré ou révoqué.
**Code** : `stream_probe.dart:184-197`. Détecté en 401/403.
**Comportement** : message "Authentification requise — token
expiré ?". `cast_manager.dart:552-554` mappe vers "Accès au flux
refusé — ton abonnement a peut-être expiré."
**Gravité** : **P2**.

### 6.10 Probe — serveur très lent ou redirects en cascade

**Cause** : TTFB > 3000ms OU `redirectCount > 0` OU MIME
ambigu (`octet-stream`).
**Code** : `stream_probe.dart:104-112` (`shouldUseRelay`).
**Comportement** : la stratégie hint vers relay, mais le code
essaie quand même direct d'abord (cf. 6.8).
**Gravité** : **P2**.

### 6.11 Diagnostics non persistés

**Cause** : ring buffer 20 slots en RAM seulement
(`cast_manager.dart:66-70`).
**Comportement** : au kill de l'app, tout l'historique est perdu.
Impossible pour un user de partager un rapport stable d'une session
ancienne.
**Gravité** : **P1**. Pour le diagnostic à distance c'est un
trou critique.

### 6.12 Ring buffer pas thread-safe **[HYPOTHÈSE]**

**Cause** : `_recentDiagnostics.insert(0, d)` en concurrence avec
`recentDiagnostics` getter qui copie la liste.
**Code** : `cast_manager.dart:67-70` et `326-331`.
**[HYPOTHÈSE]** : Dart étant mono-thread sur l'isolate principal,
l'`insert` + `removeLast` est atomique du point de vue de
l'isolate. Donc en pratique pas de race. À confirmer si jamais
on déplace l'archive dans un Future asynchrone qui yield.
**Gravité** : **P2** (théorique).

### 6.13 `_currentRelayUrl` partagé entre stratégies — risque de cross-talk

**Cause** : `_ensureRelayUrl` (`cast_manager.dart:524-543`)
mémoïse l'URL relay pour TOUTE la session courante de `castTo`.
**Comportement** : si la stratégie 3 (relay+full) échoue avec
l'URL `R`, la stratégie 4 (relay+min) réutilise la MÊME URL `R`.
C'est l'intention (évite de re-register).
**Risque** : si la session 1 reste avec un relay enregistré et
la session 2 démarre AVANT le `disconnect()`, le relay de la
session 1 est jamais clear (cf. `disconnect()` `cast_manager.dart:595-598`).
**[HYPOTHÈSE]** : en pratique l'utilisateur enchaîne `castTo` →
`castTo` sans `disconnect()` ; le 1er relay reste donc en
mémoire jusqu'à la prochaine `disconnect()` ou jusqu'à eviction
LRU (`_kMaxRelays = 8`, cf. `local_cast_server.dart:59`).
**Gravité** : **P2** (fuite mémoire bornée à 8 entrées).

### 6.14 Pas de timeout global sur `castTo`

**Cause** : `castTo` peut durer arbitrairement long
(5 stratégies × ~15s SOAP timeout = théoriquement 75s + probe + caps).
**Code** : `cast_manager.dart:216-324`.
**Comportement** : pas de garde-fou global. L'utilisateur peut
attendre 60-90s avant de voir l'échec final.
**Gravité** : **P1** — UX significativement dégradée.

### 6.15 mDNS lookup pour Google Cast peut ne rien retourner

**Cause** : firewall mDNS, AP qui bloque IGMP, multi-VLAN.
**Code** : `mdns_discovery.dart:39-97`.
**Comportement** : `discoveredDevices` ne contient pas le
Chromecast. Mais le **SDK natif** Google Cast a sa propre
discovery qui peut quand même trouver le Chromecast via le
dialog `MediaRouteChooserDialog` → c'est l'utilisateur qui le
voit là, pas dans notre picker custom.
**Code** : commentaire `google_cast_transport.dart:15-21`
documente cette dualité.
**Gravité** : **P2**.

### 6.16 Pas de récupération de session en cas de kill OS

**Cause** : `CastManager` est in-memory, `_recentDiagnostics`
aussi. Aucune sérialisation.
**Comportement** : au reboot de l'app, on perd l'info qu'on
était en cast. Le SDK Cast natif a son `setResumeSavedSession`
(`CastOptionsProviderImpl.kt:74`) — mais notre `CastManager`
Dart ne s'y synchronise pas.
**[HYPOTHÈSE]** : à l'app launch, on n'appelle pas
`hasActiveSession()` pour détecter une session natif déjà en
cours (à confirmer en lisant `main.dart` + lifecycle).
**Gravité** : **P1**.

---

## 7. Diagnostics & observabilité

### 7.1 Ce qui existe

- **`CastSessionDiagnostic`** (`cast_session_diagnostic.dart`) :
  modèle riche capturant probe, sink, profile, attempts, total
  duration, success, error. Sérialisable JSON.
- **Ring buffer** : 20 dernières sessions en RAM
  (`cast_manager.dart:67-70`).
- **`CastDiagnosticsScreen`** : UI dédiée listant ces 20.
- **`DiagnosticBatchRunner`** (`cast_diagnostics.dart`) : runner
  multi-chaînes pour matrice compat. Export JSON copiable.
- **Redact URLs** : `redactStreamUrl` (`cast_session_diagnostic.dart:238-260`)
  masque `password`/`token`/`pwd` dans les query params et les
  segments USER/PASS des URLs Xtream `/live/USER/PASS/ID.ts`.
  **Bonne pratique** — pas de fuite credentials dans un rapport
  partagé GitHub.

### 7.2 Ce qui n'existe pas

- **Pas de persistance** sur disque (le ring buffer meurt au kill
  de l'app).
- **Pas de structured logging** : tout passe par `debugPrint('[Cast] ...')`
  texte brut, grep-able mais pas parseable machine.
- **Pas d'horodatage cohérent** sur chaque message debug (juste
  l'horodatage du log Flutter).
- **Pas de canal d'upload** vers un endpoint diagnostic distant
  (Cloudflare Worker dédié, Sentry, etc.).

**Mitigation Phase 0** : ajout du fichier
`lib/core/observability/structured_logger.dart` qui fournit
l'utilitaire `StructuredLogger.instance.{info,warn,error}` avec
sortie JSON-Lines. Aucun call site n'est instrumenté en Phase 0 —
c'est laissé à Phase 1 (décision utilisateur).

---

## 8. Sécurité — observations

### 8.1 Bonnes pratiques en place

- `redactStreamUrl` masque les credentials avant export JSON.
- `LocalCastServer` génère un **token aléatoire** par relay
  (`_randomToken`, `local_cast_server.dart:195-203`) — pas
  d'URL devinable.
- User-Agent custom (`VLC/3.0.20 LibVLC/3.0.20`) pour contourner
  les filtres anti-bot Xtream — pas de masquage de l'origine
  utilisateur, juste un mimétisme légitime.

### 8.2 Risques observés

- **Relay HTTP en clair sur le LAN** : le flux qui traverse la
  relay n'est pas chiffré. Si l'attaquant est sur le même WiFi,
  il peut snooper. **[HYPOTHÈSE]** : impact faible car (a)
  l'attaquant aurait aussi accès au flux upstream directement,
  (b) le scope est limité au LAN domestique. Pas un P0.
- **Token relay réutilisable** : pas de TTL strict (juste eviction
  LRU à 8 entries). Un attaquant qui sniffe un token l'aurait
  valide tant que le LRU ne l'évicte pas.
- **CDN mpegts.js/hls.js externes** sans SRI (`local_cast_server.dart:381-382`)
  : la page HTML5 fetch jsdelivr.net sans Subresource Integrity.
  Si jsdelivr est compromis, le code arbitraire s'exécute dans
  le navigateur de la TV (impact : pas d'accès au tel, mais
  injection de pub possible).
- **CORS `*` sur `/current`** (`local_cast_server.dart:358`) :
  acceptable car le serveur ne sert que sur le LAN, mais en
  toute rigueur on pourrait restreindre à l'IP de la TV.

---

## 9. Métriques observées

Aucune métrique automatique n'est collectée. Les diagnostics
existent mais ne sont **pas agrégés** :

| Métrique | Disponible ? | Source |
|---|---|---|
| Latence cast totale (ms) | Oui par session | `CastSessionDiagnostic.totalDurationMs` |
| Latence par stratégie | Oui | `AttemptResult.durationMs` |
| Taux de succès par device | **Non** | calculable manuellement depuis le batch runner |
| Stratégie gagnante distribution | Oui (par batch) | `winningStrategyCounts` |
| Probe TTFB | Oui | `ProbeSummary.timeToFirstByteMs` |
| Crash native (Kotlin) | **Non** | pas de Crashlytics / Sentry intégré |

---

## 10. Récapitulatif

- Pile **complexe** mais cohérente : 4 transports, 1 chaîne de
  failover principale (DLNA), 1 receiver custom Google Cast,
  1 fallback universel QR.
- Le code est **abondamment commenté** (commentaires français,
  retours d'expérience empiriques annotés inline). C'est une
  force majeure pour l'audit.
- **Diagnostics riches** capturés par session mais **volatiles** —
  perte d'historique au kill app.
- **Failure modes** majoritairement bien gérés au niveau code,
  mais **manque un timeout global** sur `castTo` et un canal
  d'observabilité persistant.

Pour la classification P0/P1/P2 et les recommandations d'action,
voir `phase-0-audit-cast-recording.md`.
