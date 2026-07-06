# CAST — Dossier de passation ingénieur

> **But de ce fichier :** tout ce qu'il faut pour reprendre le casting là où il
> en est et le terminer, sans rien lire d'autre. Lis-le en entier une fois,
> puis attaque la section 6 (la solution à finir).
>
> Branche : `claude/iptv-chromecast-cast-WeAyo` · Dépôt : `manzilionellm-dotcom/tvking`
> Dernier commit de contexte : `ba1343b` · Rédigé : 2026-07-06

---

## 1. Contexte en 30 secondes

App **Flutter** (lecteur IPTV, moteur média = `media_kit`/libmpv). On veut caster
un flux **MPEG-TS brut** (`http://…/live/USER/PASS/ID.ts`, codec souvent HEVC/AC3)
vers **Chromecast / Google TV / NVIDIA SHIELD**.

Problème de fond du TS brut : le **Default Media Receiver de Google ne décode pas
le MPEG-TS brut**. On a donc un **receiver CAF custom** (App ID `5BDFD969`, page
servie par notre Worker Cloudflare) qui embarque **mpegts.js** pour transmuxer le
TS → fMP4 sur la TV.

---

## 2. État actuel — ce qui MARCHE / ce qui CASSE

### ✅ Ce qui marche (validé sur SHIELD, 2026-07-06)
- Le sender Flutter ouvre une session Cast native (bridge Kotlin maison sur le
  Google Cast SDK, `play-services-cast-framework` 21.5.0). Pas de plugin fragile.
- La page **receiver custom se charge et tourne** : `context.start()` OK,
  mpegts.js instancié, overlay debug visible.
- La **reconnexion automatique du live** que j'ai ajoutée fonctionne (backoff
  1→5 s, 6 tentatives) — visible dans l'overlay : `reconnect #1 dans 1000ms`…

### ❌ Ce qui casse (le dernier problème, section 3)
- L'overlay affiche **`first fetch status=502 ct=text/plain`** en boucle.
  → mpegts.js n'obtient jamais le flux → écran noir → reconnexions → abandon.

> Historique utile : avant mes correctifs, la page receiver était
> **syntaxiquement morte** (un `join('\n')` dans un template literal cassait le
> script → `context.start()` jamais appelé). C'est corrigé (commit `6f80197`).
> Le `502` est donc le **problème suivant**, pas l'ancien.

---

## 3. LE DERNIER PROBLÈME (à résoudre)

### Le flux réel
```
Sender (téléphone)                     Worker Cloudflare              TV (receiver custom)
  probe l'URL Xtream  ──────────────▶  /cast-sign (HMAC)   ─────────▶  reçoit URL /cast-proxy
  http://portail/…/ID.ts                                               mpegts.js fetch(/cast-proxy)
        │ redirect 302                                                        │
        ▼                                                                     ▼
  http://185.245.1.97/live/…?token     /cast-proxy fetch upstream  ◀── mpegts attend le TS
                                              │
                                              ▼  ⚠️ 502 ICI
                                        le fournisseur IPTV répond une ERREUR au Worker
```

### La preuve
- L'overlay du receiver : `first fetch status=502 ct=text/plain`.
- Ce `502 text/plain` est **notre propre** `castProxyError('upstream error', 502)`
  dans `cloudflare/worker.js` → fonction `handleCastProxy`.
- Donc : **le Worker a bien contacté le fournisseur, mais le fournisseur a
  renvoyé une erreur** (ou a coupé la connexion).

### La cause (hypothèse forte, à confirmer par le diagnostic §4)
Le **téléphone** lit le flux sans problème, mais le **Worker Cloudflare échoue**.
La seule vraie différence entre les deux : **l'IP source**.
- Téléphone = **IP résidentielle** (autorisée par le panel IPTV).
- Worker = **IP de datacenter Cloudflare** → les panels Xtream la **bloquent**
  presque toujours (anti-rediffusion), OU limitent à **1 connexion simultanée**,
  OU géo-bloquent selon le PoP Cloudflare.

**Conséquence directe et importante :** si c'est un blocage d'IP datacenter,
**aucun correctif dans le Worker ne peut le contourner** — c'est la politique du
fournisseur. Le proxy cloud (« téléphone éteint, la TV continue ») **n'est pas
viable avec ce fournisseur**. Il faut relayer depuis une **IP résidentielle**
(le téléphone, ou un VPS résidentiel). Voir §6.

