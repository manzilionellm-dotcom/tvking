# Les 5 applications officielles — carte du projet

> Décision du propriétaire, 2026-08-08 : **il n'existe que CES 5 applications.**
> Tout le reste a été supprimé des releases (voir « Ce qui a été effacé »).
> Si tu es un ingénieur ou une IA qui reprend ce projet : c'est ICI que tu pars.

## Les 5 applications

| # | App | Plateforme | Release (tag) | Lien direct permanent |
|---|---|---|---|---|
| 1 | **7 MOTION** | Téléphone Android | `prod` | `https://github.com/manzilionellm-dotcom/tvking/releases/download/prod/7motion.apk` |
| 2 | **7 MOTION iPhone** | iOS | — (App Store/TestFlight, pas de release GitHub) | workflows `build-ios.yml` / `build-ios-release.yml` |
| 3 | **7 MOTION TV** | Box Android TV / Fire TV / sticks | `seventv-latest` | `https://github.com/manzilionellm-dotcom/tvking/releases/download/seventv-latest/seven-tv.apk` |
| 4 | **The Few — Samsung TV** | Samsung Tizen 6.0+ | `tizen-latest` | `https://github.com/manzilionellm-dotcom/tvking/releases/download/tizen-latest/thefew-tizen.tpk` |
| 5 | **The Few — Windows** | PC Windows | `windows-latest` | `https://github.com/manzilionellm-dotcom/tvking/releases/download/windows-latest/7MOTION-Setup.exe` |

Toutes partagent le **même code Flutter, le même backend et le même panel**
(branche de référence : `claude/7motion-android-tv-compat-e0rtyp`).

## État des magasins (mis à jour 2026-08-14)

