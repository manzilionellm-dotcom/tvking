# Google Play — 7 MOTION (com.manzilionellm.tvking)

Tout ce qui se colle ou se téléverse dans la Play Console, prêt à l'emploi.
La fiche générale (Amazon, site, argumentaire) reste dans
`../store-listing.md` ; ce dossier-ci ne parle que de Google Play.

## Visuels

| Fichier | Champ Play Console | Format |
|---|---|---|
| `icon-512.png` | Icône de l'application | 512 × 512, PNG 32 bits, alpha opaque |
| `feature-graphic-1024x500.png` | Image de bandeau | 1024 × 500, PNG 32 bits |

Générés depuis `assets/branding/logo_7motion.jpg` (le vrai logo, pas une
invention). Il manque encore **2 à 8 captures d'écran de téléphone**
(16:9 ou 9:16) : elles ne peuvent venir que d'un appareil réel. Règle
absolue sur les captures — **aucun logo ni nom de chaîne réelle visible**.

## Titres

| | Texte | Longueur |
|---|---|---|
| Titre FR | `Lecteur IPTV M3U – 7 MOTION` | 27 / 30 |
| Titre EN | `M3U IPTV Player – 7 MOTION` | 26 / 30 |

Le mot-clé passe DEVANT la marque : personne ne cherche « 7 MOTION »,
les gens tapent *iptv*, *m3u*, *lecteur*.

## Description courte

**FR** (71 / 80)

```
Lecteur M3U/Xtream : apportez votre source, aucun contenu n'est fourni.
```

**EN** (72 / 80)

```
M3U/Xtream media player. Bring your own source — no content is provided.
```

## Description complète — FR

```
7 MOTION est un lecteur multimédia pour Android. Vous apportez votre propre
source (fichier ou lien M3U/M3U8, ou identifiants Xtream Codes) et 7 MOTION
la lit proprement, dans une interface sombre pensée pour le confort.

7 MOTION ne fournit, n'héberge, ne vend et n'indexe aucun contenu, aucune
chaîne et aucun abonnement. L'application est vide à l'installation : rien
ne s'affiche avant que vous ayez ajouté votre propre source.

LECTURE
- Direct, films et séries issus de VOTRE source
- Moteurs de lecture natifs, pensés pour les flux instables
- Pistes audio et sous-titres, ratio d'image, zoom
- Reprise là où vous vous étiez arrêté
- Picture-in-Picture pour continuer en multitâche
- Enregistrement local et export vers votre galerie

ORGANISATION
- Guide des programmes (EPG XMLTV) : en cours / à suivre
- Favoris, « récemment regardé », recherche instantanée
- Zapping vertical fluide, façon fil d'actualité
- Replay / catch-up lorsque votre source le propose
- Rappels de programmes par notification
- Mode Enfants protégé par code

SUR TOUS VOS ÉCRANS
- Téléphone, tablette, Android TV, Google TV, Fire TV
- Diffusion vers un téléviseur via Chromecast ou QR code
- Vos sources et votre historique vous suivent d'un appareil à l'autre

CE DONT VOUS AVEZ BESOIN
- Une source M3U/M3U8 ou un accès Xtream Codes que VOUS fournissez
- Une connexion Internet
7 MOTION ne vend pas d'accès à des flux et ne peut pas vous en procurer.

CONFIDENTIALITÉ
Aucun compte n'est requis. L'application utilise un identifiant d'appareil
pour gérer votre licence et sauvegarde vos sources et votre historique afin
de les retrouver sur vos autres appareils. L'application affiche nos propres
annonces et offres partenaires. Détail complet :
https://app.7themotion.com/confidentialite

AVERTISSEMENT
7 MOTION est un LECTEUR. Aucun contenu, aucune chaîne, aucun film, aucune
série et aucun abonnement n'est fourni, hébergé ou revendu par
l'application ni par son éditeur. Vous apportez votre propre source et vous
êtes seul responsable de la légalité des flux que vous lisez et des droits
dont vous disposez. Pour toute question sur un flux, adressez-vous au
fournisseur qui vous l'a fourni.
```

## Description complète — EN

