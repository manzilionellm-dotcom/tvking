# Divergence des branches — production panel/Worker et branche de l'app

Relevé du 06/10/2026, uniquement à partir de commandes `git` exécutées
(rien n'a été fusionné, rien n'a été poussé sur ces deux branches).

## Les trois branches

| Rôle | Branche | Tête | Date |
|---|---|---|---|
| Production panel + Worker | `claude/panel-mise-en-ligne` | `636aad6` | 05/10/2026 |
| App box (historique) | `ccr-1d45eb8b-x46ieg` | `6982934` | 05/10/2026 |
| Branche de travail (cette mission) | `ccr-b93e1afd-gwirw0` | `a09a832` + ce commit | 05-06/10/2026 |

| Mesure | Valeur | Commande |
|---|---|---|
| Ancêtre commun production / app | `fde70596` (24/09/2026) | `git merge-base` |
| Commits seulement en production | 37 | `git rev-list --count app..prod` |
| Commits seulement sur l'app | 149 | `git rev-list --count prod..app` |
| Branche de travail vs app | 0 en retard, 19 en avance | même commande |
| Fichiers en conflit si on fusionne | 18 | `git merge-tree --write-tree prod app` |
| Fichiers supprimés côté app | 14 | `git diff --diff-filter=D --name-only base app` |

## Ce qu'une fusion à l'aveugle casserait (PROUVÉ par `git merge-tree`)

Conflits de contenu (9) :

- `android-app/admin-panel/src/App.tsx`, `components/Sidebar.tsx`,
  `pages/ActivatePage.tsx`, `pages/DevicesPage.tsx`
- `android-app/cloudflare/api_v1.js`, `android-app/cloudflare/worker.js`
- `android-app/lib/features/playlists/data/remote_source_repository.dart`
- `android-app/lib/features/subscription/data/subscription_backend.dart`,
  `subscription_state.dart`, `tv/presentation/tv_activation_screen.dart`,
  `tv/presentation/tv_app.dart`
- `app/sitemap.ts`, `eslint.config.mjs`

Conflit « ajouté des deux côtés » (1) : `android-app/cloudflare/source_crypto.js`
— deux implémentations différentes du chiffrement des liens. Choisir un
côté sans migration rendrait illisibles les liens déjà chiffrés par l'autre.

Conflits « supprimé d'un côté, modifié de l'autre » (4) :
`admin-panel/src/pages/ServersPage.tsx`, `app/layout.tsx`, `app/page.tsx`,
`app/start/page.tsx`.

Suppressions côté app qui passeraient sans conflit : `app/films`,
`app/formation`, `app/list`, `app/reglages`, `app/search`, `app/sport`,
`app/tv`, `app/watch/[slug]`, `android-app/test/widget_test.dart`,
`android-app/.github/workflows/quality.yml`. Une fusion de l'app dans la
production **retirerait ces pages du site** sans le signaler.

## Correctif de sécurité non déployé

`3f1c841` « Ferme l'accès aux codes IPTV par la seule MAC » (30/09/2026)
n'existe que sur `ccr-1d45eb8b-x46ieg` et la branche de travail. Il ajoute
`device_guard.js` (secret propre à chaque box, comparaison en temps
constant, sauvegarde cloud fermée aux inconnus) et touche `api_v1.js`,
`worker.js`, `source_crypto.js`.

En production aujourd'hui, `GET /api/device-source/:mac` rend les codes
IPTV déchiffrés à quiconque connaît la MAC (PROUVÉ en lecture le
05/10/2026 ; seul frein : la limite de débit de 120 requêtes par minute et
par IP, livrée par le patch 6). Les MAC sont affichées sur l'écran des
box. C'est le risque de production le plus grave relevé pendant cette
mission.

Contrainte de déploiement : `device_guard` a deux époques. Une box qui n'a
pas encore enregistré de secret garde l'accès en lecture tant que sa
licence est valide. Déployer le Worker avant que les box aient le
logiciel qui enregistre le secret ne coupe donc personne, mais ne ferme
le trou que pour les box enrôlées.

## Plan de réconciliation non destructif

Aucune étape ne réécrit l'historique, aucune ne force un push, aucune ne
touche `main`. Chaque étape finit par des tests verts ou on s'arrête.

