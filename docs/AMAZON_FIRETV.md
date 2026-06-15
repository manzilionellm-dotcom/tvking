# DeFew TV — Publier sur l'Amazon Appstore (Fire TV / Fire Stick)

Fire OS est basé sur Android → **l'APK DeFew TV fonctionne nativement** sur
Fire TV. Pas de réécriture (contrairement à Samsung/LG). Ce guide explique la
soumission officielle sur l'**Amazon Appstore**.

## ✅ Pourquoi l'app est déjà prête pour Fire TV
- **Pas de Google Play Services** : le build TV n'applique PAS le patch Cast
  (le Cast se fait par QR + mDNS, sans Play Services). Fire OS n'a pas Play
  Services → aucune dépendance qui casse.
- **APK UNIVERSEL** : le workflow publie un APK toutes-ABIs (arm64 **+
  armeabi-v7a 32 bits**) → s'installe sur **tous** les Fire Stick, y compris
  les Lite / Stick de base 32 bits.
- **Bannière Fire TV** : `android:banner` présent (la home Fire TV l'utilise).
- **Navigation télécommande** D-pad + `LEANBACK_LAUNCHER`.
- **Signature stable** : mises à jour par-dessus, sans désinstaller.
- **HTTP cleartext** autorisé (flux IPTV).

## 📦 Étapes de soumission

### 1. Compte développeur Amazon
- Crée un compte sur **developer.amazon.com** (gratuit).
- Va dans **Appstore → Apps & Services → Add New App → Android**.

### 2. Récupère l'APK universel
- Lien direct (toujours la dernière version) :
  `https://github.com/manzilionellm-dotcom/tvking/releases/download/tv-latest/defew-tv.apk`
- C'est l'APK **universel** publié par `build-tv.yml` (toutes ABIs).

### 3. Renseigne la fiche (store listing)
- **Catégorie** : Entertainment.
- **Description** : sobre — « lecteur IPTV : le client saisit/charge SA
  propre source (M3U / Xtream). L'app ne fournit aucun contenu. »
- **Support Fire TV** : coche **Amazon Fire TV** dans *Device Support*
  (l'app déclare `leanback` + bannière → Amazon la détecte comme app TV).
- **Type de contrôle** : *Gamepad/Remote* (D-pad).

### 4. Assets graphiques requis (Fire TV)
| Asset | Taille | Source |
|---|---|---|
| Icône | 512×512 PNG | `assets/branding/thefew_tv_icon.png` |
| Bannière / Background | 1280×720 PNG | dérivable de `thefew_tv_banner_2x.png` |
| Captures d'écran | ≥ 3, 1280×720 ou 1920×1080 | à faire sur la box (écran Direct, lecteur, Pour vous) |

### 5. Content rating & confidentialité
- Remplis le **questionnaire de classification** (l'app ne contient pas de
  contenu adulte par défaut ; le **Mode Enfants** filtre l'adulte → argument
  « famille »).
- Fournis une **politique de confidentialité** (URL) — l'app envoie seulement
  un identifiant d'appareil (MAC virtuelle) + le modèle, pour l'activation.

### 6. Test & soumission
- Amazon teste l'APK via son **App Testing Service** (compatibilité Fire TV).
- Soumets → revue Amazon (souvent quelques jours).

## ⚠️ Points d'attention IPTV
- Comme tous les stores, Amazon examine les apps IPTV. Argumente que l'app est
  un **lecteur générique** (sources fournies par l'utilisateur), pas un
  fournisseur de contenu. Joins les CGU.
- Garde une **version sideload** (Downloader) en parallèle pour les clients,
  au cas où la revue traîne.

## 🔁 En attendant la revue : sideload (déjà opérationnel)
Le client installe en 30 s sans store :
- **Downloader** (sur le Fire Stick) → code **`6248618`**
- ou lien : `app.7themotion.com/tv`

L'APK universel garantit que ça marche sur **tous** les modèles de Fire Stick.
