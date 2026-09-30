# Audit mobile 7 Motion — téléphone face à la box Zuno 106

Branche de travail : `claude/motion-mobile-106`, partie de `32d7280a` (`claude/retour-13sept-notifications`).
La box de référence est `origin/claude/zuno-106` (PR #62). Le téléphone de cette branche vit à la racine (`lib/`), pas dans `android-app/`.

On a porté les **décisions** (quand changer de moteur, quand ré-ouvrir, quoi garder). On n'a pas copié ExoPlayer ni le lecteur Kotlin de la box : le téléphone joue avec libmpv (`media_kit`).

## Même idée, moteur différent

| Sujet | Box Zuno 106 | Téléphone avant | Téléphone maintenant |
| --- | --- | --- | --- |
| Image | ExoPlayer, matériel puis logiciel, FFmpeg vidéo s'il est dans le binaire | libmpv, `hwdec=auto-safe` ou `no` selon un interrupteur | Même échelle de noms. Matériel = `auto-safe`. Logiciel = `hwdec=no` (libmpv décode). FFmpeg vidéo séparé : **absent** de cet APK, le bouton le dit et revient au matériel |
| Reconnexion | 1 / 2 / 4 / 8 s, 8 essais silencieux, pas deux attentes en même temps | EOF à 800 ms, chien de garde ~15 s, plafond 4 | Délais 1 / 2 / 4 / 8 s, plafond 8, une seule attente armée |
| Son exclusif | Jeton de session, un seul lecteur audible | Pub de démarrage et film peuvent chacun avoir un `Player` | Bail partagé : celui qui prend le son coupe les autres. Un jeton périmé ne remonte pas le volume |
| Reprise film | position mémorisée − 5 s, plancher 0, moins de 30 s = début | saut à la position exacte si > 5 s | `ResumeStart` : − 5 s, moins de 30 s = début |
| Catalogue | ne jamais remplacer un catalogue plein par une réponse vide | un `forceRefresh` mémoire vide + réseau vide pouvait rendre une liste vide | `keepPreviousWhenEmpty` : mémoire, puis disque. On n'écrit pas le vide |
| Panel | WebSocket + routes box propres à Zuno (`/api/box/wait`) | WebSocket actuel, ACK `sync` / `message`, sondage sources 60 s. Un `sources: []` ne retirait pas les listes posées par le panel | Même Worker, aucune route nouvelle. Effacement explicite = tableau `sources` vide sans objet `source`. On retire seulement les listes que le panel avait posées |
| Football | (hors périmètre 106 TV) | sondage 45 s, un seul but annoncé par photo | tous les buts dignes d'alerte, plus coup d'envoi et fin (deux absences) |

## Ce qui n'est pas le même produit

- Le téléphone n'a pas de décodeur vidéo FFmpeg à part de libmpv. Inventer un troisième moteur aurait été faux.
- Le recyclage du `Player` libmpv (une instance neuve à chaque ouverture, pour ne pas fuir les connexions) peut encore noircir la surface. La box évite de détacher sa Surface. On ne couvre plus une image déjà vue par le spinner quand on ré-ouvre **la même** adresse. Ça ne prouve pas l'absence de flash noir.
- Les flux IPTV restent souvent en `http://`. Les forcer en HTTPS casserait les fournisseurs. Le panel et le Worker sont en HTTPS (`app.7themotion.com`, repli `workers.dev`).
- Pas de notification push tant que le processus est tué. Il n'y a pas de FCM dans cette app, et on ne déploie pas le Worker pour en ajouter.

## Bugs constatés dans le code d'avant, et le correctif

1. **Catalogue.** `forceRefresh` avec mémoire vide allait au réseau et, si la réponse était vide, renvoyait vide sans relire le disque. Corrigé dans `vod_repository.dart` et `series_repository.dart`.
2. **Buts.** `_detectGoals` s'arrêtait au premier but digne d'alerte alors que `_goalsIn` avait déjà mémorisé les autres totaux. Les autres buts de la même photo ne revenaient jamais. Corrigé : on annonce chaque but digne d'alerte.
3. **Listes du panel.** `sources: []` sans objet `source` retournait `noSource` et gardait les playlists locales, y compris celles posées par le panel. Corrigé : on retire les empreintes provisionnées, pas une liste ajoutée à la main.
4. **Reprise.** Le téléphone cherchait la position exacte. Corrigé : − 5 s, jamais sous 0, sous 30 s on repart du début.
5. **Retour au premier plan.** La licence était relue, pas les sources ni la config. Corrigé dans `RealtimeSyncService` (sources sauf mode sans échec, config). Les scores sont relus si l'écran Sport est ouvert ou si la fenêtre d'alerte est ouverte.
