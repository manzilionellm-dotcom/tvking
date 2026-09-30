# 7 Motion téléphone — lot 106 (image, stabilité, catalogue, panel, football)

Branche : `claude/motion-mobile-106`. Base : `claude/retour-13sept-notifications` @ `32d7280a`.
Rien n'est publié. `ci/release_tag.sh phone claude/motion-mobile-106` renvoie `latest` (stderr : l'app téléphone lit `phone-latest`, pas `latest`). L'étape « Publier l'APK téléphone » du workflow ne part que si `REL_TAG == phone-latest`. Le Worker n'est pas déployé. `main`, `phone-latest`, `zuno-tv`, `zuno-tv-test` et le 4K Player ne sont pas touchés.

Le garde-fou `guard_no_rollback.sh` ne s'exécute plus que lorsque le canal de la branche est vraiment `phone-latest`. Sur `claude/retour-13sept-notifications` il continue de tourner. Sur cette branche il ne bloque plus un build qui ne dépose aucun APK.

## PROUVÉ — machine de développement, pas un téléphone

Flutter **3.47.5** (stable), Dart **3.13.4**.

- `flutter analyze --no-fatal-infos --no-fatal-warnings` : code de sortie **0**. **303** signalements, **0** erreur, **13** avertissements, **290** infos (le gros est antérieur à ce lot).
- `flutter test` (suite complète, y compris le test de chronométrage) : **1433** réussis, **36** ignorés, **0** échec, environ **71 s**.
- Fichiers ajoutés, relancés ensuite à part, tous verts :
  - `test/features/player/motion_player_plan_test.dart`
  - `test/features/vod/resume_and_catalog_test.dart`
  - `test/features/playlists/panel_source_decision_test.dart`
  - `test/features/sports/live_alert_plan_test.dart`
  - `test/core/security/update_and_posture_test.dart`
  - plus `goal_sentinel_test.dart` (période **45 s** inchangée) et `live_scores_test.dart` (premier tour muet, deux buts détectés). Ces fichiers font partie des 1433.

Décisions mesurées dans ces tests, sans ouvrir de flux :

- Délais de réouverture : 1000, 2000, 4000, 8000 ms. Une attente déjà posée n'en arme pas une autre. Au 9e essai, on abandonne.
- Moteur : matériel → logiciel. Sans FFmpeg vidéo dans le binaire, le cran suivant revient au matériel et le dit. `hwdec` matériel = `auto-safe`, logiciel = `no`.
- Un signal réseau ne change pas de moteur. Un échec matériel ouvre le logiciel une fois, puis on abandonne l'échelle.
- Vingt prises de son : un seul propriétaire, les dix-neuf autres sont coupés. Un jeton de session plus ancien ne compte plus.
- Reprise : 29 s → 0. 60 s → 55 s. « Depuis le début » ignore la mémoire.
- Catalogue : une liste entrante vide garde la mémoire, puis le disque. Une liste non vide remplace.
- Panel : `sources: []` sans objet `source` est un effacement. On retire l'empreinte provisionnée, pas une autre liste. Un ordre sans id ou d'un type inconnu est refusé.
- Football, décision pure : première photo muette. Photo vide n'arme pas la baseline. Deux buts dans la même photo sont tous les deux sortis. La fin n'est annoncée qu'après deux absences.
- Chrono local (`LiveAlertPlan`, 1000 photos de 40 matchs) : **27628 µs** sur cette VM, sous le plafond de 200 ms du test. C'est le temps de **décider**, pas le temps qu'un but met à arriver.

## Ce que le code fait, et ce que les tests ne jouent pas

Image. Le bouton « Moteur image » est dans la feuille de réglages. Le lecteur pose `hwdec` depuis `hwdecFor`. Sur erreur classée décodeur, ou image noire au bout du délai de démarrage, ou gel, on avance d'un cran (matériel → logiciel) puis on ré-ouvre. Le réseau ne change pas de moteur.

Stabilité. À chaque ouverture le lecteur prend le bail et met le volume à 0. Le volume 100 ne revient que si le jeton est encore le courant, à la première preuve de lecture. La pub de démarrage s'enregistre sur le même bail. Les réouvertures silencieuses (EOF live, gel) passent par `ReconnectGate`.

Catalogue. Réseau vide : on ne sauvegarde pas le vide par-dessus le disque.

Panel. Compatible avec le Worker **déjà en ligne** : `GET /api/device-source`, ordres, `POST /api/device-orders/ack`, WebSocket existant. Au retour au premier plan : resync des sources (sauf mode sans échec) et de la config (annonces, thème, messages déjà relus). Pas de route `/api/box/wait`.

Football. La source reste `GET /api/sports/live` (cache serveur 45 s, amont TheSportsDB annoncé ~2 min dans le commentaire du service). La clé n'est pas dans l'app. Tant que le processus vit, chaque but digne d'alerte est notifié (id stable `970000 + hash % 1000`, un second but remplace le premier). Coup d'envoi et fin passent par le canal général, pas par le son « wouaaah ». Au retour au premier plan, si la fenêtre (5 min avant, 3 h après) est ouverte ou si l'écran Sport tourne, on relit tout de suite.

## PAS PROUVÉ — téléphone réel

Aucun APK n'a été installé sur un téléphone dans ce travail. À faire à la main, dans cet ordre, sur un build de **cette** branche (pas `phone-latest`) :

1. Ouvrir une chaîne. Vérifier que l'image part (matériel). Couper le Wi-Fi 5 secondes, le remettre : la reprise attend environ 1 s puis 2 s, sans deuxième spinner empilé, et le son ne double pas avec la pub si elle jouait encore.
2. Dans les réglages du lecteur, passer Matériel → Logiciel. Un message dit que FFmpeg vidéo n'est pas dans cette version si on insiste. La chaîne repart.
3. Lancer un film déjà vu au-delà d'une minute : il reprend environ 5 secondes avant le point sauvé.
4. Couper le réseau, rouvrir Films : la liste d'avant est encore là.
5. Depuis le panel, vider la liste de cet appareil : elle disparaît dans l'app sans attendre une minute, et une liste ajoutée à la main sur le téléphone reste. Déposer une annonce : elle s'affiche, l'app accuse réception.
6. Suivre un match dans sa fenêtre, laisser l'app ouverte : un but peut mettre jusqu'au cache de 45 s plus le retard de la source (~2 min). Tuer l'app : **aucun** but n'arrive. Ce n'est pas un push.

Le lien du run GitHub Actions de cette branche est ajouté ici dès qu'il a un état réel. Tant qu'il n'est pas vert, ce paragraphe reste vide de lien inventé.

## Limites

- Recycler libmpv peut encore faire un flash noir. Le test `coverWithLoader` prouve la décision, pas l'image à l'écran.
- Le plafond amont du football ne se raccourcit pas sans changer le Worker déployé. On ne le déploie pas.
- Une app tuée par Android ne reçoit pas les buts. Pas de service de premier plan ajouté pour ça (permissions Play, batterie).
- La pub de démarrage lue au lancement suivant, pas au milieu d'une session déjà ouverte, reste la règle d'avant si le dépôt de la pub ne la réaffiche pas tout de suite.
