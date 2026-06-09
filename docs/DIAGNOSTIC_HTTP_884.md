# Diagnostic — « HTTP 884 » au chargement des sources M3U / Xtream

> Statut : **diagnostic + instrumentation livrés**. Le correctif réseau
> définitif (pile TLS native) est **documenté et prêt à brancher**, mais
> volontairement **non embarqué tel quel** dans ce build de production —
> voir la section « Pourquoi pas tout de suite » plus bas.

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

## 6. Pourquoi pas tout de suite (décision d'ingénierie)

`cronet_http` (1.8.0) repose sur **`package:jni`** et exige **compileSdk 35**.
Surtout, il existe un **crash JNI documenté en build `--release`/`--profile`
avec obfuscation** (dart-lang/http #1241) — or **c'est exactement le mode de
build de cette app** (`flutter build apk --release --obfuscate`).

Embarquer cette dépendance **sans pouvoir la tester sur device** dans cette
session ferait courir le risque de transformer un bug **« aucune chaîne
importée »** en **« l'app crashe au lancement »** pour **tous** les
utilisateurs en production — un échange défavorable, et contraire au principe
« on teste avant de livrer ».

**Donc, dans cette branche :**
- ✅ diagnostic écrit + raisonnement sur le discriminant ;
- ✅ **instrumentation** de la requête exacte (pour enfin la capturer) ;
- ✅ garde-fou de **budget temps global** (plus de N×90s empilés) ;
- ✅ architecture **déjà prête** (client HTTP injectable) + ce mode d'emploi ;
- ⏭️ **à brancher avec un device de test** : `cronet_http` embarqué
  (Option A) ou pont OkHttp (Option B), puis valider qu'un APK release
  obfusqué **ne crashe pas** AVANT distribution.

---

## 7. Ce que change concrètement ce commit

- `m3u_fetcher.dart` : log `net/m3u.request` + `net/m3u.response` (requête
  exacte + statut), et **budget temps global** (`_totalBudget = 150 s`) pour
  ne pas cumuler les tentatives lentes.
- `xtream_client.dart` : log `net/xtream.request` + `net/xtream.response`
  (mot de passe non journalisé).
- Aucune dépendance ajoutée, aucun changement de pile réseau → **build
  inchangé et sûr**.
