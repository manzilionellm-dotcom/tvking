# Playbook engagement & rétention — « rendre les gens accros »

> Objectif : transformer 7 MOTION en **habitude quotidienne**. Ce
> document est une stratégie priorisée, ancrée sur ce que l'app a DÉJÀ et
> sur ce qu'il faut ajouter. Engagement « accro » mais **respectueux** :
> on crée de la valeur réelle (retrouver vite ce qu'on aime), pas des
> pièges. C'est ce qui fait revenir ET garde une bonne réputation.

---

## 1. La science en 1 minute — le « Hook Model »

Une habitude se crée en bouclant 4 étapes (Nir Eyal) :

1. **Déclencheur** : externe (notification) puis interne (ennui → « je
   regarde un truc »).
2. **Action** : le geste le plus simple possible pour obtenir la récompense
   (ouvrir → ça joue tout de suite).
3. **Récompense variable** : du nouveau/imprévu à chaque fois (nouveautés,
   « en direct maintenant », reprises).
4. **Investissement** : l'utilisateur dépose quelque chose (favoris,
   reprise, profil) → l'app devient « la sienne » et le prochain
   déclencheur est plus fort.

**Le plus grand levier de rétention pour une app vidéo = le DÉCLENCHEUR
(notifications/rappels) + une ACTION sans friction (lecture instantanée).**
C'est précisément ce qui manque aujourd'hui.

---

## 2. Métriques à suivre (sinon on pilote à l'aveugle)

