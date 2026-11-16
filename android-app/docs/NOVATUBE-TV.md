# NovaTube TV — édition TV construite sur le code de l'app TV existante

## Pourquoi cette base, et pas l'APK « 4K Player » (334.2.6)

L'APK NovaTube TV 334.2.6 (`com.manthefew`) est le **4K Player de KKStore**
(`com.kkstore.fourkplayer`) repaqueté : son moteur et son interface ne sont pas
notre code. Retirer son activation d'origine et le vendre sous le nom NovaTube
exigerait l'autorisation écrite de son éditeur. Le propriétaire a donc choisi
(16/11/2026) de construire NovaTube TV sur **notre propre application TV**
(lecteur natif Media3, M3U/Xtream, activation par code `MK:`, boîte noire).

Conséquence assumée : **le moteur vidéo n'est plus celui de 4K Player**.
L'équivalence d'image avec 4K Player n'est PAS établie ; elle se vérifie sur
une NVIDIA SHIELD, même flux, mêmes réglages.

## Ce que fait l'édition (et rien d'autre)

Compilation : `--target=lib/main_tv.dart --dart-define=NOVATUBE_TV=true`
(constante `kNovatubeTv`, `lib/core/app/novatube_tv_edition.dart`). Sans ce
define, le build Zuno est identique à avant (tests dans les deux modes).

| Domaine | Édition NovaTube TV |
|---|---|
| Identité | paquet `com.sevenmotion.novatube.tv`, nom « NovaTube », logo sans cadre |
| Thème | vert pétrole / noir / turquoise, définitif (`TvNovatube`) |
| Premier écran | « Bienvenue sur NovaTube » : Ajouter une liste M3U · Se connecter avec Xtream Codes · code `MK:XX:XX:XX:XX:XX` · état de la licence |
| Listes | enregistrables licence en attente ; plusieurs listes (écran « Mes listes ») ; conservées après expiration |
| TV en direct | 3 colonnes existantes : catégories · chaînes (logos, recherche) · aperçu vidéo + guide |
| Synchronisation | 5 s / 15 s / filet 60 s, reprise jusqu'à 2 min (jamais chaque seconde) |
| Retiré pour NovaTube | thème « tv » du panel, WhatsApp Zuno, publicité de démarrage, cartes du panel, mise à jour vers la release `zuno-tv` |
| Moteur vidéo | **inchangé** par rapport à Zuno TV : aucun fichier de `packages/`, `android/`, `lib/features/player` modifié |

## Construire et tester

```sh
# Images de marque (déjà dans le dépôt, à régénérer seulement si besoin)
python3 ci/novatube_tv/make_brand_assets.py
# Sur un checkout de CI ou une copie jetable :
python3 ci/novatube_tv/prepare_build.py        # logo déclaré, nom, bannière, lancement
flutter test test/novatube_tv                   # mode Zuno
flutter test --dart-define=NOVATUBE_TV=true test/novatube_tv
```

La CI complète est `.github/workflows/novatube-tv-test.yml` (push sur la
branche NovaTube TV) : tests, APK signé, vérification (paquet, nom, Leanback,
certificat, SHA-256), émulateur Android 11 en 1080p **hors réseau** avec
captures, import M3U HTTP local + lecture d'une mire générée, puis pré-version
`novatube-tv-test-<commit>`. Aucune release publique n'est modifiée.

## Signature et code `MK`

Le code `MK:` est dérivé de l'`ANDROID_ID` de l'application, qui dépend de la
**clé de signature** (Android 8+). Avec la clé de test jetable de la CI, chaque
APK de test a une autre clé : il faut désinstaller avant d'installer, et la
box affiche un **nouveau code MK**. Pour un code stable et des mises à jour
par-dessus, créer une clé dédiée et la mettre dans les secrets du dépôt :

```sh
keytool -genkeypair -keystore novatube-tv.jks -storetype PKCS12 \
  -alias novatube-tv -keyalg RSA -keysize 3072 -validity 10000
base64 -w0 novatube-tv.jks   # → secret NOVATUBE_TV_KEYSTORE_BASE64
```

Secrets : `NOVATUBE_TV_KEYSTORE_BASE64`, `NOVATUBE_TV_KEYSTORE_PASSWORD`,
`NOVATUBE_TV_KEY_ALIAS` (`novatube-tv`), `NOVATUBE_TV_KEY_PASSWORD`. Garder une
copie hors ligne du `.jks` : sa perte empêche toute mise à jour future.

**Aucun APK de cette édition ne peut mettre à jour NovaTube 334.2.6**
(`com.manthefew`) : c'est une autre application, installée à côté.

## Installation sur NVIDIA SHIELD (Android 11)

1. Paramètres → Préférences de l'appareil → Sécurité et restrictions →
   Sources inconnues : autoriser l'application qui installera l'APK
   (par exemple « Downloader » ou un gestionnaire de fichiers).
2. Ouvrir le lien direct de la pré-version de test dans cette application,
   télécharger l'APK, puis « Installer ».
3. Si une version de test précédente signée avec une autre clé est présente :
   Paramètres → Applications → NovaTube → Désinstaller, puis réinstaller.
4. Ouvrir NovaTube depuis l'écran d'accueil (bannière NovaTube).
5. « Ajouter une liste M3U » ou « Se connecter avec Xtream Codes ».
6. Donner le code `MK:…` affiché au revendeur pour l'activation.

## Limites connues (à traiter avant une vente)

- **Activation séparée dans Atlas** : la box s'annonce comme appareil « tv »
  (espace Zuno) par `/api/heartbeat`. Elle apparaît et s'active dans le panel
  comme une box Zuno, avec la politique d'essai Zuno. Une application Atlas
  NovaTube TV distincte (essai serveur de 10 jours, 9,99 €) demande une
  évolution additive du Worker (le code `app_novatube4k` des PR #250-#254 vise
  `com.manthefew`) et un déploiement autorisé.
- **Paiement** : aucun paiement réel n'est activé.
- **Qualité d'image** : identique à Zuno TV (mêmes binaires vidéo), non
  comparée à 4K Player ; HDR / Dolby Vision / passthrough à vérifier sur SHIELD.
- **Films et séries depuis une liste M3U** : dépendent du travail « Cinéma M3U »
  (PR #255), non fusionné dans cette base.