---

## 4. DIAGNOSTIC — confirmer la cause en une capture

J'ai instrumenté le proxy et l'overlay (commit `ba1343b`, **déjà déployé**).
Refaire un cast et lire la nouvelle ligne overlay :

```
first fetch status=502 upstream=XXX body=…
```

| `upstream=` | Signification | Action |
|---|---|---|
| **403 / 456 / 512** | Le fournisseur REFUSE l'IP du proxy (datacenter) ou limite les connexions | → §6 : relais résidentiel. Le proxy cloud est mort pour ce fournisseur. |
| **404** | Token de redirection périmé quand la TV le demande | Le build signe déjà l'URL d'origine (le Worker re-résout un token frais). Si ça persiste : le portail bloque quand même. |
| **`unreachable …`** | Le fournisseur DROP la connexion depuis l'IP du proxy | → §6 : idem 403, blocage réseau. |

Code du diagnostic à relire : `cloudflare/worker.js` → `handleCastProxy`
(distingue `fetch` qui jette vs réponse 4xx/5xx, remonte `X-Upstream-Status`) ;
`cloudflare/cast_receiver.js` → le `fetch` de debug lit le corps non-2xx.

---

## 5. CARTE DES FICHIERS

**Sender Flutter**
- `lib/features/cast/data/cast_manager.dart` — orchestration, découverte, failover DLNA, watchdog reconnexion, diagnostics.
- `lib/features/cast/data/google_cast_transport.dart` — **décision de routage** (cast_proxy / relais HLS téléphone / direct). ⬅️ le cœur du sujet.
- `lib/features/cast/data/google_cast_api.dart` — API Dart du bridge.
- `lib/features/cast/data/local_cast_server.dart` — **serveur HTTP embarqué du téléphone** (relais + wrap HLS). ⬅️ la brique clé de la §6.
- `lib/features/cast/data/stream_probe.dart` — pré-vol upstream (redirects, MIME, isLive).

**Natif Android**
- `android_overlay/google_cast/GoogleCastApi.kt` — CastContext/SessionManager/RemoteMediaClient + `MediaInfo`/`load`.
- `android_overlay/google_cast/CastOptionsProviderImpl.kt` — **App ID receiver** + flag `USE_CUSTOM_RECEIVER`.

**Serveur Cloudflare**
- `cloudflare/cast_receiver.js` — page CAF + mpegts.js (LOAD interceptor, MEDIA_STATUS, reconnexion, overlay).
- `cloudflare/worker.js` — routes `/cast-sign`, `/cast-proxy` (`handleCastProxy`), `/cast-receiver`, `/vendor/mpegts.js`.

> ⚠️ **Invariant à ne jamais casser :** `kCastUseCustomReceiver` (Dart, dans
> `google_cast_transport.dart`) et `USE_CUSTOM_RECEIVER` (Kotlin, dans
> `CastOptionsProviderImpl.kt`) **doivent toujours valoir la même chose**. Les
> désynchroniser = écran noir garanti.

---

## 6. LA SOLUTION À FINIR (échafaudage prêt à coller)

**Stratégie recommandée : essayer le proxy cloud, VÉRIFIER qu'il délivre
vraiment, sinon basculer sur le relais résidentiel depuis le téléphone.**

Le téléphone a déjà un serveur HTTP local (`LocalCastServer`) capable de tirer le
flux (IP résidentielle, connexion qui marche déjà pour la lecture locale) et de le
re-servir en HLS. **Contrainte majeure à gérer :** la page receiver custom est en
**HTTPS**, or `mpegts.js` utilise `fetch()` → un relais **HTTP** du téléphone est
**bloqué (mixed content)**. Deux issues possibles, à trancher par l'ingénieur :

- **Voie A (recommandée, la plus simple) :** quand le proxy est bloqué, **basculer
  la session sur le Default Media Receiver** (pas la page custom HTTPS) et lui
  envoyer l'URL **HLS du relais téléphone**. Le Default Receiver lit le HLS
  nativement (pas de `fetch`, donc pas de blocage mixed-content sur le média), et
  le wrap HLS du `LocalCastServer` transforme déjà le `.ts` en playlist HLS. Coût :
  le téléphone doit rester allumé et sur le même Wi-Fi. **C'est le compromis
  standard des apps IPTV (BubbleUPnP, etc.).**