- **North star** : minutes regardées par utilisateur actif / semaine.
- **Rétention** : J1 / J7 / J30 (le J7 est le juge de paix de l'habitude).
- **DAU/WAU** (stickiness = DAU/WAU ; viser > 50 % pour une app TV).
- **Time-to-first-frame** (du tap à l'image — viser < 2 s).
- **Sessions/jour** et **durée de session**.
- **Taux d'activation** : % qui regardent dans les 5 min après install.

---

## 3. Ce que 7 MOTION a DÉJÀ (audit du code — fondations solides)

L'app est **déjà avancée** sur l'engagement :

✅ Zapping vertical façon feed · ✅ Favoris · ✅ « Récemment regardé »
(rangées sur l'accueil mobile + TV) · ✅ **Bannière « Reprendre »**
(`resume_banner.dart`, dernière session < 60 min) · ✅ **Personnalisation
par affinité de genre** (`affinity_service.dart` : réordonne les rangées
selon ce qui est *réellement* regardé) · ✅ **Adaptation horaire**
(`time_of_day_service.dart` : remonte le bon genre à la bonne heure) ·
✅ Guide EPG + Catch-up · ✅ Cast / Android TV / Fire TV · ✅ Enregistrement
· ✅ Picture-in-Picture · ✅ Recherche + recherches récentes · ✅ Rangées
d'affiches premium.

**Vrais manques, par impact décroissant :**
1. **Notifications / rappels** (déclencheur de retour) — *absent* (aucun
   plugin de notification). ⇒ levier n°1 restant.
2. **Auto-play de l'épisode suivant** (binge séries) — *absent*.
3. **Reprise par POSITION pour la VOD** — la reprise actuelle est par
   *session/chaîne* (live), pas une reprise « à la minute près » des films.
4. **Vitesse perçue** : skeleton loaders / transitions (polish).

---

## 4. Le plan, priorisé par ROI

### 🥇 Tier 1 — le plus rentable (à faire en premier)

> Note d'audit : l'accueil personnalisé (#3) et la reprise (#2) existent
> DÉJÀ en partie (bannière « Reprendre », rangées « récemment regardé »,
> affinité de genre, adaptation horaire). Les vraies nouveautés à coder
> sont donc surtout **#1 notifications** et **#4 auto-play épisode
> suivant** ; #2/#3 deviennent de l'**amélioration** (reprise par position
> VOD, rangée « Reprendre » dédiée).

**1. Notifications & rappels EPG** — *LE* levier de retour.
- « Ton match commence dans 10 min », « Nouveau contenu dans tes favoris »,
  « Reprends ton film ». Rappel posable depuis le guide (cloche sur un
  programme).
- *Hook :* déclencheur externe n°1 → ramène l'utilisateur tous les jours.
- *Tech :* `flutter_local_notifications` (rappels EPG locaux, sans serveur)
  d'abord ; push distant (FCM) ensuite pour annoncer nouveautés/sport.
- *Effort :* moyen. *Dépendance :* aucune pour les rappels locaux.

**2. « Reprendre la lecture » (resume)** — enclenche le binge.
- Sauvegarde la position de lecture (films/séries) + rangée « Reprendre »
  en haut de l'accueil.
- *Hook :* réduit l'action à zéro (« 1 tap = je reprends là où j'étais »).
- *Tech :* étendre `watch_history` avec une position ms ; rangée d'accueil.
- *Effort :* moyen.

**3. Accueil personnalisé** — récompense variable + investissement.
- Rangées : **Reprendre** · **En direct maintenant** · **Tes favoris** ·
  **Parce que tu as regardé X** · **Récemment ajouté**.
- *Hook :* à chaque ouverture, du neuf et du « pour moi ».
- *Tech :* compose des rangées à partir de favoris + historique + EPG (pas
  besoin d'IA — des règles simples suffisent).
- *Effort :* moyen.

**4. Auto-play de l'épisode suivant** — le moteur du binge des séries.
- Compte à rebours « Épisode suivant dans 5 s » en fin d'épisode.
- *Hook :* supprime la friction entre deux récompenses.
- *Effort :* faible-moyen (séries Xtream surtout).

**5. Lecture quasi-instantanée** — soigne l'ÉTAPE « action ».
- Pré-buffer de la chaîne voisine pendant le zap, time-to-first-frame
  réduit, vignettes instantanées.
- *Hook :* moins d'attente = plus de zaps = plus de temps passé.
- *Effort :* moyen.

### 🥈 Tier 2 — forte valeur

6. **« En direct maintenant » sport/événements** + rappels dédiés.
7. **Badges « Nouveau / Récemment ajouté »** sur les affiches.
8. **Skeleton loaders + transitions fluides** (vitesse perçue = pro).
9. **Multi-profils** (chacun ses favoris/reprises → plus d'investissement).
10. **Recherche vocale** sur TV (télécommande).

### 🥉 Tier 3 — à doser (gamification, avec goût)

11. **Récap hebdo** « Tu as regardé 7 h cette semaine » (rétention douce).
12. **Chaînes tendance** (preuve sociale : « regardé par d'autres »).
13. **Widget écran d'accueil** « Reprendre » (Android).
14. **Série de jours (streak)** — uniquement si pertinent, sans culpabiliser.

---

## 5. Les 3 premiers « quick wins » recommandés

Dans cet ordre, c'est le meilleur retour sur effort :

1. **Rappels EPG locaux** (cloche sur un programme) → déclencheur de retour.
2. **« Reprendre la lecture »** + rangée d'accueil → binge + action zéro-friction.
3. **Accueil personnalisé** (Reprendre / En direct / Favoris / Nouveautés).

Ces trois-là, combinés, font bouger le J7 plus que tout le reste.

---

## 6. Garde-fous (pro & durable)

- **Notifications utiles, pas spam** : fréquence raisonnable, désactivables,
  centrées sur CE QUE l'utilisateur a choisi (favoris, rappels posés).
- **Pas de dark patterns** : on facilite, on ne piège pas. La meilleure
  rétention vient de la valeur, pas de la manipulation.
- **Performance d'abord** : une app rapide retient plus qu'une app pleine de
  features lentes.

---

## 7. Prochaine étape proposée

Je peux **implémenter le Tier 1 #1 (rappels EPG locaux)** et **#2
(Reprendre la lecture)** dès maintenant — ce sont les deux qui créent
l'habitude. Dis « go engagement » et je commence.
