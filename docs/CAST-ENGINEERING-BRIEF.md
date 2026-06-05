# Cast — Brief d'ingénierie (lecture pour un dev senior)

> Mission ciblée. Périmètre verrouillé. À traiter chirurgicalement.
> Basé sur les patterns réels des apps IPTV qui castent bien
> (IPTV Smarters Pro, TiviMate, XCIPTV) et sur l'architecture déjà
> présente dans ce dépôt.

---

## 0. Mission (une seule)

**Faire que l'app caste un flux IPTV (live `.ts` / HLS) vers un Chromecast / Google TV de façon fiable.**

Critère d'acceptation : sur un téléphone **avec Google Play Services**, même Wi‑Fi qu'une Chromecast, l'utilisateur tape l'icône cast → choisit la TV → **l'image s'affiche sur la TV en < 10 s**, play/pause/stop OK. Plus un repli **DLNA** pour les TV non‑Chromecast.

## 1. Périmètre — NE TOUCHER QUE ÇA

Autorisé :
- Natif : `android_overlay/google_cast/{GoogleCastApi.kt, CastOptionsProviderImpl.kt, MulticastLockBridge.kt, MainActivity.kt}`
- Dart : `lib/features/cast/**` (notamment `cast_manager.dart`, `google_cast_api.dart`, `google_cast_transport.dart`, `cast_transport.dart`, `local_cast_server.dart`, `stream_probe.dart`, `dlna_*.dart`, `presentation/cast_*.dart`)

Interdit : abonnement, activation, panel, i18n, enregistrement, thème, lecteur principal. Tout le reste est en prod et validé.

## 2. La vérité technique du cast IPTV (ce que font Smarters Pro & co.)

Le **Default/Styled Media Receiver** de Chromecast NE lit PAS arbitrairement un flux IPTV. Il accepte un **set restreint** : HLS (`.m3u8`), MP4/fMP4, WebM, H.264/AAC. Il **échoue** sur :
- **MPEG‑TS brut** (`video/mp2t`) — or 90 % du live IPTV est du `.ts` brut ;
- codecs hors‑liste (HEVC partiel, audio **AC3/EAC3/MP2**) ;
- flux derrière **auth/headers/UA** spécifiques, redirections, **HTTP cleartext** selon le receiver.

➡️ **Conséquence :** les apps qui castent bien **ne castent JAMAIS l'URL du provider directement**. Elles font tourner un **relais HTTP local sur le téléphone** qui :
1. récupère le flux provider (bons UA/headers),
2. **remuxe à la volée** TS → **fMP4 / HLS** (ou passe‑through si déjà HLS/MP4),
3. l'expose sur `http://<IP-LAN-du-tel>:<port>/...` (PAS `127.0.0.1`),
4. sert le **bon Content‑Type** (`application/vnd.apple.mpegurl` pour HLS, `video/mp4` pour fMP4) et marque le flux `STREAM_TYPE_LIVE`.

C'est cette URL **locale remuxée** qu'on envoie au Chromecast — pas l'URL IPTV d'origine.