```
7 MOTION is a media player for Android. You bring your own source (an
M3U/M3U8 file or link, or Xtream Codes credentials) and 7 MOTION plays it
smoothly, in a dark interface built for comfort.

7 MOTION does not provide, host, sell or index any content, channel or
subscription. The app is empty on install: nothing appears until you add
your own source.

PLAYBACK
- Live, movies and series from YOUR own source
- Native playback engines, tuned for unstable streams
- Audio and subtitle tracks, aspect ratio, zoom
- Resume where you left off
- Picture-in-Picture for multitasking
- Local recording and export to your gallery

ORGANISATION
- Program guide (XMLTV EPG): now / next
- Favorites, "recently watched", instant search
- Smooth vertical-feed zapping
- Replay / catch-up when your source offers it
- Program reminders via notifications
- PIN-protected Kids Mode

ON EVERY SCREEN
- Phone, tablet, Android TV, Google TV, Fire TV
- Send to a television via Chromecast or QR code
- Your sources and history follow you across devices

WHAT YOU NEED
- An M3U/M3U8 source or Xtream Codes access that YOU provide
- An internet connection
7 MOTION does not sell stream access and cannot obtain it for you.

PRIVACY
No account required. The app uses a device identifier to manage your licence
and backs up your sources and history so you can find them on your other
devices. The app displays our own announcements and partner offers. Full
details: https://app.7themotion.com/confidentialite

DISCLAIMER
7 MOTION is a PLAYER. No content, channel, movie, series or subscription is
provided, hosted or resold by the app or its publisher. You bring your own
source and you alone are responsible for the legality of the streams you
play and for holding the necessary rights. For any question about a stream,
contact the provider who supplied it.
```

## Sécurité des données — ce qu'il faut déclarer

Établi en lisant le code, pas de mémoire. Tout est **chiffré en transit**
(les deux hôtes serveur sont en `https`, cf. `backend_hosts.dart`) et tout
est **supprimable sur demande** (cf. la politique de confidentialité).
Rien n'est **partagé** avec un tiers.

| Donnée | Collectée | Oblig./Fac. | Finalité | Preuve dans le code |
|---|---|---|---|---|
| Identifiants d'appareil (MAC virtuelle `MK:…`, ANDROID_ID) | oui | obligatoire | licence, activation, anti-fraude | `device_identity.dart`, `subscription_backend.dart` |
| Adresse IP et pays | oui (côté serveur) | obligatoire | sécurité, présence « en ligne », choix des annonces par pays | `cloudflare/worker.js` |
| Diagnostics appareil (modèle, marque, version Android, version app, langue) | oui | obligatoire | support, compatibilité | `subscription_backend.dart` |
| Diagnostics — échecs de lecture (1×/24 h : chaîne, hôte, code d'erreur ; **jamais l'URL du flux**) | oui | obligatoire | corriger les pannes de lecture | `fleet_reporter.dart` |
| Activité dans l'app (chaîne en cours, 50 dernières chaînes) | oui | obligatoire | « Récemment », synchro entre appareils | `subscription_backend.dart` |
| Inventaire des sources (nom, serveur/URL, identifiant ; **jamais le mot de passe**) | oui | obligatoire | support, retrouver ses sources ailleurs | `subscription_backend.dart` |
| Avis client (note + commentaire) | oui | **facultatif** | support | `feedback_repository.dart` |
| **Journaux de plantage** | **NON** | — | — | build v14 : `GOOGLE_SERVICES_JSON absent → Crashlytics désactivé`, vérifié dans le journal du run 30727088092 |
| Photos, vidéos, fichiers | non | — | — | permissions média retirées de l'AAB Play (`build-android.yml`) |
| Nom, e-mail, contacts, position précise, santé, finances, SMS, micro, caméra | non | — | — | aucun code correspondant |

### Deux réponses à ne pas rater

- **« Votre application contient-elle des annonces ? » → OUI.**
  L'app affiche des annonces et offres partenaires servies par notre propre
  infrastructure (`lib/features/ads/`, table `ad_campaigns` du Worker). Il
  n'y a aucune régie tierce et aucun identifiant publicitaire, mais la
  réponse au formulaire reste **oui**.
- **Journaux de plantage → ne rien déclarer.** Crashlytics n'était pas actif
  au build de l'AAB v14. Si le secret est posé un jour, cette ligne devra
  changer.

## À ne jamais écrire

- « chaînes gratuites », « TV gratuite », « X chaînes incluses »
- un nom de chaîne ou de bouquet réel (motif de refus le plus fréquent)
- « regardez tous les matchs / tout le sport »
- un prix ou un moyen de paiement hors Google Play pour un accès numérique
  (motif de sanction à part entière)

## Reste à faire à la main dans la Console

1. Coller titres et descriptions (FR puis EN).
2. Téléverser `icon-512.png`, `feature-graphic-1024x500.png` et 2 à 8
   captures de téléphone.
3. Politique de confidentialité : `https://app.7themotion.com/confidentialite`
4. Sécurité des données : recopier le tableau ci-dessus.
5. Classification du contenu (IARC), public cible (16+), pays, coordonnées.
6. Créer la version Production avec l'AAB **versionCode 14**, puis déployer.
