# DeFew TV — Samsung (Tizen) & LG (webOS)

App **web** native pour téléviseurs **Samsung (Tizen)** et **LG (webOS)**. C'est
la sœur des apps Android (`lib/main_tv.dart`) : **même backend**
(`app.7themotion.com`), **même panel** (activation par MAC, source poussée,
statut). Seule la techno change — ici HTML/JS, car ces TV **ne sont pas
Android** et **ne lisent pas l'APK**.

> ⚠️ Le lecteur vidéo Android (ExoPlayer/Media3) n'existe pas sur ces
> plateformes. On utilise la **vidéo native** de chaque TV : **AVPlay** sur
> Samsung, **`<video>` HTML5** sur LG. Le lecteur Android n'est donc PAS touché.

## Structure

```
tv-tizen-webos/
├── shared/                 # LE code (un seul, partagé)
│   ├── index.html
│   ├── css/app.css
│   └── js/
│       ├── config.js       # backend + branding
│       ├── platform.js     # détection tizen/webos + touches télécommande
│       ├── device.js       # MAC stable « MK:… » (dérivée du matériel)
│       ├── api.js          # heartbeat / status / device-source
│       ├── xtream.js       # chargement chaînes Xtream
│       ├── m3u.js          # chargement/parsing M3U
│       ├── nav.js          # navigation D-pad spatiale
│       ├── player.js       # AVPlay (Samsung) / HTML5 (LG)
│       └── app.js          # écrans : boot → activation → direct → lecteur
├── platform/
│   ├── tizen/config.xml    # manifeste Samsung (→ .wgt)
│   └── webos/appinfo.json  # manifeste LG (→ .ipk)
├── build.sh                # assemble build/tizen et build/webos
└── README.md
```

## Tester vite (sur PC)

```bash
cd tv-tizen-webos/shared
python3 -m http.server 8080
# ouvrir http://localhost:8080  (flèches = navigation, Entrée = OK, Échap = retour)
```
En navigateur, le lecteur HTML5 sert de prévisualisation. La MAC est alors
générée aléatoirement (pas de matériel TV) et mémorisée en localStorage.

## Construire les paquets

```bash
cd tv-tizen-webos
./build.sh        # crée build/tizen et build/webos
```

### Samsung (Tizen) → `.wgt`
1. Installer **Tizen Studio** + le **TV Extension**.
2. Créer un **certificat** :
   - *Samsung* (auteur + distributeur) via le **Certificate Manager**.
   - Pour lire la MAC (privilège `network.public`, niveau **partenaire**), il
     faut un **compte partenaire Samsung** et un certificat *Partner*. Sans lui,
     l'app fonctionne mais retombe sur une MAC dérivée/aléatoire stockée.
3. Packager + signer :
   ```bash
   tizen package -t wgt -s <NOM_DU_PROFIL> -- build/tizen
   ```
4. Tester sur TV en **Developer Mode** (Apps → entrer l'IP du PC) :
   ```bash
   tizen install -n DeFewTV.wgt -t <TV_TARGET>
   ```
5. Soumettre sur **Samsung Apps TV — Seller Office**
   (`https://seller.samsungapps.com`).

### LG (webOS) → `.ipk`
1. Installer le **webOS TV CLI** (`@webos-tools/cli`) : `npm i -g @webos-tools/cli`.
2. Mettre la TV en **Developer Mode** (app *Developer Mode* du store LG).
3. Packager :
   ```bash
   ares-package build/webos
   ```
4. Installer + lancer sur la TV :
   ```bash
   ares-install ./com.7themotion.defewtv_1.0.0_all.ipk
   ares-launch com.7themotion.defewtv
   ```
5. Soumettre sur **LG Seller Lounge** (`http://seller.lgappstv.com`).

## Icônes à fournir
- Samsung : `platform/tizen/icon.png` (512×512 conseillé).
- LG : `platform/webos/icon.png` (80×80) **et** `largeIcon.png` (130×130).
  *(à exporter depuis le logo The Few, fond transparent.)*

## Remarques importantes
- **Politique store IPTV** : Samsung et LG examinent les apps ; une app IPTV
  « brute » peut être refusée. Prévoir une description sobre (lecteur de listes
  fournies par l'utilisateur), des CGU, et idéalement un compte de test.
- **Flux** : `config.js > streamExt` vaut `m3u8` (HLS) par défaut. Si l'image ne
  démarre pas sur certains serveurs, basculer en `ts` (MPEG-TS).
- **CORS** : Tizen (`access origin="*"`) et webOS (permissions réseau)
  autorisent les requêtes cross-origin vers les serveurs IPTV — pas de blocage
  CORS comme dans un navigateur classique.
- Aucune URL IPTV en dur (règle AGENTS.md) : tout vient du panel par MAC.