Le **Google Cast SDK exige GMS**. Sans GMS → pas de Chromecast (c'est par design). Pour ces appareils, **DLNA/UPnP** est le repli (déjà câblé ici).

## 3. Carte du code existant (déjà en place)

| Rôle | Fichier |
|---|---|
| Orchestrateur (discovery, sélection, failover, timeout 25 s) | `lib/features/cast/data/cast_manager.dart` |
| Pont SDK Google Cast (sessions, `loadMedia`, play/pause) | `lib/features/cast/data/google_cast_api.dart` ↔ natif `GoogleCastApi.kt` |
| Transport Cast SDK | `google_cast_transport.dart` |
| **Relais HTTP local** (le point névralgique) | `lib/features/cast/data/local_cast_server.dart` |
| Probe codec/container du flux | `stream_probe.dart` |
| Repli DLNA/UPnP + profils/capabilities | `dlna_*.dart`, `upnp_av_transport.dart`, `roku_ecp_transport.dart` |
| Découverte mDNS/SSDP + lock multicast | `mdns_discovery.dart`, `ssdp_discovery.dart`, `MulticastLockBridge.kt` |
| Config receiver (App ID) | `CastOptionsProviderImpl.kt` — actuellement Default Receiver `CC1AD845` |
| Écran de diag (À UTILISER) | `lib/features/cast/presentation/cast_diagnostics_screen.dart` |

## 4. Diagnostic chirurgical (dans cet ordre)

1. **GMS présent ?** `GoogleCastApi.isCastAvailable()` → si `false`, tester sur un autre appareil. Ne pas debugger le SDK sur un tél sans GMS.
2. **Découverte** : la TV apparaît‑elle dans le picker ? Sinon → réseau (même Wi‑Fi, AP‑isolation OFF, `MulticastLock` bien acquis pendant la découverte). Vérifier via `cast_diagnostics_screen`.
3. **Quelle URL est réellement envoyée au receiver ?** Tracer l'argument `streamUrl` passé à `GoogleCastApi.loadMedia` (Dart) et à `RemoteMediaClient.load` (Kotlin).
   - ❌ Si c'est l'URL **provider en `.ts`** → c'est la cause. La TV ne sait pas la lire.
   - ✅ Il faut envoyer l'**URL du relais local** (`local_cast_server`) en **HLS/fMP4**, IP **LAN**.
4. **Le relais remuxe‑t‑il ou passe‑t‑il en TS brut ?** Lire `local_cast_server.dart` : s'il sert du `video/mp2t` tel quel, le Default Receiver échoue → il faut **remux TS→HLS/fMP4** (ex. via `MediaCodec`/`MediaMuxer` côté natif, ou segmentation HLS à la volée), ou un **receiver custom** avec Shaka Player.
5. **Content‑Type & STREAM_TYPE** côté `loadMedia` (Kotlin `MediaInfo.Builder`) : mime cohérent avec ce que sert le relais, `STREAM_TYPE_LIVE` pour le live.
6. **IP du relais** : doit être l'IP Wi‑Fi du téléphone (jointe par la TV), jamais `localhost`/`127.0.0.1`.

## 5. Cause la plus probable + correctif

**Hypothèse n°1 (à confirmer en 10 min via §4.3/§4.4) :** on envoie au Chromecast une URL **MPEG‑TS brute** (provider ou relais pass‑through) que le Default Media Receiver ne décode pas → écran noir / erreur côté TV.

**Correctif chirurgical :**
- Brancher le chemin Chromecast sur le **relais local en sortie HLS/fMP4** (remux), pas en TS.
- Aligner `Content-Type` + `STREAM_TYPE_LIVE`.
- Si remux trop lourd : option **receiver custom** (publier `46F815A5`, charger un receiver Shaka qui avale plus de formats) — mais le relais HLS reste le standard de l'industrie.

**Hypothèse n°2 :** GMS/réseau (cf. §4.1‑4.2) — fréquent en test, pas un bug code.

## 6. Protocole de test

- Tél **avec GMS** + Chromecast/Google TV même Wi‑Fi (AP‑isolation OFF).
- Tester un flux **HLS** d'abord (doit marcher quasi direct) puis un **`.ts`** live (révèle le besoin de remux).
- Push sur `claude/github-commit-access-YDUAv` → `build-android.yml` publie l'APK sur la release `latest`.
- Valider play/pause/stop + repli DLNA sur une TV non‑Chromecast.

## 7. À ne pas oublier

- `STREAM_TYPE_LIVE` pour le live (pas de seek), `STREAM_TYPE_BUFFERED` pour la VOD.
- Garder le `MulticastLock` actif **uniquement pendant** la découverte (batterie).
- Le timeout de 25 s dans `cast_manager.dart` doit laisser le relais démarrer avant l'envoi.
- Ne pas régresser le repli **DLNA** (TV sans Chromecast).
