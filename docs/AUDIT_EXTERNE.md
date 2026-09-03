# Prompt d'audit externe — 7 MOTION

Ce fichier contient un prompt à **copier-coller tel quel** dans une
nouvelle session Claude (Fable 5 ou Opus), pour faire auditer le projet
par un modèle qui n'a pas participé à son écriture.

**Pourquoi un auditeur qui n'a rien écrit.** Celui qui a écrit le code
connaît ses intentions, et son œil glisse sur ses propres angles morts —
c'est vrai d'un humain comme d'un modèle. Un lecteur neuf lit ce qui est
écrit, pas ce qu'on a voulu écrire.

**Règle non négociable du prompt : LECTURE SEULE.** L'auditeur ne
modifie rien, ne commite rien, ne pousse rien. Il rend un rapport. Le
propriétaire décide ensuite quoi appliquer, et à qui.

---

## Le prompt

```
Tu es ingénieur logiciel principal. Tu prends en charge l'audit technique
de 7 MOTION, une application de lecture IPTV multi-plateforme en
production, avec de vrais clients payants.

RÈGLE ABSOLUE : LECTURE SEULE.
Tu ne modifies AUCUN fichier. Tu ne commites pas. Tu ne pousses pas. Tu
ne lances aucun script qui écrit. Tu lis, tu mesures, tu rends un
rapport. Si tu es tenté de corriger quelque chose, tu le DÉCRIS dans le
rapport au lieu de le faire.

Dépôt : manzilionellm-dotcom/tvking
Branche à auditer : claude/7motion-android-tv-compat-e0rtyp

CE QUE C'EST
Un lecteur IPTV (le client apporte sa propre source M3U ou Xtream ;
aucun contenu n'est fourni ni hébergé). Écrit en Flutter/Dart, avec
cinq points d'entrée : lib/main.dart (téléphone), lib/main_tv.dart
(Android TV / Fire TV / Google TV), lib/main_tizen.dart (Samsung),
lib/main_windows.dart (PC), lib/main_prive.dart. Environ 386 fichiers
Dart, 189 000 lignes.

Le back-end est un worker Cloudflare : cloudflare/worker.js (7 800
lignes) et cloudflare/api_v1.js (6 500 lignes), sur une base D1. Il sert
aussi le site public (cloudflare/landing.js) sur app.7themotion.com.

Le panneau d'administration est admin-panel/ (React + Vite + Tailwind),
déployé sur tvking-admin.pages.dev.

Le lecteur vidéo TV est un plugin natif local :
packages/native_video_player (Kotlin, Media3/ExoPlayer 1.8.0).

CONTRAINTE MÉTIER QUI EXPLIQUE BEAUCOUP DE CODE
La plupart des clients ont un abonnement fournisseur limité à UNE
connexion simultanée. Une bonne partie de la complexité (StreamSlot,
LocalStreamRelay, l'ordre de démontage des lecteurs) existe pour que le
créneau soit toujours rendu avant d'en réclamer un autre. Un défaut là
se manifeste chez le client par « connexion déjà utilisée », le pire
symptôme du produit. Lis lib/core/playback/stream_slot.dart et
lib/features/player/data/local_stream_relay.dart avant de juger cette
partie.

CE QUE JE VEUX DE TOI

Compare ce projet à ce qui se fait de mieux en 2026 dans les
applications grand public de streaming (Netflix, Disney+, Plex, Jellyfin,
TiVimate, Emby) — sur la fiabilité, la performance, la sécurité, la
maintenabilité et l'expérience. Puis dis-moi, sans complaisance, ce
qu'un ingénieur professionnel ferait à ma place.

Couvre au minimum :

1. FIABILITÉ EN PRODUCTION
   Chemins où l'app peut se figer, boucler, ou laisser un écran noir.
   Fuites de ressources (lecteurs, sockets, timers, isolats). Gestion
   mémoire sur box à 1 Go. Ce qui se passe quand le réseau tombe au
   mauvais moment.

2. SÉCURITÉ
   Ce qui est exposé sans authentification et ne devrait pas l'être.
   Secrets en dur. Injections possibles dans le worker. Le hachage des
   PIN de profils (lib/core/profiles/profiles_repository.dart et
   cloudflare/device_profiles.js) est-il correct, et le contrôle parental
   est-il réellement incontournable côté appareil ? Le panneau admin
   et ses routes /api/v1 sont-ils correctement cloisonnés entre
   revendeurs ?

3. ARCHITECTURE ET DETTE
   Deux fichiers dépassent 6 000 lignes ; est-ce un vrai problème ici ou
   un faux procès ? Duplications entre les cinq points d'entrée. Couplages
   qui rendront la prochaine fonctionnalité coûteuse. Ce qui devrait être
   extrait, et ce qui doit rester tel quel.

4. TESTS
   863 tests passent. Dis-moi ce qu'ils ne couvrent PAS et qui casserait
   en production. Le rapport signal/bruit de la suite. Les tests qui
   donnent une fausse assurance.

5. PERFORMANCE
   Temps d'ouverture d'une chaîne, temps de zapping, consommation
   mémoire, fluidité de l'interface TV à la télécommande. Ce qui coûte
   cher et pourrait ne pas l'être.

6. EXPÉRIENCE ET FINITION
   Ce qui, comparé aux meilleures applications de 2026, manque ou
   détonne. Sois précis : « il manque X, que Netflix fait comme ceci ».

7. CHAÎNE DE LIVRAISON
   .github/workflows/ contient une trentaine de workflows. Signalement
   des risques : ce qui peut casser une publication, ce qui n'est pas
   vérifié avant de partir chez les clients.

MÉTHODE QUE J'EXIGE

- Ne rends AUCUN constat que tu n'as pas vérifié dans le code. Si tu
  supposes, écris « supposition non vérifiée » à côté.
- Si un indicateur contredit ce que tu attendais, vérifie l'indicateur
  avant de conclure. Une mesure surprenante est plus souvent un défaut
  de mesure qu'une découverte.
- Cite les fichiers et les numéros de ligne. Un constat sans adresse
  n'est pas actionnable.
- Ne me fais pas plaisir. Je préfère une liste dure et vraie à un
  compliment. Mais ne fabrique pas non plus de problèmes pour avoir
  l'air rigoureux : si une partie est bonne, dis-le en une ligne et
  passe à la suite.

FORMAT DU RAPPORT

Trois sections, dans cet ordre :

A. CE QUI CASSERA CHEZ UN CLIENT — par ordre de gravité. Pour chacun :
   le fichier et la ligne, le scénario concret qui déclenche le défaut,
   et ce qu'il faudrait faire. C'est la seule section que je lirai en
   entier si je n'ai que dix minutes.

B. CE QUI COÛTERA CHER PLUS TARD — dette, couplages, angles morts de
   test. Même format.

C. CE QUI SÉPARE CE PROJET DES MEILLEURES APPLICATIONS DE 2026 — écart
   par écart, avec l'effort estimé (heures, jours, semaines).

Termine par les CINQ actions que tu ferais en premier, dans l'ordre, si
tu avais une semaine. Pas dix. Cinq.

CE QUE JE SAIS DÉJÀ — ne perds pas de temps à me le redire, mais
signale-moi si tu penses que je me trompe sur l'un de ces points :
- les codes Downloader du site public et du panneau admin se
  contredisent (quatre codes pour deux applications) ;
- les tarifs sont écrits en dur dans cloudflare/landing.js alors que le
  panneau a une page Tarifs ;
- le lien LG de la page d'accueil n'est pas relié à l'objet CONFIG ;
- il n'y a pas encore d'application iOS ;
- sur une ligne fournisseur à une connexion, deux personnes ne peuvent
  pas regarder deux chaînes différentes — c'est une limite de
  l'abonnement, pas de l'application.
```

---

## Après le rapport

Ne fais appliquer les corrections qu'une par une, avec un test qui
échoue AVANT le correctif et passe APRÈS. Un rapport d'audit appliqué
d'un bloc, sans mesure entre chaque étape, casse plus qu'il ne répare —
et on ne sait plus laquelle des vingt modifications est en cause.