- **Voie B (si "téléphone éteint" est impératif) :** héberger la logique
  `/cast-proxy` sur un **VPS à IP résidentielle** (offres "residential IP") au lieu
  de Cloudflare. Plus cher, ops en plus, mais garde le custom receiver et le
  téléphone-éteint. Ne pas partir là-dessus sans valider le besoin.

### 6.1 — Étape 1 : détecter le blocage côté sender (code prêt)

À ajouter dans `google_cast_transport.dart`. Cette fonction fait un GET léger sur
l'URL proxy signée et lit juste le status : si non-2xx, le proxy est bloqué.

```dart
/// Vérifie que /cast-proxy DÉLIVRE réellement le flux (le Worker peut être
/// bloqué par le fournisseur IPTV — cf. docs/CAST_HANDOFF.md §3). On lit le
/// status puis on coupe : on NE télécharge PAS le flux. `true` = 2xx.
static Future<bool> _proxyDelivers(String proxyUrl) async {
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 6);
  try {
    final HttpClientRequest req = await client
        .getUrl(Uri.parse(proxyUrl))
        .timeout(const Duration(seconds: 6));
    req.headers.add(HttpHeaders.acceptHeader, '*/*');
    final HttpClientResponse resp =
        await req.close().timeout(const Duration(seconds: 8));
    final int status = resp.statusCode;
    // Optionnel : lire l'en-tête X-Upstream-Status pour le diagnostic.
    final String upstream =
        resp.headers.value('x-upstream-status') ?? '';
    StructuredLogger.instance.info(
      domain: 'cast',
      event: 'proxy.verify',
      ctx: <String, Object?>{'status': status, 'upstream': upstream},
    );
    return status >= 200 && status < 300;
  } on Exception {
    return false; // injoignable → on considère le proxy KO
  } finally {
    client.close(force: true); // coupe le GET sans vider le flux
  }
}
```

Puis, dans `playStream`, remplacer le commit direct au proxy par une vérification :

```dart
String? proxied =
    kCastUseCustomReceiver ? await _signedCastProxyUrl(upstream) : null;

// NOUVEAU : ne PAS faire confiance aveuglément au proxy — vérifier.
if (proxied != null && !await _proxyDelivers(proxied)) {
  StructuredLogger.instance.warn(
    domain: 'cast', event: 'proxy.blocked_fallback_relay',
    ctx: const <String, Object?>{},
  );
  proxied = null; // → bascule sur le relais téléphone (bloc `else` existant)
}

if (proxied != null) {
  urlToCast = proxied; mime = 'video/mp2t'; castPath = 'cast_proxy';
} else {
  // ⬇️ TODO ÉTAPE 2 : ici, aujourd'hui c'est le relais HLS téléphone MAIS
  //    il est envoyé au receiver CUSTOM (HTTPS) → mixed content si HTTP.
  //    Voir 6.2 : router ce cas vers le Default Media Receiver.
}
```

### 6.2 — Étape 2 : router le repli vers le Default Media Receiver (à écrire)

C'est le vrai travail restant. Aujourd'hui `USE_CUSTOM_RECEIVER` est un flag de
**compilation** — il faut le rendre **dynamique par session** :

```
TODO (ingénieur) :
[ ] Exposer une méthode native (GoogleCastApi.kt) qui (re)configure le
    receiver App ID de la session AVANT loadMedia :
        - custom 5BDFD969  → pour le chemin cast_proxy (TS décodé sur la TV)
        - Default CC1AD845 → pour le chemin relais HLS téléphone
    Note : le SDK charge l'App ID via OptionsProvider au démarrage ; changer de
    receiver en cours de session impose souvent de terminer puis rouvrir la
    session (endCurrentSession → showRoutePicker/reconnect). Valider le coût UX.
[ ] Côté sender : si proxy bloqué → wrap HLS via LocalCastServer.registerRelay
    (wrapInHls:true, déjà implémenté) → loadMedia(url HLS, mime application/x-mpegURL)
    sur le Default Receiver.
[ ] Vérifier sur Chromecast pur (pas seulement SHIELD) que le Default Receiver
    accepte une URL HLS HTTP du téléphone. Si Chrome bloque le média HTTP :
        - soit servir le relais en HTTPS (cert auto-signé accepté par la TV ? à tester),
        - soit conclure que seule la Voie B (VPS résidentiel) marche pour "phone off".
[ ] Garder le custom receiver comme chemin PRIORITAIRE (téléphone-éteint) quand le
    proxy délivre (2xx) — ne PAS régresser les fournisseurs qui autorisent le proxy.
```

