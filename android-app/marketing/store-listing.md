# Fiche magasin & mots-clés — 7 MOTION

> Prêt à coller. Remplace `[À COMPLÉTER]` par tes infos. Règle d'or :
> **on vend le LECTEUR, jamais du contenu.** Ne jamais écrire « chaînes
> incluses », « films gratuits », « abonnement IPTV inclus » → risque de
> retrait + faux. On parle de fonctionnalités du lecteur.

---

## 1. Positionnement (1 phrase)

**FR :** « Le lecteur IPTV premium : ajoute ta source, regarde partout —
téléphone, TV, Chromecast — avec une expérience fluide et élégante. »
**EN :** “The premium IPTV player: add your own source and watch anywhere —
phone, TV, Chromecast — with a smooth, elegant experience.”

---

## 2. Google Play — édition gratuite Android

La fiche française et la fiche anglaise du paquet `com.manzilionellm.tvking`
figurent dans [les métadonnées de la version gratuite](../assets/store/campaign-20261125/play-store-metadata.json).
Leur publication accompagne la mise en production de cette version.

### Déclarations Play de cette édition

| Écran Play Console | Réponse à préparer avec la version distribuée |
|---|---|
| Contenu de l’application → Publicités | Choisir **Oui, mon application contient des annonces** pour la version avec AdMob. Cette mention couvre aussi les annonces promotionnelles gérées depuis le panel. |
| Politique de confidentialité | Dans le champ de cette fiche Play, utiliser la [politique publiée de 7 MOTION gratuit](https://7themotion.pages.dev/7motion-free/privacy/). Le site sert le même document français et anglais que [la copie du projet](../legal/privacy-7motion-free.html). |
| Sécurité des données → SDK publicitaire | Pour le SDK Google Mobile Ads activé, déclarer la collecte **et** le partage des types réellement utilisés pour la publicité, les statistiques et la prévention de la fraude. Le SDK standard traite l’IP (localisation approximative), les interactions dans l’application, les diagnostics et les identifiants d’appareil ou autres identifiants. Vérifier la fiche du SDK effectivement empaqueté et ses réglages avant l’envoi. |
| Sécurité des données → Lecteur et panel | L’identité Android et l’identifiant 7 MOTION remontent au panel pour le fonctionnement et l’assistance. Le lecteur communique aussi l’état de lecture et, selon les réglages de télémétrie, la chaîne courante, l’historique récent et l’inventaire des sources. Examiner les rubriques **Identifiants d’appareil**, **Activité dans l’application**, **Identifiants utilisateur** et **Diagnostics** selon les champs effectivement transmis. |
| Sécurité des données → Sauvegarde | Avec l’accord de l’utilisateur, le serveur reçoit également les URL M3U complètes ou les accès Xtream, y compris le mot de passe, les paramètres de source et les favoris. Déclarer ces traitements facultatifs pour la sauvegarde/restauration. Distinguer le nom d’utilisateur éventuellement transmis dans l’inventaire du panel et le mot de passe transmis dans la sauvegarde. Le choix de sauvegarde ne désactive pas la gestion de l’appareil. |
| Sécurité des données → Chiffrement et suppression | Les échanges AdMob sont chiffrés. L’utilisateur peut saisir une source HTTP et y transmettre des identifiants. Examiner le parcours complet avant de répondre à la question sur le chiffrement de **toutes** les données. Vérifier le traitement effectif des demandes de suppression des enregistrements du panel et des sauvegardes via `support@7themotion.com`. |
| Identifiant publicitaire | Si le manifeste **fusionné de la version distribuée** contient `com.google.android.gms.permission.AD_ID` et si le SDK utilise l’identifiant, le déclarer pour les usages activés. |
| Public cible et contenu | Vérifier l’audience réellement déclarée et la classification à partir du comportement du lecteur. Les catégories de la source importée, le contrôle parental, la radio publique et les scores sportifs sont distincts. La gratuité porte sur le logiciel. |

AdMob associe l’application publiée au paquet `com.manzilionellm.tvking`. Dans le compte de l’éditeur, relier la fiche existante, créer le bloc d’annonces choisi et configurer les messages de confidentialité adaptés. Pour vérifier la propriété, publier la ligne `app-ads.txt` fournie par ce compte à la racine du site développeur lié à la fiche. Vérifier l’état de l’application dans AdMob après l’exploration du fichier. La notice bilingue est en ligne. L’inscription AdMob et les déclarations Play s’effectuent dans les comptes de l’éditeur.

Sources Google pour les déclarations et l’inscription : [publicités et contenu](https://support.google.com/googleplay/android-developer/answer/9859455), [rubriques Sécurité des données](https://support.google.com/googleplay/android-developer/answer/10787469), [données du SDK AdMob](https://developers.google.com/admob/android/privacy/play-data-disclosure), [app-ads.txt](https://support.google.com/admob/answer/9363762).

---

## 3. Amazon Appstore (Fire TV / tablettes) — canal prioritaire

- **Title :** `7 MOTION - IPTV Player`
- **Short description :**
  `Premium IPTV player for your own M3U / Xtream source. Live, replay,
  recording, Chromecast & TV-ready.`
- **Long description :** voir §4.
- **Keywords (champ dédié, séparés par virgules) :**
  `iptv player, m3u player, m3u8, xtream player, media player, live tv player,
  epg, electronic program guide, catch up, replay, dvr, recording, chromecast,
  fire tv, android tv, video player, playlist player`
- **Category :** Movies & TV / Video Players.
- **Device support :** Fire TV + Fire tablets + (phone Android).

---

## 4. Description longue de l’édition premium (Amazon / site)

### FR

```
7 MOTION est un lecteur IPTV premium, élégant et rapide. Vous apportez
votre propre source (liste M3U/M3U8 ou identifiants Xtream Codes) et
profitez d'une expérience de lecture soignée sur tous vos écrans.

7 MOTION ne fournit, ne vend et n'héberge AUCUN contenu, chaîne ou
abonnement. C'est un lecteur : vous saisissez la source de votre choix.

FONCTIONNALITÉS
• Lecture Live, films et séries depuis votre source M3U ou Xtream
• Guide des programmes (EPG) : en cours / à suivre
• Replay / Catch-up quand votre fournisseur le propose
• Enregistrement et reprise de lecture
• Zapping fluide façon « feed » vertical
• Favoris et historique « récemment regardé »
• Chromecast, Android TV, Fire TV & Google TV
• Picture-in-Picture (continuez à regarder en multitâche)
• Sélection des pistes audio et sous-titres, ratio d'image
• Interface premium sombre, pensée pour le confort des yeux
• Multi-appareils : votre licence vous suit

ESSAI & LICENCE
• 7 jours d'essai gratuit
• Ensuite 5 €/an ou 9,90 € à vie (paiement externe sécurisé)

CONFIDENTIALITÉ
Aucun compte requis. Pas de pub. Nous ne suivons pas ce que vous regardez.

7 MOTION est un lecteur multimédia. Pour toute question sur des flux ou
abonnements, contactez votre fournisseur de contenu.
```

### EN

```
7 MOTION is a premium, elegant and fast IPTV player. Bring your own source
(M3U/M3U8 playlist or Xtream Codes credentials) and enjoy a polished
playback experience on every screen.

7 MOTION does NOT provide, sell or host any content, channel or
subscription. It is a player: you enter the source of your choice.

FEATURES
• Play Live, movies and series from your M3U or Xtream source
• Program guide (EPG): now / next
• Replay / Catch-up when your provider supports it
• Recording and resume playback
• Smooth vertical-feed channel zapping
• Favorites and "recently watched" history
• Chromecast, Android TV, Fire TV & Google TV
• Picture-in-Picture multitasking
• Audio/subtitle track selection, aspect ratio control
• Premium dark interface, easy on the eyes
• Multi-device: your license follows you

TRIAL & LICENSE
• 7-day free trial
• Then €5/year or €9.90 lifetime (secure external payment)

PRIVACY
No account required. No ads. We don't track what you watch.

7 MOTION is a media player. For any question about streams or
subscriptions, contact your content provider.
```

---

## 5. Captures d'écran (plan de 6–8)

1. Accueil premium (rangées d'affiches, ambiance sombre/dorée)
2. Lecteur en direct plein écran + logo chaîne
3. Guide des programmes (EPG « en cours / à suivre »)
4. Zapping vertical (feed)
5. Carte « Diffusion sur la TV » (Cast)
6. Favoris / Récemment regardé
7. Enregistrement / Replay
8. Écran d'ajout de source (montre « apporte ta propre source » + mention légale)

> Conseil : ajoute une bande de texte courte sur chaque capture
> (« Caste sur ta TV », « Guide TV intégré », « Enregistre tes programmes »).

---

## 6. « Quoi de neuf » (gabarit de release)

```
• Nouveau : carte « Diffusion sur la TV » pendant le cast
• Sauvegarde cloud : retrouve tes sources après réinstallation
• Lecture plus fluide et interface plus rapide
• Corrections et améliorations de stabilité
```

---

## 7. Rappels conformité (à respecter partout)

- Toujours : « apporte ta propre source », « lecteur », « aucun contenu fourni ».
- Jamais : noms de chaînes/bouquets, « gratuit à vie », logos de chaînes,
  captures montrant des marques tierces identifiables.
- Lien **CGU + Confidentialité** obligatoire dans la fiche (cf. `legal/`).