1. **Branche d'intégration depuis la production** :
   `git switch -c integration/panel-app origin/claude/panel-mise-en-ligne`.
   La production reste intacte et déployable pendant tout le travail.
2. **Appliquer les patchs déjà prouvés sur la production**, dans l'ordre :
   `docs/patches/` 1 à 7 (`git apply --3way`). Ils ont été écrits contre
   la tête de production et vérifiés dessus. Tests Worker, audit sécurité,
   test de concurrence workerd, tests panel et build panel.
3. **Porter le correctif `device_guard`** (`3f1c841`) par `git cherry-pick -x`,
   en résolvant `api_v1.js`, `worker.js` et `source_crypto.js` à la main.
   Pour `source_crypto.js` : garder le format de production pour la lecture
   des liens existants, et ajouter l'autre format en lecture seule
   (expand-contract) ; un test doit relire des liens chiffrés par chacune
   des deux versions. `zuno_security.test.mjs` doit passer.
4. **Ne PAS reprendre les suppressions de `app/`** : le site Next.js reste
   tel qu'en production. Les pages retirées côté app sont traitées à part,
   avec redirections 301 si une URL disparaît.
5. **Code de la box** : la box se construit depuis la branche de l'app
   (`build-zuno-tv.yml`). Elle n'a pas besoin d'être fusionnée dans la
   branche du panel ; seuls les contrats HTTP comptent (`/api/box/ack`,
   `order_id`, `trace_id`, `rev`). Ils sont rétrocompatibles dans les deux
   sens. PROUVÉ : le code de production actuel répond 404 sur
   `POST /api/box/ack/:mac`, avec ou sans Durable Object (appel direct du
   Worker de production sur base SQLite, 06/10/2026) ; la box envoie alors
   UNE fois et s'arrête (`order_ack_client_test.dart`). Dans l'autre sens,
   un ordre jamais accusé passe `expired` après 10 min
   (`order_ack_trace.test.mjs`).
6. **Déploiement par étapes** via `deploy-panel-cloudflare.yml`
   (`confirme=DEPLOYER`), en relisant une MAC de référence avant et après.
   D'abord le Worker avec les patchs 1-7 (ajouts de tables et de colonnes
   seulement), puis `device_guard`, puis la box qui enregistre son secret.
7. **Seulement après** : proposer une PR de l'intégration vers la branche
   de production, relue par une personne. Jamais de fusion directe.

## Annexe A — commits seulement en production (37)

