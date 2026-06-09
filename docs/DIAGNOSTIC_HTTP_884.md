# Diagnostic — « HTTP 884 » au chargement des sources M3U / Xtream

> Statut : **CORRECTIF LIVRÉ**. La requête passe désormais par un **pont
> réseau natif Android** (`HttpURLConnection` = pile TLS SYSTÈME, la même
> que le navigateur et IBO Player), avec **repli automatique sur `dart:io`**.
> Diagnostic, instrumentation et garde-fous restent en place (ci-dessous).

---

## 1. Le symptôme

En ajoutant une playlist M3U du type :

```
http://<host>/get.php?username=XXX&password=YYY&type=m3u_plus&output=ts
```

le serveur répond **« HTTP 884 »** — un code **non standard**, fabriqué par
le serveur/CDN (le RFC HTTP s'arrête à 5xx). L'app affiche une erreur et
n'importe **aucune** chaîne.

**Fait déterminant** : la **même URL**, sur la **même TV**, le **même
Wi-Fi** (donc la **même IP publique**), **fonctionne** :

- dans un **navigateur** (Chrome / WebView) ;
- dans **IBO Player** (et d'autres lecteurs IPTV).

Seule **notre app** échoue. Le blocage ne vient donc PAS de : l'URL,
l'abonnement, l'IP, ni le pays.

---

## 2. Ce qui a déjà été tenté (et pourquoi ça n'a pas suffi)

| Tentative | Résultat | Enseignement |
|---|---|---|
| Rotation de **9 User-Agents** de lecteurs (VLC, ExoPlayer/IBO, OkHttp, Smarters, TiviMate, Kodi, Lavf, Chrome mobile, Chrome desktop) | **884 sur toutes** | Ce n'est **pas** un simple filtre User-Agent. |
| En-têtes **« façon navigateur »** (`Accept`, `Accept-Language`, `Connection: keep-alive`) | **884 persiste** | Ce n'est **pas** (uniquement) un filtre sur les en-têtes applicatifs. |
| Reproduction côté CI | **Impossible** | Le pare-feu de sortie du runner GitHub bloque l'hôte IPTV (hors liste blanche). Le 884 n'est donc **pas** reproductible en build. |

Conclusion : le discriminant est **plus bas** que l'User-Agent et que les
en-têtes HTTP applicatifs.

---

## 3. L'élément discriminant (raisonnement)

Posons la question correctement : **qu'est-ce qui diffère entre les clients
qui MARCHENT (navigateur, IBO) et le nôtre, à part l'User-Agent et les
en-têtes — qu'on a déjà alignés ?**

| Client | Pile réseau / TLS | Empreinte TLS (JA3/JA4) | Verdict serveur |
|---|---|---|---|
| Navigateur Chrome / WebView | **Pile système Android** (Chromium / BoringSSL système) | empreinte « navigateur », ultra-répandue | ✅ accepté |
| IBO Player (ExoPlayer + **OkHttp**) | **Pile système Android** (Conscrypt) | empreinte « OkHttp/Android », ultra-répandue | ✅ accepté |
| **Notre app (Flutter)** | **`dart:io HttpClient`** → **BoringSSL embarqué par Dart** | empreinte **`dart:io`**, rare/atypique | ❌ **884** |

Les deux clients qui passent partagent une chose que le nôtre **n'a pas** :
ils utilisent la **pile réseau du système Android**. Notre app, elle, parle
au serveur via **`dart:io HttpClient`**, qui embarque **sa propre copie de
BoringSSL** avec un **ClientHello TLS différent** (liste/ordre des cipher
suites, extensions, courbes, ALPN, GREASE…).

Un front **anti-bot / WAF** (fréquent chez les revendeurs IPTV : Stalker,
panels CDN maison…) calcule une **empreinte TLS** (JA3 / JA4) **dès la
poignée de main, AVANT** même de voir l'URL ou les en-têtes HTTP. Il
**whiteliste** les empreintes courantes (navigateurs, OkHttp, VLC…) et
**rejette** les empreintes inconnues avec un **code maison** — ici **884**.

> C'est cohérent avec **tous** les faits :
> - changer l'User-Agent ne change rien (le tri se fait **avant** l'HTTP) ;
> - ajouter des en-têtes ne change rien (idem) ;
> - le navigateur **et** IBO marchent (tous deux sur la **pile système**) ;
> - seule notre app `dart:io` échoue (empreinte TLS atypique).

**Le discriminant le plus probable est l'empreinte TLS (JA3/JA4) de la pile
`dart:io`, distincte de celle de la pile système Android.** Les pistes
secondaires (version HTTP, ordre exact des en-têtes, `Accept-Encoding`)
restent possibles mais **moins probables** : IBO/OkHttp passe en HTTP/1.1
comme nous, ce qui disqualualifie « HTTP/2 obligatoire » comme cause unique.

> ⚠️ **Honnêteté intellectuelle** : ce raisonnement est **fortement étayé**
> mais **pas encore prouvé par capture** (voir §4). Je n'ai pas accès au
> réseau de l'utilisateur ni à l'hôte IPTV (bloqué en CI), donc je n'ai pas
> pu intercepter la requête réelle. La capture reste l'étape qui transforme
> ce diagnostic en **preuve**.

---

## 4. Comment PROUVER (capture) — méthode exigée

Il faut comparer **la requête qui marche** et **la requête qui échoue**.

### 4.a — Capturer la requête qui MARCHE (IBO / navigateur)

Sur le **même réseau** que la TV :

1. Installer **HTTP Toolkit** (le plus simple) ou **mitmproxy** sur un PC,
   ou **Wireshark** pour le niveau TLS brut.
2. Router la TV (ou un téléphone qui reproduit) vers ce proxy.
3. Ouvrir l'URL `get.php?...` dans IBO / le navigateur.
4. Noter : **ligne de requête**, **TOUS les en-têtes** (+ leur **ordre**),
   **version HTTP**, **redirections**, et — pour Wireshark — le
   **ClientHello TLS** (cipher suites, extensions) → c'est le **JA3/JA4**.

### 4.b — Capturer la requête qui ÉCHOUE (notre app)

Cette branche **instrumente** déjà l'app pour ça. À chaque tentative, on
journalise la **requête exacte** envoyée et la **réponse** reçue :

```jsonc
// events émis par StructuredLogger (domain: "net")
{ "event": "m3u.request",  "ctx": { "url": "...", "uaIndex": 1, "ua": "...", "headers": { ... } } }
{ "event": "m3u.response", "ctx": { "status": 884, "bytes": 0, "contentType": "..." } }
{ "event": "xtream.request",  "ctx": { "host": "...", "action": "...", "ua": "...", "headers": { ... } } }
{ "event": "xtream.response", "ctx": { "host": "...", "status": 884 } }
```

- **Build debug** : ces lignes sortent directement dans `flutter logs` /
  Logcat.
- **Build release** (l'APK distribué) : le sink par défaut du logger est
  silencieux. Pour capturer sur la vraie TV, soit on branche un **sink**
  (`StructuredLogger.instance.addSink(...)`) vers un fichier / un endpoint,
  soit — plus parlant pour le 884 — on **route l'app vers HTTP Toolkit** et
  on lit la requête réelle au niveau réseau.

### 4.c — Diff

Mettre les deux requêtes côte à côte. L'élément qui **diffère** et qui n'est
**pas** l'User-Agent ni un en-tête applicatif (déjà alignés) sera, selon ce
diagnostic, le **ClientHello / JA3** — c.-à-d. la **pile TLS**.

---

## 5. Le correctif définitif (répliquer à l'identique)

Si la capture confirme le JA3, `dart:io` **ne permet pas** de changer son
empreinte TLS (le ClientHello est figé dans le BoringSSL embarqué). Il faut
donc **router la requête par la pile réseau du système Android**, exactement
comme le navigateur et IBO. Deux options, par ordre de recommandation :

### Option A — `cronet_http` (Cronet / Chromium) **[recommandée]**

`package:cronet_http` route les requêtes via **Cronet** (la pile réseau de
Chromium) → empreinte TLS **« navigateur »**, HTTP/2 + HTTP/3, suivi de
redirects natif. On l'expose comme un `http.Client` standard, donc il se
**branche directement** dans `M3uFetcher.fetch(httpClient: …)` et dans
`XtreamClient(httpClient: …)` — l'architecture est **déjà prête** (le client
HTTP est injectable partout).

```dart
// Esquisse (à valider sur device — voir §6)
final engine = CronetEngine.build(userAgent: PlayerSettings.instance.userAgent);
final http.Client client = CronetClient.fromCronetEngine(engine, closeEngine: true);
final body = await M3uFetcher.fetch(url, httpClient: client);
```

**Pré-requis Fire TV (PAS de Google Play Services)** : il faut la variante
**embarquée** de Cronet, sinon le moteur ne se charge pas sur Fire TV.
- `--dart-define=cronetHttpNoPlay=true` au `flutter build` ;
- côté Android, dépendre de `org.chromium.net:cronet-embedded`
  (≈ +8 Mo/ABI ; acceptable car l'APK est déjà `--split-per-abi`).

### Option B — **OkHttp** via `MethodChannel` (Kotlin)

Écrire un petit pont Kotlin qui fait le GET avec **OkHttp** (pile **Conscrypt
système** → empreinte **identique à IBO Player**). Avantage : pas de
`package:jni`, donc **pas** de risque d'obfuscation/JNI (cf. §6).
Inconvénient : code natif à maintenir + injection dans la `MainActivity`
générée par la CI (via `android_overlay/`).

> Les replis existants (rotation d'User-Agent, fallback UTF-8/Latin-1, strip
> BOM, suppression de la source orpheline) **restent en place** : le client
> natif devient juste la **1ʳᵉ tentative**, avec repli `dart:io` si le moteur
> natif est indisponible.

---

## 6. Le correctif RETENU : pont natif `HttpURLConnection` (Option C)

Plutôt que `cronet_http` (Option A) — qui repose sur **`package:jni`**, exige
**compileSdk 35**, et a un **crash JNI documenté en build `--release`
obfusqué** (dart-lang/http #1241), or c'est **exactement** notre mode de build
(`flutter build apk --release --obfuscate`) — on a retenu une voie **plus
sûre et sans dépendance** :

**Un pont `MethodChannel` natif qui fait le GET avec
`java.net.HttpURLConnection`.** Sur Android, `HttpURLConnection` s'appuie sur
la pile TLS **système (Conscrypt)** — **la même que le navigateur et IBO
Player**, ceux qui marchent. L'empreinte TLS redevient « normale » → le front
laisse passer.

Pourquoi c'est le bon choix ici :
- **Zéro dépendance** ajoutée (`HttpURLConnection` est dans le framework
  Android) → **zéro patch Gradle**, rien à télécharger au build.
- **Aucune réflexion / JNI** → **compatible avec l'obfuscation R8** du build
  release (contrairement à `cronet_http`).
- **Repli automatique sur `dart:io`** : si le pont est absent (iOS, vieil
  APK) ou échoue, on reprend l'ancien chemin → **aucune régression possible**.
- Fonctionne **avec ou sans Google Play Services** (Fire TV inclus), car
  Conscrypt est présent sur **tout** Android.

### Fichiers du correctif

| Fichier | Rôle |
|---|---|
| `android_overlay/google_cast/NativeHttpBridge.kt` | Pont natif : channel `com.manzilionellm.tvking/native_http`, méthode `get(url, headers)` → GET `HttpURLConnection` (suit les redirections cross-protocole http↔https), renvoie `{status, body, finalUrl, contentType}`. Tourne hors du thread UI. |
| `android_overlay/google_cast/MainActivity.kt` | Câble `NativeHttpBridge` dans `configureFlutterEngine` (try/catch isolé). |
| `android_overlay/google_cast/apply_cast_patch.sh` | Copie `NativeHttpBridge.kt` au bon package au build CI. |
| `lib/core/net/native_http.dart` | Façade Dart `NativeHttp.get(...)` → `NativeHttpResponse`. Détecte l'indisponibilité (MissingPluginException) et renvoie `null` (repli). |
| `lib/features/playlists/data/m3u_fetcher.dart` | Tente le pont natif EN PREMIER (toutes signatures), repli dart:io. |
| `lib/features/playlists/data/xtream_client.dart` | Idem pour `player_api.php` (reconstruit une `http.Response` standard). |

### Limite (honnêteté)

Si le front bloque **aussi** sur un critère post-TLS (rare : géo-IP, token,
ordre d'en-têtes spécifique), `HttpURLConnection` ne suffira pas et le pont
renverra le même code. Dans ce cas, la **capture** (§4) reste l'outil pour
isoler le critère restant. Mais pour le cas décrit (marche en navigateur +
IBO, échoue seulement chez nous), la pile TLS système est la cause la plus
probable et ce pont la corrige.

---

## 7. Ce que change concrètement ce travail

- **Correctif réseau** : pont natif `HttpURLConnection` (§6) tenté en premier
  pour le M3U **et** l'Xtream, repli `dart:io` automatique.
- **Instrumentation** : logs `net/m3u.request[.native]` + `.response[.native]`
  et `net/xtream.*` (requête exacte + statut, ex. 884 ; mot de passe non
  journalisé) — pour capturer/diffuser la requête.
- **Garde-fou** : budget temps global (`_totalBudget = 150 s`) côté M3U pour
  ne pas cumuler les tentatives lentes.
- Robustesse conservée : rotation d'User-Agent, UTF-8 → Latin-1, strip BOM,
  suppression de la source orpheline si elle ne charge pas.
