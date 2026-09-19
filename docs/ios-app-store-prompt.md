# Prompt — Claude dans le navigateur : déposer 7 MOTION sur l'App Store

> À coller tel quel dans Claude (extension Chrome), connecté aux comptes de
> Lionel : Apple Developer, App Store Connect, GitHub. Tout ce qui suit est
> vrai à la date du 19/09/2026 pour la branche
> `claude/retour-13sept-notifications` du dépôt `manzilionellm-dotcom/tvking`.
> Le détail technique est dans `docs/ios-app-store-playbook.md`.

---

Tu es l'assistant de Lionel, propriétaire de 7 MOTION (lecteur IPTV). Ta mission : publier l'app iPhone **7 MOTION** sur TestFlight puis l'App Store, depuis le navigateur, en suivant les phases ci-dessous **dans l'ordre**. Tu agis dans mes comptes (Apple Developer, App Store Connect, GitHub), déjà connectés.

## Règles absolues

1. **Tu n'inventes rien.** Chaque valeur à saisir est donnée ci-dessous. Si une page demande quelque chose qui n'y est pas, tu t'arrêtes et tu me demandes.
2. **Tu me passes la main** pour : tout paiement, toute vérification d'identité, tout code à deux facteurs, et pour ouvrir un fichier téléchargé (tu ne sais pas lire un fichier sur mon disque).
3. **Tu ne donnes JAMAIS d'identifiants IPTV payants** — ni à Apple, ni dans une note, ni dans une capture. Pour le reviewer, uniquement la liste M3U libre et légale indiquée en phase 10.
4. **Tu ne cliques pas « Envoyer pour examen »** (Submit for Review) sans ma confirmation explicite, écrite, à ce moment-là.
5. Après chaque phase, tu m'écris une ligne : ce qui est fait, ce qu'il reste. En cas d'erreur, tu cites le message exact de la page.

## Valeurs fixes (copie exacte)

| Champ | Valeur |
|---|---|
| Nom de l'app | `7 MOTION` (si refusé : `7 MOTION Player`) |
| Bundle ID | `com.manzilionellm.tvking` |
| SKU | `7motion-ios-001` |
| Langue principale | Français |
| Catégorie principale / secondaire | Divertissement / Utilitaires |
| Prix | Gratuit, tous les pays |
| Version | `0.3.4` |
| Copyright | `© 2026 7 MOTION` |
| URL d'assistance | `https://app.7themotion.com` |
| URL de politique de confidentialité | `https://app.7themotion.com/privacy` |
| Sous-titre (30 car. max) | `Lecteur IPTV M3U et Xtream` |
| Mots-clés | `iptv,m3u,xtream,lecteur,player,tv,epg,chaînes,direct,replay` |
| Dépôt GitHub | `manzilionellm-dotcom/tvking`, branche `claude/retour-13sept-notifications` |

**Description (FR) :**

```
7 MOTION est un lecteur multimédia pour vos propres playlists IPTV.

7 MOTION ne fournit aucun contenu, chaîne ou playlist. C'est un lecteur conçu pour être utilisé avec vos propres contenus et playlists dont vous détenez les droits d'accès. Compatible M3U et Xtream Codes.

• Ajoutez votre liste M3U ou votre compte Xtream en quelques secondes
• Lecture fluide, décodage matériel, formats 4K
• Guide des programmes (EPG) de vos chaînes
• Favoris, historique, reprise là où vous en étiez
• Rattrapage (catch-up) quand votre fournisseur le propose
• Interface claire, 8 langues

Aucun contenu n'est inclus dans l'application.
```

**Texte promotionnel (170 car. max) :** `Votre lecteur IPTV : ajoutez votre propre liste M3U ou Xtream et regardez vos chaînes, avec guide des programmes et favoris.`

## Phase 1 — Compte Apple Developer

1. Ouvre `https://developer.apple.com/account`.
2. Vérifie que l'adhésion **Apple Developer Program** est **active** (page *Membership details*). Note le **Team ID** (10 caractères) : c'est `APPLE_TEAM_ID`.
3. Si l'adhésion n'est pas active ou demande un paiement / une vérification d'identité : **arrête-toi et passe-moi la main.** Rien d'autre ne peut avancer sans elle.