- `636aad6` 2026-10-05 Activation à distance : essais gratuits 3 jours, 7 jours, 1 mois (défaut 7 jours)
- `39b1b84` 2026-10-05 Mise en ligne panel : la vérification du bundle servi réessaie (propagation Cloudflare), plus de faux rouge
- `211f228` 2026-10-05 Interrupteur allumé / éteint par liste : Worker garde enabled:false, panel affiche le bouton
- `ef3b387` 2026-10-05 Panel : écran « Activation à distance » (licence + liste en un bouton) ; listes du client jamais renvoyées par « Supprimer »
- `f4d1d64` 2026-10-04 Merge pull request #97 from manzilionellm-dotcom/cursor/canal-temps-reel-worker-c1d5
- `516b87f` 2026-10-04 Canal panel → box : Durable Object, WebSocket, repli long-poll.
- `0896028` 2026-10-04 Panel : bouton « Supprimer » par liste (la box l'efface seule) et MAC complétée sans « MK: »
- `f7e1fd0` 2026-10-03 Workflow de mise en ligne : enregistrement auprès de GitHub au push (jobs sautés sans DEPLOYER)
- `3c275b9` 2026-10-03 Tests et guide alignés sur l'activation pro ; workflow de mise en ligne
- `44549fb` 2026-10-03 Fusion de claude/panel-activation-pro dans la livraison panel
- `7cdcf7c` 2026-10-03 Fusion de claude/essai-7-jours dans la livraison panel
- `9fa1a36` 2026-10-03 feat(panel): activation pro, sans clonage familial
- `0ca93f9` 2026-10-03 docs: préparer le déploiement du panel et aligner l'e2e
- `e22a98e` 2026-10-03 Merge remote-tracking branch 'origin/claude/panel-pro' into claude/panel-tout-en-un
- `117d544` 2026-10-03 Merge remote-tracking branch 'origin/claude/panel-audit-liaison' into claude/panel-tout-en-un
- `d5d150c` 2026-10-03 Merge remote-tracking branch 'origin/claude/panel-audit-ui' into claude/panel-tout-en-un
- `e2bb333` 2026-10-03 Merge remote-tracking branch 'origin/claude/panel-audit-robustesse' into claude/panel-tout-en-un
- `00fc527` 2026-10-03 Merge remote-tracking branch 'origin/claude/panel-audit-securite' into claude/panel-tout-en-un
- `313af52` 2026-10-03 Merge remote-tracking branch 'origin/claude/panel-audit-activation' into claude/panel-tout-en-un
- `bf5a16b` 2026-10-03 Merge remote-tracking branch 'origin/claude/panel-audit-e2e' into claude/panel-tout-en-un
- `cdcf369` 2026-10-03 feat(trial): essai de 7 jours décidé par le serveur
- `9cfc9d0` 2026-10-03 feat(admin-panel): séparer l'activation et le lien de chaînes
- `6fbc983` 2026-10-03 fix(liaison): effacement panel derrière un interrupteur coupé
- `aa10bfd` 2026-10-03 fix(admin-panel): défauts d'interface prouvés au navigateur
- `896b8f3` 2026-10-03 feat(admin-panel): rendre le panneau plus clair
- `799b1da` 2026-10-03 Rendre le panel admin robuste face aux listes, dates et pannes.
- `d101bee` 2026-10-03 fix(security): durcir auth, chiffrement des liens et accès du panel
- `0e5d92c` 2026-10-03 fix(worker): séparer activation et lien M3U
- `fc9acfa` 2026-10-03 fix(liaison): présence commise avant la réponse, panel à 2 s
- `0d2de7a` 2026-10-03 Ajoute un parcours local panel, Worker et box simulée.
- `d689224` 2026-09-28 Merge pull request #43 from manzilionellm-dotcom/claude/panel-vip-urgent
- `6e25b4a` 2026-09-28 fix(admin-panel): corrections urgentes fluidité + navigation + empty states FR
- `51f4486` 2026-09-27 feat(zuno): /activer S+M2 panel parity + app-only « pas de chaînes » (#42)
- `eb6b3e9` 2026-09-27 chore(zuno): brand Zuno-only + official AAB download (await Lionel OK) (#41)
- `ff0d7c7` 2026-09-27 feat(zuno): P0 VIP commerce — Forfaits 9,99€/15€ + Concierge WA + Activer
- `a3fe038` 2026-09-27 ci: ajoute le prompt système Mobile Guard
- `5ea51de` 2026-09-27 ci: ajoute le workflow Grok Bot (Mobile Guard)

## Annexe B — commits seulement sur l'app (149)

- `6982934` 2026-10-05 Passation : essais gratuits en ligne, mise à jour Windows, box #155
- `f5971b7` 2026-10-05 Zuno PC : mise à jour dans l'app (manifeste zuno-windows, installeur vérifié, relance automatique)
- `c99e76a` 2026-10-05 Passation : interrupteur allumé/éteint en production, box #154 réunie (WebSocket + interrupteur)
- `3d3bb3e` 2026-10-05 Box : interrupteur allumé / éteint du panel (liste masquée ou réaffichée sans retéléchargement)
- `23adc60` 2026-10-05 Box : pastille « Mise à jour… » dès qu'une liste du panel se charge, durée réelle dans la boîte noire
- `e646e5a` 2026-10-05 Fusion de cursor/canal-temps-reel-box-c1d5 : WebSocket panel → box (travail de l'autre ingénieur)
- `3aca58d` 2026-10-05 Passation : canal temps réel en production et écran Activation à distance (5 octobre)
- `4abe4a9` 2026-10-04 Box : WebSocket panel → listes, repli sur l'attente longue.
- `74f46f6` 2026-10-04 Passation : comment le panel, le Worker et l'app box sont reliés (état vérifié au 4 octobre)
- `3b9d9f4` 2026-10-04 Audit : panel mis en ligne (bouton Supprimer par liste, MAC sans MK:), Worker non redéployé
- `ab913c6` 2026-10-04 Audit : build #152 vérifié (107-test.152, canal test, version.json de test cohérent), releases clients inchangées
- `53d5944` 2026-10-04 Bouton Mise à jour : dernier build vu par la box de test, téléchargement lent toléré, autorisation d'installer guidée ; numéro propre à chaque build de test
- `d3e24d3` 2026-10-04 MAC affichée sans « MK: » sur la box ; patch panel (bouton Supprimer par liste, MAC complétée)
- `827d38b` 2026-10-04 Audit : build #151 vérifié (AAB minSdk 24 pour Play, APK box minSdk 21), releases clients inchangées
- `6bf1680` 2026-10-04 AAB Google Play en minSdk 24 (protection automatique Play), APK box inchangé en 21
- `236aad7` 2026-10-04 Audit : build #150 (APK + AAB Google Play) et Windows #12 vérifiés, releases clients inchangées
- `fb3df3e` 2026-10-04 AAB Google Play attaché à la release de test ; build Windows sur branche ccr sans publication ; manifeste tablettes/Wi-Fi
- `d030bee` 2026-10-04 Audit : build de test #149 vérifié (SHA-256, versionCode, certificat), release clients inchangée
- `8956ae8` 2026-10-04 Cartes du panel sur l'accueil box : annonce, favori du jour, bannières (lecteur /api/banners)
- `e698de2` 2026-10-04 Guide Xtream apparié et importé en isolate ; historique « regardé » après 20 s ; reprise au démarrage dans toute la liste
- `1050c92` 2026-10-04 Panel → box : source importée tout de suite quand la box n'a aucune chaîne ; deux grands QR (WhatsApp + Mon espace) à l'activation et sur le Direct vide
- `1b5a855` 2026-10-04 Lecteur : copie de dernière image noire rejetée et retirée à la première trame ; essai « Sortie : 48 kHz » (défaut coupé)
- `f39470f` 2026-10-04 docs : rapport d'audit de production Zuno TV (octobre 2026)
- `4d87ee9` 2026-10-04 Audit production Zuno TV : journal expurgé et fsync regroupé, EPG borné et sans doublon, listes atomiques, garde de synchro sous le lecteur, télécommande
- `dac20f2` 2026-10-03 NativeVideoView : imports en double retirés (Format, DecoderReuseEvaluation)
- `a1e5701` 2026-10-03 Titre « Ajouter ma source » via la traduction, tests accordés
- `c2c8845` 2026-10-03 Ajouter ma source : titre de nouveau traduit (tvAddListTitle)
- `2471156` 2026-10-03 Fusionne connexion ouverte et arrêt du son hors app.
- `b16d41b` 2026-10-03 Affiche un QR sur l'accueil TV vide pour saisir la source au téléphone.
- `dd98380` 2026-10-03 Retire le catalogue de serveurs : la source se saisit librement.
- `eec0b5b` 2026-10-03 Le panel affiche la boîte noire d'une box à partir de sa MAC.
- `de26d3b` 2026-10-03 Home : le son s'arrête dans onPause, rien ne rouvre dehors
- `474969c` 2026-10-02 Relance le build : le premier envoi n'avait aucun commit nouveau
- `b3317af` 2026-10-02 Mesure le chemin audio, la phase gauche/droite, et un son témoin
- `1f2b4d5` 2026-10-02 Build : variante « Zuno essai » installable à côté d'un Zuno existant
- `84af59e` 2026-10-01 Publication test : version.json (sha256, size) à côté de l'APK sur zuno-tv-test
- `78e49b0` 2026-10-01 Lecture du compteur Zuno sans clientUid au compile
- `9e9a13d` 2026-10-01 Sonde spectre branchée dès l'allumage, et trace du volume
- `607cc3d` 2026-10-01 Un seul AudioTrack au zap et au retour dans l'app
- `881192a` 2026-10-01 Son « dans un trou » : focus audio géré par Zuno, aucune lecture hors de l'app
- `ea646cc` 2026-10-01 Diagnostic du son : la fiche défile à la télécommande, chiffres du chevauchement en tête
- `a79c198` 2026-10-01 Repli AAC par chaîne : le son « radio » ne revient plus sur les chaînes déjà vues
- `0171d8e` 2026-10-01 Mesure le spectre après chaque étage audio, sans changer le son.
- `99b9a53` 2026-10-01 Ajoute la publication de l'APK téléphone 7 MOTION sur 7motion-test
- `67043b7` 2026-10-01 Propose l'essai du décodeur AAC de la box, coupé par défaut.
- `724a0a5` 2026-10-01 Ajoute un diagnostic audio local, sans changer le son par défaut.
- `febaef2` 2026-09-30 Ajoute la publication d'un APK déjà construit sur zuno-tv-test
- `7b904c7` 2026-09-30 Note les mesures panel de la 106, séparées prouvé et pas prouvé.
- `644212c` 2026-09-30 Retire les imports en double qui empêchent de compiler.
- `bd910b5` 2026-09-30 Note que la 106 inclut le correctif Media3 e6f8a3fe.
- `dfceae4` 2026-09-30 Corrige la compilation : Media3 n'accepte pas un écouteur de trames null.
- `a6e2571` 2026-09-30 Zuno 106 : plancher de version et note de ce qui est prouvé.
- `2eccc17` 2026-09-30 Reprend Zuno 105 : diagnostic du son et retour sans flash.
- `b2c863b` 2026-09-30 Fusionne le panel instantané (PR #57).
- `a6615d6` 2026-09-30 Fusionne Zuno intelligent (PR #56) : émissions suivies.
- `a69e032` 2026-09-30 Fusionne le cache catalogue (PR #59).
- `0175370` 2026-09-30 Fusionne Zuno image (PR #61) : repli décodeur et fréquence d'écran.
- `1a72e51` 2026-09-30 Fusionne Zuno stabilité (PR #60) : reconnexion 1/2/4/8 s et reprise des films.
- `fa0d44f` 2026-09-30 Zuno image : repli décodeur, fréquence d'écran, FFmpeg vidéo seulement s'il existe.
- `004692c` 2026-09-30 Zuno : reconnexion à attente croissante, dernière image gardée, reprise des films.
- `7634aaa` 2026-09-30 Garde le dernier catalogue films et séries sur la box.
- `fb784ab` 2026-09-30 Zuno 105 (test) : diagnostic du son dans la boîte noire + retour sans flash
- `04ba4b7` 2026-09-30 Zuno : preuves chronométrées du canal panel → box.
- `00b68a4` 2026-09-30 Note de version 104 : ce qui est prouvé, et le test des 20 zaps.
- `4a56d14` 2026-09-30 Zuno 104 : un seul lecteur a le droit de parler au zap.
- `7277b68` 2026-09-30 Zuno : le panel parle à la box tout de suite, et la box accuse réception.
- `7655ae1` 2026-09-30 Apprend les émissions suivies et prévient quand elles passent.
- `519f4ad` 2026-09-30 Zuno 103 : la box suit l'activation et l'effacement de liste en quelques secondes.
- `5e1c465` 2026-09-30 Affiche les sous-titres déjà présents dans la langue de l'app.
- `47fdce3` 2026-09-30 Ajoute les suggestions selon le jour et l'heure.
- `71c816e` 2026-09-30 Ajoute le résumé du guide quand on arrive en retard.
- `45c5da4` 2026-09-30 Fusionne la voix et le guide « ce soir » (PR #52).
- `d401be2` 2026-09-30 Fusionne la télécommande téléphone (PR #51) dans Zuno tout.
- `072e9af` 2026-09-30 Fusionne les profils familiaux (PR #50) dans Zuno tout.
- `01aaf61` 2026-09-30 Zuno : recherche à la voix et guide « ce soir »
- `ed44786` 2026-09-30 Zuno : le téléphone pilote la box sur le Wi-Fi, sans application
- `5d768af` 2026-09-30 Zuno : profils familiaux (jusqu'à 4), sans perdre les données
- `d9c9dc8` 2026-09-30 Ajoute les profils famille, sans mélanger les données de Maison.
- `af073fc` 2026-09-30 Ajoute la recherche à la voix, avec repli si le micro manque.
- `4f56911` 2026-09-30 Ajoute la télécommande téléphone par QR, coupable sans toucher au lecteur.
- `eded2b8` 2026-09-30 Fusionne l'accueil pour revenir (reprise, favoris, rappels).
- `0545f70` 2026-09-30 Fusionne la navigation télécommande (zapping, guide, recherche).
- `1c71fbc` 2026-09-30 Fusionne la fiabilité image et zap sans retirer le repli son FFmpeg.
- `8306a02` 2026-09-30 Fusionne le son HE-AAC (repli FFmpeg) dans Zuno tout.
- `3f1c841` 2026-09-30 Ferme l'accès aux codes IPTV par la seule MAC.
- `5c30f6e` 2026-09-30 Zuno TV : accueil pour revenir sans piège
- `7a179be` 2026-09-30 Zuno box : image stable et zap qui ne bloque pas une chaîne
- `26dac8b` 2026-09-30 Zuno TV : zapping, guide et recherche plus lisibles à la télécommande
- `3835c51` 2026-09-30 Zuno box : son HE-AAC avec repli si FFmpeg bloque
- `d56de43` 2026-09-30 Ajoute l'audit Zuno : risques, valeur client, feuille de route.
- `867bd7a` 2026-09-29 Zuno box : secours du direct quand le serveur ne sert plus les chaînes
- `2d70ba2` 2026-09-29 Stabilité : canal « box de test » avant toute publication clients
- `8ae2e20` 2026-09-29 Zuno box : retour au lecteur v98 (chaînes bloquées sur le chargement)
- `b20c61c` 2026-09-28 Zuno box : menu Audio et sous-titres qui défile jusqu'au bout
- `8c95349` 2026-09-28 Zuno box : qualité adaptative façon Netflix + anti-saccade
- `0a36478` 2026-09-28 Zuno box : son « qualité cinéma » (fin du son « vieille radio »)
- `054d706` 2026-09-27 Site : adresse publique zuno.7themotion.com (liens canoniques, sitemap, robots, raccourci /apk affiché)
- `79bc2c4` 2026-09-27 ci : relance de la création du CNAME zuno
- `a327cf7` 2026-09-27 ci : créer le CNAME zuno.7themotion.com → Vercel (une seule ligne, idempotent)
- `af9676e` 2026-09-27 Site : relais serveur pour « Activer ma liste », 16 langues finalisées, export Pages vérifié
- `4bc28f9` 2026-09-27 Site : swahili (version intermédiaire)
- `4fe7efb` 2026-09-27 Site : traductions en cours (es, it, ar, tr, ru, zh, hi — versions intermédiaires valides)
- `8a303c7` 2026-09-27 Site : traductions danois, norvégien, suédois
- `d6d98d8` 2026-09-27 Site : traductions anglais, allemand, néerlandais
- `757d184` 2026-09-27 Site : 16 langues automatiques (sans choix, adresse inchangée) + page « Activer ma liste »
- `f7f9b7f` 2026-09-27 Site : page « Télécharger » Zuno (box, PC, Google Play) + raccourcis /apk et /pc
- `a7a6de6` 2026-09-27 Zuno v97 : « Télécharger la saison » façon Netflix (box + PC)
- `1c9d8d0` 2026-09-27 Zuno PC 96 : même app que la box v96 ; recherche Films / Séries sur 150 000 titres
- `f0fc83f` 2026-09-27 Zuno TV v96 : Films / Séries affichent toutes les catégories
- `47fb819` 2026-09-27 Zuno TV v95 : Films / Séries chargés en entier (fin du « ça ne prend que la moitié »)
- `cb2b6b0` 2026-09-27 Zuno TV v94 : Réglages en anneau 3D (carrousel étapes 3 et 4)
- `bf320e1` 2026-09-27 test : m3u_parser_test.dart remis à l'identique (reformatage involontaire)
- `d8b9a9c` 2026-09-27 Zuno TV v93 : sources identifiées, multi-sources actives, Redémarrer et mises à jour qui chargent vraiment le neuf
- `4b1c0af` 2026-09-27 Carrousel 3D Zuno — étape 2 : anneau 3D et affiches premium
- `707d53a` 2026-09-27 Carrousel 3D Zuno — étape 1 : squelette et structure
- `817c185` 2026-09-26 ci(pc): compiler sous PowerShell (la variable CL était déformée par Git Bash)
- `3b71c52` 2026-09-26 ci(pc): épingler windows-2022 (Visual Studio 2022) pour le build Windows
- `00994d4` 2026-09-26 ci(pc): déclencher le build Windows au push des fichiers propres au PC
- `01ff1b1` 2026-09-26 feat(pc): Zuno pour Windows — même app, même design que la box
- `604c906` 2026-09-26 fix(tv): Retour un à un, enregistrements dans Réglages, AAB Google Play TV
- `63546f1` 2026-09-26 fix(ci): déclarer kBoxMinSdk après les import du build.gradle.kts
- `394c449` 2026-09-26 fix(tv): APK complet pour les box x86_64 (Intel/AMD)
- `837ca60` 2026-09-26 fix(tv): Zuno s'installe sur toutes les box (signature des clients + Android 5)
- `418d47e` 2026-09-26 feat(tv): Cinéma — Films et Séries façon Netflix (reprise, audio/sous-titres, téléchargements)
- `6ca5309` 2026-09-26 feat(tv): 8 nouvelles langues (de, it, pt, nl, tr, ru, zh, hi) + 13 libellés manquants
- `6baa7fc` 2026-09-25 feat(tv): tout le texte de l'app box traduit, langue de la TV suivie automatiquement
- `d533a87` 2026-09-25 ci(tv): numéro de version visible 88, 89, 90… à chaque publication
- `ff7c9eb` 2026-09-25 feat(tv): bouton « Mise à jour » fonctionnel dans les Réglages
- `96d2eb7` 2026-09-25 fix(tv): lecteur plein écran sans Material → textes en style d'erreur (jaune)
- `f57bae5` 2026-09-25 feat(tv): progression visible pendant « Connexion… » (octets, chaînes trouvées, enregistrées)
- `992be74` 2026-09-25 feat(tv): boîte noire (enregistreur de vol) + import Xtream à mémoire bornée
- `0d976e9` 2026-09-25 docs: prompt de passation Zuno (stabilité, fluidité, boîte noire, enregistrement)
- `56a4d76` 2026-09-25 perf(tv): défilement sans vue native + import M3U 100 % hors du fil UI
- `52d39d1` 2026-09-25 fix(tv): plus de gel/fermeture de Direct sur grosse liste
- `1dbd9e8` 2026-09-25 feat(tv): synchronisation automatique des listes (façon TiviMate)
- `aca0034` 2026-09-25 feat(panel): 6 sources par appareil (ex-trio) + snapshot du Worker prod
- `b417326` 2026-09-25 perf(tv): fluidité grosses listes + fusion de toutes les playlists
- `ccd0967` 2026-09-25 feat(tv): source-push direct depuis le panel sur l'accueil
- `40fe38a` 2026-09-25 feat(tv): nouvelle marque Zuno — logo or, thème noir & or, release zuno-tv
- `e104d36` 2026-09-25 fix(tv): appel du helper statique _parseName depuis la ligne de chaîne
- `7722b88` 2026-09-25 feat(tv): écran Direct en 3 colonnes (catégories · liste · aperçu vidéo + guide)
- `5032854` 2026-09-25 feat(tv): fond plein écran de marque sur l'accueil box
- `b8af254` 2026-09-25 feat(tv): accueil « box » à tuiles (Direct/Films/Séries/Serveur/Réglages)
- `01d4140` 2026-09-25 fix(tv): fenêtre « Quitter » sans double soulignement jaune
- `4f59ae3` 2026-09-24 ci(tv): publier l'app Flutter sur une release séparée 7motion-tv-panel
- `de2af21` 2026-09-24 feat(tv): entrée par connexion Xtream + M3U sur le gate, licence panel conservée
- `4014b6b` 2026-09-24 ci(tv): corriger le contrôle Leanback de l'APK (aapt affiche leanback-launchable-activity)
- `b6b2e50` 2026-09-24 feat(tv): thème sombre 7 MOTION « Maison Noir » (charbon, braise, ivoire)
- `14cbe94` 2026-09-24 feat(tv): relier 7 MOTION TV au panel admin — build Flutter publié sur la release 7motion-tv
