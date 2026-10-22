# 7 MOTION — port iPhone du build 1988121

Cette préparation reconstruit **la source exacte de la dernière release mobile
`7motion-1988121`**, puis applique une adaptation iPhone isolée. Elle ne construit
pas `android-app/lib` (qui appartient aussi à ZUNO et a divergé du téléphone).
La base, les dix correctifs, leurs empreintes Git et Flutter 3.47.7 sont verrouillés
dans `source.lock.json`. `prepare_source.py` refuse toute divergence.

## Vérification et livraison

Le workflow actif est **à la racine** : `.github/workflows/7motion-ios.yml`.
Les anciens workflows sous `android-app/.github/` ne sont pas exécutés par GitHub.

Un push sur `feature/7motion-iphone-*` prépare la source, teste le contrat iOS,
compile avec Xcode 26+ / SDK iOS 26+, compile pour simulateur, lance l'app sur
un iPhone simulé et conserve une vraie capture. La garde de publication du dépôt
reste appelée. Une compilation sans signature ne produit **pas** d'IPA installable.

Artefact `7motion-iphone-0.3.7-<run>` :

- `7motion-iphone-unsigned.zip` : binaire ARM64 non signé pour vérification.
- `7motion-iphone-simulator.zip` : application de simulateur, pas pour un iPhone réel.
- `7motion-iphone-source.tar.gz` : projet Flutter/Xcode reconstitué avec le port.
- `iphone-simulator.png` : capture réelle de lancement, pas une capture marketing.
- `IOS_SOURCE_PROVENANCE.json` : origine exacte de la version.

**Ne pas annoncer « prêt pour l'App Store » avant un run réussi, la signature,
un test sur iPhone réel et la validation du dossier de soumission.** Un lancement
simulé ne prouve ni la lecture d'une source, ni l'audio verrouillé, ni Face ID réel.

## Adaptations incluses

- iPhone sous iOS 15 minimum ; SDK de compilation iOS 26 minimum.
- Nom 7 MOTION et icône rouge de la dernière version, sans alpha dans l'icône Apple.
- Décodeur iOS `media_kit_libs_ios_video` explicite, version 1.1.4.
- Notifications Darwin avec permission demandée au moment du choix utilisateur.
- Description de permission Face ID pour le verrou biométrique existant.
- Session audio Apple et identifiant privé dans le trousseau local.
- Clé AES aléatoire de 32 octets dans le trousseau pour le chiffrement existant.
- Profil `mobile` conservé pour le panel existant, qui n'accepte pas encore un
  profil `ios`. Le pont natif identifie Apple dans les informations d'assistance.
- Restrictions Store existantes activées : pas de téléchargement/mise à jour APK.
- Rayon réservé 18+ absent de cette édition ; filtre du dépôt de chaînes et de VOD.

Le canal iOS réutilise les règles fonctionnelles du canal Google Play pour les
boutons d'achat et le verrou de fin d'essai. Aucune intégration StoreKit ni vente
in-app n'est ajoutée. Le modèle commercial Apple reste à valider avant soumission.

## Limites connues à tester ou à compléter

- Chromecast, DLNA, AirPlay et mini-fenêtre PiP ne sont pas portés dans cette
  première édition. Aucun multicast n'est lancé ; l'action Cast explique la limite.
- Export Galerie/remux Android, miroir d'écran et enregistrement prolongé en
  arrière-plan ne doivent pas être annoncés sur la fiche iPhone. La lecture et le
  partage des fichiers existants doivent être vérifiés sur appareil réel.
- La source conserve ses radios, football, lecteur, EPG et favoris. Leurs services
  réseau, droits de contenu et notifications en arrière-plan exigent des essais réels.
- Le composant iOS ne fait pas de suivi publicitaire ; cela ne constitue pas une
  déclaration « aucune donnée collectée » pour toute l'app. Le backend, la sauvegarde
  cloud et les dépendances doivent figurer dans le questionnaire de confidentialité.
- L'exception HTTP est destinée aux sources saisies par l'utilisateur. Sa justification
  doit être présentée honnêtement à Apple.

## Signature Apple et App Store Connect

Identifiant proposé et verrouillé : **`com.manzilionellm.sevenmotion`**.
Le vérifier/réserver dans le compte Apple avant le premier envoi ; s'il existe déjà
une fiche 7 MOTION, réutiliser son identifiant en adaptant le verrou et les tests.

Après validation et intégration du workflow à la branche autorisée
`ccr-b93e1afd-gwirw0`, l'action manuelle `signed_archive=true` fabrique un IPA signé,
sans téléversement. Elle conserve l'environnement de validation `zuno-app-test`.
Elle échoue explicitement si les prérequis manquent ; elle ne transforme pas une
absence de signature en succès vert.

Secrets à enregistrer dans GitHub (jamais dans un fichier source ni un message) :

| Secret | Contenu |
| --- | --- |
| `APPLE_TEAM_ID` | Équipe Apple Developer, 10 caractères |
| `APPLE_BUNDLE_ID` | `com.manzilionellm.sevenmotion` |
| `APPLE_CERT_P12_BASE64` | Certificat Apple Distribution exporté en P12 et encodé en base64 |
| `APPLE_CERT_P12_PASSWORD` | Mot de passe du P12 |
| `APPLE_PROFILE_BASE64` | Profil App Store de cette app, encodé en base64 |

Le script vérifie le Team ID, le Bundle ID, l'expiration et le type App Store du
profil. Il crée un trousseau éphémère et le supprime, même en cas d'échec.
Le numéro Apple est `<run_number>.<run_attempt>` ; une relance reçoit donc un
numéro différent. Le label humain **1988121** indique la base mobile, sans consommer
un nouveau numéro de publication pour une compilation de préparation.

Pour la livraison publique : importer l'IPA signé dans App Store Connect avec
Transporter/Xcode, faire un TestFlight sur iPhone réel, renseigner captures,
confidentialité, classification d'âge, contact et accès de revue, puis soumettre.
La validation et la disponibilité sur l'App Store relèvent d'Apple.

Sources officielles vérifiées le 22 octobre 2026 :
- https://developer.apple.com/news/upcoming-requirements/
- https://docs.flutter.dev/deployment/ios
- https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
