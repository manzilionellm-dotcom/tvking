# 🍏 Playbook iOS / App Store — 7 MOTION (lecteur IPTV)

> But : publier l'app **sur l'App Store sans se faire bannir**, et garder le
> build iOS prêt-à-soumettre. Tout le technique est déjà câblé (Info.plist,
> CI signé dormant). Il ne manque que **ton compte Apple Developer (99 $/an)**
> et les secrets associés.
>
> Modèle stratégique : **lecteur « BYO playlist »** — l'app ne fournit AUCUN
> contenu ; l'utilisateur entre SON propre abonnement (Xtream / M3U). C'est
> exactement la recette qui passe la review Apple (même catégorie que VLC).

---

## 0. État technique (déjà fait dans ce repo)

| Élément | Fichier | État |
|---|---|---|
| Check de compilation iOS | `.github/workflows/build-ios.yml` | ✅ tourne (sans signature) |
| Config Info.plist complète (ATS, audio fond, cast) | `ci/ios/patch_info_plist.sh` | ✅ partagée par les 2 workflows |
| Build **signé** → TestFlight | `.github/workflows/build-ios-release.yml` | ✅ **dormant** jusqu'aux secrets Apple |
| Modèle d'export App Store | `ci/ios/ExportOptions.plist` | ✅ référence |
| Architecture | `ios/` généré à la volée (jamais commité, comme `android/`) | ✅ |

**Édition iOS = LECTEUR propre uniquement** (`lib/main.dart`). La version
« Privé » 18+ (`main_prive.dart`) n'est **jamais** construite pour iOS.

---

## 1. 🚫 Ne PAS se faire bannir — règles Apple pour un lecteur IPTV

Les apps IPTV se font dégager surtout sur **5.2.3** (propriété intellectuelle).
Cas réel : l'app *RealmIPTV* a été retirée en **janvier 2026** sous 5.2.3. Le
schéma est clair : celles qui **fournissent / découvrent / lient** des flux se
font virer ; les **lecteurs BYO purs** survivent.

### Ce que l'app DOIT faire (et fait déjà / à garder)
- **Écran de départ VIDE** : au 1ᵉʳ lancement → « Ajouter une playlist / login
  Xtream / importer un M3U ». Aucun contenu visible tant que l'utilisateur n'a
  rien ajouté.
- Se présenter comme un **lecteur multimédia générique** (comme VLC).
- Lecture, EPG **des données de l'utilisateur**, favoris, enregistrement **du
  flux de l'utilisateur**.

### Ce que l'app NE DOIT PAS faire (chaque point = motif de rejet documenté)
- ❌ **Aucune chaîne / playlist préchargée** dans le binaire (même pas en
  « démo »).
- ❌ **Aucune découverte de flux** / recherche « free IPTV » / catalogue intégré
  / scraping.
- ❌ **Aucun lien ou texte** indiquant où acheter/trouver un abonnement ou des
  listes M3U (= « facilitation » sous 5.2.3).