### 6.3 — Détails déjà en place à réutiliser
- `LocalCastServer.registerRelay(upstreamUrl, profile, receiverHost, wrapInHls: true)`
  renvoie déjà une URL HLS `http://<ipLAN>:<port>/hls/<token>.m3u8`. **Le relais
  existe**, il n'est juste pas routé vers le bon receiver quand le proxy est bloqué.
- Le receiver custom sait déjà lire le HLS natif (branche CAF) ET le TS brut
  (mpegts.js) — cf. `isRawMpegTs` dans `cast_receiver.js`.
- Anti-SSRF + suivi de redirects du proxy : `isSafeUpstream` / `handleCastProxy`.

---

## 7. DÉPLOIEMENT & TEST

**Worker (receiver + proxy)** — auto-déployé par GitHub Actions au push de
`cloudflare/worker.js` ou `cloudflare/cast_receiver.js` :
```
.github/workflows/deploy-worker.yml   (secrets CLOUDFLARE_API_TOKEN / ACCOUNT_ID)
```
Vérif rapide en prod : ouvrir `https://app.7themotion.com/cast-receiver?debug=1`
dans un navigateur (la page doit se charger sans erreur console).

**APK** — auto-build + release signée (clé maîtresse `CN=The Few`,
`ci/release.jks.enc` + secret `ANDROID_KEYSTORE_PASSWORD`) :
```
.github/workflows/build-android.yml
Release : cast-fix-latest  →  https://github.com/manzilionellm-dotcom/tvking/releases/download/cast-fix-latest/7motion.apk
```

**Qualité (obligatoire avant push)** :
```
flutter analyze                 # doit rester 0 erreur
flutter test                    # doit rester vert (100+ tests)
node --check cloudflare/worker.js
node cloudflare/worker_security.smoke.mjs
# + vérifier que les <script> GÉNÉRÉS de cast_receiver.js parsent
#   (piège template-literal : doubler les backslash destinés à la page)
```

**Test terrain minimal** : caster UNE chaîne réellement en direct (⚠️ certaines
chaînes du panel redirigent vers `black.ts` de 1 octet = source morte, elles ne
casteront JAMAIS — tester sur une chaîne qui marche en lecture locale) ; lire
l'overlay ; téléphone éteint pour valider le chemin téléphone-autonome (si Voie B).

---

## 8. CHECKLIST DE FIN

```
[ ] Diagnostic §4 relevé : upstream=____  (403/404/456/unreachable)
[ ] Cause tranchée : blocage IP datacenter ?  oui / non
[ ] Étape 6.1 (détection proxy bloqué) intégrée + testée
[ ] Étape 6.2 (repli Default Receiver + relais HLS) implémentée
[ ] Testé sur Chromecast PUR + SHIELD + une Google TV
[ ] Chaîne live → image en < 25 s, pause/stop depuis le téléphone OK
[ ] Reconnexion : coupure > 5 min sans blocage définitif
[ ] flutter analyze 0 erreur, flutter test vert, smoke worker 6/6
[ ] kCastUseCustomReceiver ⇔ USE_CUSTOM_RECEIVER cohérents
[ ] docs/AUDIT-CAST-7MOTION-2026-07-05.md relu (limitations connues)
```

## 9. Points ouverts hérités (dans l'audit détaillé)
Voir `docs/` du dépôt `7themotion`, fichier `AUDIT-CAST-7MOTION-2026-07-05.md` :
overlay debug encore actif (`kCastDebugOverlay=true`, à couper en prod), SDK Cast
21.5.0 à migrer 22.3.x, token relais exposé via `/current` (CORS ouvert), HLS
`.m3u8` sans réécriture CORS, Roku pause/resume (toggle unique), `isAdvertised`
DLNA sans effet.