| Magasin | App | Statut |
|---|---|---|
| **Google Play** | Lecteur IPTV – 7 MOTION (téléphone) | Prod 1349 en ligne ; **ENVOI n°10 EN EXAMEN depuis le 14 août** (release 1402 + fiche complète + identifiants GPLAYREVIEW) — délai annoncé ≤ 7 j. ⚠️ Publication gérée ACTIVE : après approbation, il reste UN clic « Publier » manuel |
| **Amazon Appstore** | 7 MOTION TV (Fire TV) | **REFUS n°2 le 15/08** (« Content Policy », détails VIDES dans la console, Primary Validation PASS — l'e-mail cite « ad network libraries » mais les 2 scans binaires indépendants prouvent ZÉRO SDK pub). **Support case 21632144391 ouvert le 15/08** demandant la cause exacte ; APK conforme `seven-tv-amazon.apk` prêt (vc 1786782656, sans updater/REQUEST_INSTALL_PACKAGES). ⚠️ NE PAS resoumettre avant la réponse écrite — hypothèse principale : le réviseur humain a réagi au CONTENU vu via les accès démo (chaînes premium) → chantier « bouquet de démo propre » à décider |
| **Microsoft Store** | 7 MOTION (Windows) | **SOUMISE le 14 août** — « In review », SLA 3 j ouvrés (compte Individual gratuit, éditeur « 7 MOTION ») |
| **Google Play TV** | 7 MOTION TV (Android TV/Google TV) | Nouvelle fiche en cours — release TEST FERMÉ (règle 12 testeurs) avec AAB vc 1786723319 (sans updater, PLAY_BUILD) |
| **LG Content Store** | The Few (webOS) | Compte Seller configuré (7 Few, LLC), app créée (App ID com.sevenmotion.thefew validé, ID LG 1318975), visuels prêts aux dimensions officielles. Upload .ipk bloqué le 14/08 par une PANNE du scan antivirus LG (prouvée : fichier témoin 8 octets rejeté pareil) — retry automatique toutes les 30 min |
| **Samsung TV** | The Few (Tizen) | **SOUMISE le 14 août** — Pre-Test Pass (label « The Few », ID com.sevenmotion.thefew), 44/44 groupes de modèles, « Submitted — 100% Rollout (scheduled) ». Vérification Samsung en cours (~1-2 sem.) |
| **Apple App Store** | 7 MOTION (iPhone) | Playbook prêt, CI signé dormant — attend le compte Developer (99 $/an) |

Notes Amazon : catégorie « Movies & TV » (taxonomie sans « Video Players ») ;
Amazon re-signe les APK à la livraison (comportement standard) ; assets
provisoires à rebrander un jour : icône Fire TV 1280×720 + fond 1920×1080.

## Signatures

- **Android (téléphone + TV)** : clé maîtresse release (« The Few », RSA 2048,
  SHA384withRSA, valide → 2053), schémas v1/v2/v3. Empreinte SHA-256 du
  certificat : `51:45:B8:E0:19:F6:D5:FB:96:A2:07:F2:E7:36:73:FD:95:4F:79:99:66:FD:59:88:89:21:15:56:CB:DF:9E:61`.
  Secrets CI : `ANDROID_KEYSTORE_PASSWORD` (+ `ci/release.jks.enc`).
- **Samsung Tizen** : certificat AUTEUR Samsung du propriétaire
  (secrets `SAMSUNG_AUTHOR_P12_BASE64` / `SAMSUNG_AUTHOR_PASSWORD`) +
  distributeur Tizen par défaut. Sideload OK ; pour le store Samsung il faut
  en plus un certificat distributeur (compte Samsung Seller).
- **Windows** : installateur non signé Authenticode (un certificat de
  signature de code Windows s'achète — à faire avant une distribution large,
  sinon SmartScreen affiche un avertissement contournable).
- **iOS** : signature Apple via le pipeline iOS (certificats Apple Developer).

## Publier une nouvelle version (par app)

| App | Workflow | Publication |
|---|---|---|
| Téléphone | `build-android.yml` | release `prod` (canal officiel clients) |
| TV box | `build-seventv.yml` (dispatch, `publish=true`) | release `seventv-latest` + `version.json` (MAJ auto in-app, anti-harcèlement) |
| Samsung | `build-tizen.yml` (dispatch ou push code TV) | release `tizen-latest` |
| Windows | `build-windows.yml` (dispatch) | release `windows-latest` |
| iPhone | `build-ios-release.yml` | App Store / TestFlight |

Branche à utiliser pour les dispatchs : `claude/7motion-android-tv-compat-e0rtyp`
(l'état le plus récent de l'app), sauf indication contraire dans STATUS.md.

⚠️ Règles gravées : Flutter épinglé 3.32.x et Impeller OFF sur les builds TV
(anti écran noir des box) — ne pas y toucher sans revalider sur box réelle.

## Ce qui a été effacé (2026-08-08, sur instruction du propriétaire)

Releases supprimées pour ne garder que les 5 apps (et libérer le stockage
GitHub) : `phone-test`, `cinema-test`, `master-console`, `tv-prod`,
`tv-latest`, `tv-fix-latest`, `cast-fix-tv-latest`.

Conséquences assumées :
- Les box de l'ancienne lignée **DeFew TV** (~38 installations) ne reçoivent
  plus de mises à jour : leurs apps continuent de fonctionner, figées. Pour
  les faire migrer : installer 7 MOTION TV via le lien officiel (l'ancienne
  app peut ensuite être désinstallée).
- La **console maître** n'a plus d'APK en ligne : elle se reconstruit à la
  demande (`build-android.yml` avec `master_console=true` puis
  `publish-master.yml`).
- Les APK de test se republient à la demande (`publish-phone-test.yml`,
  `publish-cinema-test.yml`) — à effacer après usage.

## Outils internes (pas des apps clientes)

- Panel admin (`admin-panel/`, workflow `deploy-admin-panel`).
- Worker Cloudflare (`cloudflare/`, workflow `deploy-worker`) — liens courts
  /app /dl /7tv /seventv, API, updater.
- Console maître (APK privé, reconstruite à la demande, voir ci-dessus).