- ❌ **Aucun contenu adulte** (règle **1.1.4** : porno = ban dur, aucun palier
  de note ne l'autorise sur iOS). → la version « Privé » est **exclue d'iOS**.
- ❌ **Pas de second app jumeau** quasi identique (règle **4.3** spam).
- ❌ Ne pas nommer l'app/les mots-clés d'après un service ou une marque
  protégée (5.2.1 copycat).
- ❌ Pas de déblocage de fonctions via « code d'activation » : tout achat
  in-app qui débloque l'app doit passer par **Apple IAP** (3.1.1). *(L'abonnement
  IPTV de l'utilisateur, lui, est un service externe → OK, tant qu'on ne le VEND
  pas dans l'app.)*

### Texte de la fiche App Store (à coller, wording éprouvé)
> **7 MOTION ne fournit aucun contenu, chaîne ou playlist.** C'est un lecteur
> multimédia conçu pour être utilisé avec **vos propres** contenus / playlists
> dont vous détenez les droits d'accès. Compatible M3U et Xtream Codes.

### Notes pour la review Apple (à coller dans « App Review Information »)
> This app is a generic media player. It contains **no channels, playlists, or
> content of its own**; the end user supplies their own legal M3U URL or Xtream
> Codes login.
>
> To test all features, on first launch tap **"Add Playlist" → "M3U URL"** and
> paste this **free, ad-supported, license-free** sample playlist (free-to-air /
> FAST channels): `<URL_M3U_LIBRE_ET_LÉGALE>`
> *(ex. une liste publique Free-TV / Samsung TV Plus / Pluto TV — voir
> https://github.com/Free-TV/IPTV ; à donner ICI seulement, jamais dans le
> binaire.)*
>
> The app then displays channels FROM THAT URL. Live playback, EPG, favorites,
> recording (records the user's own stream locally), and casting are testable.
>
> **ATS:** `NSAllowsArbitraryLoads` is required because the user enters their
> own arbitrary stream server, commonly served over plain HTTP, which we cannot
> pre-declare because it is provided at runtime by the end user. Our own backend
> uses HTTPS. (media_kit/libmpv opens its own sockets, so the narrower
> media-only ATS exception is insufficient.)
>
> **Permissions:** Local Network is used ONLY to discover Chromecast/DLNA
> receivers on the user's Wi-Fi for casting. The app does not provide, host,
> index, or link to any content.

> ⚠️ Ne donne **jamais** tes vrais identifiants IPTV payants au reviewer (ça
> ressemble à de la distribution d'abonnement). Donne une **M3U libre/légale**.

---

## 2. ⚙️ Config technique iOS (déjà appliquée par `ci/ios/patch_info_plist.sh`)

| Clé Info.plist | Valeur | Pourquoi |
|---|---|---|
| `NSAppTransportSecurity.NSAllowsArbitraryLoads` | `true` | Flux IPTV souvent HTTP clair, serveurs fournis par l'user (justif. review ci-dessus) |
| `UIBackgroundModes` | `[audio]` | Audio écran éteint (parité « Écouteurs ») + capability PiP |
| `NSLocalNetworkUsageDescription` | texte FR | Découverte Chromecast / DLNA (iOS 14+) |
| `NSBonjourServices` | `_googlecast._tcp`, `_CC1AD845._googlecast._tcp`, `_airplay._tcp`, `_raop._tcp` | Découverte cast (mDNS) |
| `CFBundleDisplayName` | `7 MOTION` | Nom sous l'icône |
| photo / micro / caméra | **supprimées** | Aucune permission inutile = moins de friction review |

> **DLNA/SSDP** : multicast UDP (239.255.255.250:1900), pas du Bonjour → aucune
> entrée Bonjour ; débloqué par la seule permission « réseau local ».

### ⚠️ Deux limites iOS à connaître (parité Android incomplète)
1. **Picture-in-Picture** : media_kit rend via libmpv dans une *texture* Flutter
   (pas un `AVPlayerLayer`) → **le PiP système iOS ne marche pas tout seul**.
   Recommandation : **sortir iOS avec l'audio de fond uniquement**, marquer le
   PiP « Android only », et **ne PAS le vanter** sur la fiche (vanter une
   fonction absente = règle 2.3.1).
2. **Audio de fond** : `UIBackgroundModes=audio` ne suffit pas seul — il faut
   une **`AVAudioSession` active** côté runtime (catégorie *playback*). À câbler
   en Dart (package `audio_session`, gardé `Platform.isIOS`) — voir §5.

### Fonctions natives = Android only pour l'instant
Les 6 ponts natifs (`cast`, `pip`, `recording_service`, `device`, `gallery`,
`multicast`) sont en Kotlin. Ils sont **fail-open** (try/catch) → sur iPhone ils
**no-op proprement, l'app ne crashe pas**, mais ces fonctions sont **absentes
sur iOS** tant qu'on n'écrit pas l'équivalent Swift. Pour un **1ᵉʳ lancement
App Store, c'est OK** : Apple ne rejette pas pour fonction manquante, seulement
pour crash ou contenu. Lecture cœur (media_kit) = ✅ marche sur iOS.

---

## 3. 🔐 CI — build signé (workflow déjà prêt, dormant)

`build-ios-release.yml` (déclenchement **manuel**) fait : génère iOS → patche
l'Info.plist → importe le certificat + profil dans un trousseau temporaire →
`flutter build ipa` signé → upload TestFlight via **clé API App Store Connect**.
Tant que les secrets sont absents, il **s'arrête au 1ᵉʳ step (vert)**.

### Secrets à créer (Settings → Secrets and variables → Actions)
| Secret | C'est quoi | Où l'obtenir |
|---|---|---|
| `APPLE_TEAM_ID` | Team ID (10 car.) | portail Developer → Membership |
| `APPLE_BUNDLE_ID` | ex. `com.manzilionellm.tvking.tvKing` | enregistré dans le portail |
| `APPLE_PROFILE_NAME` | nom exact du provisioning profile App Store | portail → Profiles |
| `APPLE_CERT_P12_BASE64` | certificat « Apple Distribution » `.p12` en base64 | voir « sans Mac » ci-dessous |
| `APPLE_CERT_P12_PASSWORD` | mot de passe du `.p12` | toi |
| `APPLE_PROFILE_BASE64` | profil App Store `.mobileprovision` en base64 | portail → Profiles |
| `APPLE_KEYCHAIN_PASSWORD` | mot de passe au choix (trousseau CI) | toi |
| `ASC_KEY_ID` | App Store Connect API — Key ID | App Store Connect → Users and Access → Integrations → Keys |
| `ASC_ISSUER_ID` | Issuer ID (un par équipe) | même page |
| `ASC_API_KEY_P8_BASE64` | la clé `.p8` (téléchargeable **une seule fois**) en base64 | même page, à la création |

> **Encoder en base64** : `base64 -i fichier.p12 | pbcopy` (Mac) ou
> `base64 -w0 fichier.p12` (Linux), puis coller dans le secret GitHub.

> **Sans Mac** : générer le **certificat de distribution `.p12`** demande
> normalement un Mac une fois. Pour l'éviter : **fastlane `match`** (stocke
> certs/profils dans un repo git privé) ou **Codemagic CLI** (`app-store-connect`
> crée certs/profils en headless avec juste la clé API ASC) — les deux tournent
> sur le runner macOS GitHub. Tu ne touches jamais un Mac.

### TestFlight — règle à connaître
- **Test interne** (≤ 100 membres de l'équipe) : **aucune review Apple**,
  dispo dès le traitement du build. → pour ton QA.
- **Test externe** (≤ 10 000 via lien public) : **review Apple obligatoire**
  (allégée, mais mêmes règles 5.2.3). → le playbook §1 s'applique aussi.

---

## 4. ✅ Checklist de soumission (le jour J)

1. [ ] Compte **Apple Developer** actif (99 $/an).
2. [ ] Bundle id enregistré dans le portail (= `APPLE_BUNDLE_ID`).
3. [ ] Certificat « Apple Distribution » + profil **App Store** créés.
4. [ ] Clé **App Store Connect API** (.p8) créée + Key ID + Issuer ID.
5. [ ] Les **10 secrets** GitHub renseignés (§3).
6. [ ] App créée dans **App Store Connect** (nom : « 7 MOTION », catégorie
       *Divertissement* ou *Utilitaires*).
7. [ ] Lancer **Actions → iOS release (signed → TestFlight)** → vérifier le
       build qui monte sur TestFlight.
8. [ ] Tester en **interne** (pas de review).
9. [ ] Remplir la **fiche** (texte §1) + **captures d'écran** iPhone.
10. [ ] **App Review Information** : notes §1 + **M3U libre/légale** de démo.
11. [ ] Confidentialité des données + classification par âge (sans adulte).
12. [ ] Soumettre pour review.

---

## 5. 🔭 Phase 2 iOS (après le 1ᵉʳ lancement — à faire avec un device)
Non bloquant pour soumettre, mais pour la parité Android :
- [ ] **Audio de fond runtime** : ajouter `audio_session`, configurer une
      `AVAudioSession` *playback* gardée `Platform.isIOS` (sinon l'audio fond
      s'arrête malgré `UIBackgroundModes`).
- [ ] **PiP iOS natif** : `AVSampleBufferDisplayLayer` + `AVPictureInPicture
      Controller` via un canal de plateforme Swift (media_kit ne le fait pas).
- [ ] **Cast iOS** : SDK Google Cast iOS (équivalent du pont Kotlin actuel).
- [ ] **Enregistrement iOS** : pipeline natif (le `RecordingForegroundService`
      est Android-only).

---

## 5 bis. ✅ Le drapeau `IOS_STORE_BUILD` (implémenté)

Le build App Store passe `--dart-define=IOS_STORE_BUILD=true` (câblé dans
`codemagic.yaml` ET `build-ios-release.yml`). Effets, via
`lib/core/update/build_flags.dart` (`kIsIosStoreBuild` + `kIsStoreBuild`) :

| Retiré du build iOS | Pourquoi (règle Apple) |
|---|---|
| Prix €, essai gratuit, boutons d'achat, liens 7themotion.com | 3.1.1 (paiement hors IAP) |
| Bloc « Activer l'application » (numéro de référence → revendeur) | 3.1.1 (déblocage par code) |
| Écran bloquant essai/gel (`SubscriptionGateScreen`) | 3.1.1 |
| Bouton « Vérifier mon abonnement » + mentions « revendeur » | 5.2.3 (facilitation) |
| Diapos onboarding « activation » et « premium » (cast/enreg. absents d'iOS) | 3.1.1 / 2.3.1 |
| Mode démo embarqué + code examinateur GPLAYREVIEW | §1 : rien de préchargé dans le binaire |
| Auto-updater sideload (déjà retiré de tout build store) | 2.5.2 |

Sur iOS, l'app est donc un **lecteur BYO pur** : accueil vide → « J'ai un
code Xtream » / M3U. Le reviewer Apple reçoit une M3U libre et légale dans
les notes de review (cf. §1), jamais dans le binaire.

---

## 6. Sources
Guidelines Apple (5.2.3, 5.2.1/.2, 2.1, 2.3.1, 3.1.1, 4.3, 1.1.4) :
https://developer.apple.com/app-store/review/guidelines/ ·
ATS : https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity ·
media_kit iOS : https://pub.dev/packages/media_kit ·
Cast iOS (réseau local + Bonjour) : https://developers.google.com/cast/docs/ios_sender/permissions_and_discovery ·
M3U libres pour la démo reviewer : https://github.com/Free-TV/IPTV ·
CI fastlane + clé API ASC : https://docs.fastlane.tools/app-store-connect-api/