## Phase 2 — Enregistrer l'identifiant de l'app

1. `https://developer.apple.com/account/resources/identifiers/list` → **+** → *App IDs* → *App*.
2. Description : `7 MOTION` · Bundle ID : **Explicit** `com.manzilionellm.tvking`.
3. Capabilities : ne coche **rien** de plus (aucune capacité spéciale n'est requise). Continue → Register.
4. Si l'identifiant existe déjà, passe.

## Phase 3 — Clé API App Store Connect

1. `https://appstoreconnect.apple.com/access/integrations/api` (Users and Access → Integrations → App Store Connect API → onglet *Team Keys*).
2. **+** (Generate API Key) : nom `GitHub CI 7 MOTION`, accès **Admin** (nécessaire pour créer le certificat depuis le CI).
3. Note l'**Issuer ID** (en haut de page) → `ASC_ISSUER_ID`, et le **Key ID** de la clé → `ASC_KEY_ID`.
4. Clique **Download API Key** : le fichier `AuthKey_<KEYID>.p8` se télécharge **une seule fois**. Tu ne peux pas le lire : **demande-moi de l'ouvrir dans un éditeur de texte et de te coller son contenu** (il commence par `-----BEGIN PRIVATE KEY-----`). Ce contenu, en clair, est la valeur de `ASC_API_KEY_P8_BASE64` (le CI accepte le clair aussi bien que le base64).

## Phase 4 — Jeton GitHub (une fois, 7 jours)

1. `https://github.com/settings/personal-access-tokens/new` (fine-grained).
2. Nom `ios-signing-bootstrap` · Expiration **7 jours** · Repository access : **Only select repositories** → `manzilionellm-dotcom/tvking`.
3. Permissions → *Repository permissions* : **Secrets : Read and write** (Metadata : Read s'ajoute seul). Rien d'autre.
4. Generate token → copie-le : c'est `GH_ADMIN_PAT`. Il sert au CI pour ranger le certificat dans les secrets ; il expire seul.

## Phase 5 — Poser les 6 secrets

`https://github.com/manzilionellm-dotcom/tvking/settings/secrets/actions` → **New repository secret**, un par un, noms EXACTS :

| Nom | Valeur |
|---|---|
| `APPLE_TEAM_ID` | Team ID de la phase 1 |
| `APPLE_BUNDLE_ID` | `com.manzilionellm.tvking` |
| `ASC_KEY_ID` | Key ID de la phase 3 |
| `ASC_ISSUER_ID` | Issuer ID de la phase 3 |
| `ASC_API_KEY_P8_BASE64` | contenu du `.p8` que je t'ai collé (en clair) |
| `GH_ADMIN_PAT` | jeton de la phase 4 |

## Phase 6 — Fabriquer le certificat et le profil (sans Mac)

1. `https://github.com/manzilionellm-dotcom/tvking/actions/workflows/ios-signing-bootstrap.yml` → **Run workflow** → branche `claude/retour-13sept-notifications` → Run.
2. Attends la fin (2 à 4 min). Vert = le CI a créé chez Apple le certificat « Apple Distribution » et le profil App Store, et a écrit 5 nouveaux secrets (`APPLE_CERT_P12_BASE64`, `APPLE_CERT_P12_PASSWORD`, `APPLE_PROFILE_BASE64`, `APPLE_PROFILE_NAME`, `APPLE_KEYCHAIN_PASSWORD`). Vérifie qu'ils apparaissent dans la page des secrets.
3. Rouge : ouvre le job, copie-moi le message d'erreur exact. Ne relance pas à l'aveugle.
4. Une fois vert, **supprime le secret `GH_ADMIN_PAT`** (il n'a plus d'usage) et révoque le jeton sur GitHub.

## Phase 7 — Construire et envoyer sur TestFlight

1. `https://github.com/manzilionellm-dotcom/tvking/actions/workflows/build-ios-release.yml` → **Run workflow** → branche `claude/retour-13sept-notifications` → `submit_to_testflight` = `true` → Run.
2. Attends la fin (20 à 30 min). Vert = le `.ipa` signé est parti vers App Store Connect.
3. Rouge : copie-moi le message exact du step en échec.

## Phase 8 — Créer l'app dans App Store Connect

1. `https://appstoreconnect.apple.com/apps` → **+** → *New App*.
2. Platforms : **iOS** · Name : `7 MOTION` · Primary Language : **French** · Bundle ID : choisis `com.manzilionellm.tvking` · SKU : `7motion-ios-001` · User Access : Full Access.
3. Si le nom est pris : `7 MOTION Player`, et dis-le-moi.

## Phase 9 — TestFlight (test interne, sans review)

1. Onglet **TestFlight** de l'app. Le build de la phase 7 apparaît après traitement (10 à 30 min). S'il pose la question du chiffrement, réponds **Non** (l'app n'utilise que le HTTPS standard ; le build le déclare déjà).
2. *Internal Testing* → **+** → groupe `Équipe` → ajoute mon identifiant Apple comme testeur → associe le build.
3. Dis-moi quand le build est **Ready to Test** : je l'installe sur mon iPhone et je fais les captures d'écran.

## Phase 10 — Remplir la fiche App Store

Onglet **App Store** → version `0.3.4` (Prepare for Submission).

1. **App Information** : sous-titre, catégories, *Content Rights* → « Non, l'app ne contient pas de contenu de tiers » (elle n'embarque **aucun** contenu), *Age Rating* → réponds **Aucun / Non** à chaque question (l'app ne contient rien ; si une question te paraît ambiguë, demande-moi), URL de politique de confidentialité.
2. **Pricing and Availability** : Gratuit · tous les pays.
3. **App Privacy** → *Get Started* → l'app **collecte** des données, **non liées à l'identité de l'utilisateur**, **pas de suivi (tracking)** :
   - *Identifiers → Device ID* : usage **App Functionality** (activation de la licence sur l'appareil).
   - *Usage Data → Product Interaction* : usage **App Functionality** et **Analytics** (chaîne en cours, historique, pour restaurer la session).
   - *Diagnostics → Crash Data* et *Performance Data* : usage **App Functionality** (boîte noire, banc d'essai).
   - Rien d'autre : pas de nom, pas d'email, pas de localisation, pas de contacts.
4. **Version Information** : captures d'écran → **attends les miennes** (6,7" et 6,5" — tu ne peux pas les générer) ; description, texte promotionnel, mots-clés, URL d'assistance, copyright, version `0.3.4`.
5. **App Review Information** : mon nom, mon téléphone, mon email (demande-les-moi) ; *Sign-in required* : **Non** ; **Notes** (colle en anglais) :

```
This app is a generic media player. It contains no channels, playlists, or content of its own; the end user supplies their own legal M3U URL or Xtream Codes login.

To test all features, on first launch tap "Add Playlist" → "M3U URL" and paste this free, ad-supported, license-free sample playlist of free-to-air channels:
https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8

The app then displays channels from that URL. Live playback, EPG, favorites and playback resume are testable.

ATS: NSAllowsArbitraryLoads is required because the user enters their own stream server, commonly served over plain HTTP, which cannot be pre-declared. Our own backend uses HTTPS.

Permissions: Local Network is used only to discover Chromecast/DLNA receivers on the user's Wi-Fi for casting. The app does not provide, host, index, or link to any content.
```

   Avant de coller cette URL de démo, ouvre-la dans un onglet et vérifie qu'elle répond (une liste de chaînes en texte). Si elle ne répond plus, dis-le-moi : on en choisira une autre ensemble, jamais une liste payante.
6. **Build** : sélectionne le build de la phase 7. *Save*.

## Phase 11 — Soumettre

1. Quand tout est vert dans la fiche (aucun champ en rouge) et que mes captures sont en place : **arrête-toi** et écris-moi « Prêt à soumettre : confirme ».
2. Seulement après mon « confirme » écrit : *Add for Review* → *Submit to App Review*.
3. Rapport final : lien App Store Connect de l'app, numéro de build, date/heure de soumission, et la liste de ce que tu n'as pas pu faire.

## Ce que tu ne peux pas faire (et c'est normal)

- Payer l'adhésion Apple, vérifier une identité, saisir un code 2FA → moi.
- Lire le fichier `.p8` téléchargé → je te colle son contenu.
- Faire les captures d'écran → moi, depuis TestFlight sur mon iPhone.
- Fabriquer un certificat → le CI le fait (phase 6), pas toi.
