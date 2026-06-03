# 📡 Diagnostic du Cast — comment lire les logs

## 🩺 Outil automatique : `cast_doctor.sh`
Le plus simple : un script qui **dit en clair** pourquoi le cast échoue
(lecture seule, ne modifie rien sur l'appareil).

```bash
# téléphone branché en USB (débogage activé) :
./android_overlay/google_cast/cast_doctor.sh
# ou en précisant l'applicationId :
./android_overlay/google_cast/cast_doctor.sh com.manzilionellm.tvking.tv_king
```
Il vérifie : appareil connecté + app installée → permissions réseau
(INTERNET / ACCESS_NETWORK_STATE / **CHANGE_WIFI_MULTICAST_STATE** /
ACCESS_WIFI_STATE) → meta-data OptionsProvider → capture ~15 s de logs
pendant que tu ouvres le picker → même sous-réseau (heuristique). Puis un
**VERDICT** symptôme → cause → action. Code de sortie 0 = vert.

## 🔬 Manuel (logcat brut)
Une session de cast émet une trace **corrélable** de bout en bout
(domaine `cast` côté Dart + tag `MulticastLock`/`MainActivity` côté natif).

## Commande
```bash
adb logcat | grep -E "MulticastLock|MainActivity|Cast|mDNS|ssdp"
```

## Lecture, étape par étape
1. **Câblage des channels** (au boot) — `MainActivity` :
   - `✓ Cast channel wired` / `✓ MulticastLock channel wired` → OK.
   - `✗ ... channel failed` → bridge natif KO (cast cassé). Vérifier le
     package détecté par `apply_cast_patch.sh`.
2. **MulticastLock** — au début d'un scan :
   - log natif `WifiLock/MulticastLock acquired` → OK.
   - Dart `cast multicast_lock.acquire_failed` ou
     `discovery.multicast_lock_failed {transport}` → **cause n°1 d'un
     picker vide** : permission `CHANGE_WIFI_MULTICAST_STATE` absente ou
     WiFi indisponible.
3. **Découverte** — Dart :
   - `cast discovery.start` puis `cast discovery.finish {devices, multicastLockOk}`.
   - `cast discovery.empty_lock_failed` → 0 appareil **et** lock KO →
     message UX actionnable affiché dans le picker.
4. **Session** — Dart : `cast.network_unreachable` (TV endormie / WiFi
   différent / isolation AP) si l'envoi échoue alors que la TV est listée.

## Receiver (cast trouvé mais l'envoi échoue)
- En **debug**, l'app utilise le **Default Media Receiver** (`CC1AD845`,
  toujours disponible) → le cast marche sans branding.
- En **release**, le receiver **custom** (`46F815A5`) est utilisé : il
  doit être **PUBLIÉ** sur la Google Cast SDK Developer Console, sinon la
  découverte marche mais la **session échoue** sur les TV non déclarées.
- Donc : si le cast marche en debug mais pas en release → publier le
  receiver custom (problème de Console, pas de réseau).
