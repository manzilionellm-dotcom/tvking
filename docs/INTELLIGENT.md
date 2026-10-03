# Tes émissions

L'app peut retenir les émissions que tu regardes, et te le dire sur la télé : ça va commencer, c'est déjà parti, ou c'est fini. Tout reste sur la box. Rien n'est envoyé.

Ce texte dit ce qui a été **vérifié ici** et ce qui ne l'a **pas** été. On ne devine pas.

## Ce qui est prouvé

Les tests automatiques ont été lancés sur l'ordinateur de développement (pas sur une box).

Ils vérifient la logique, sans image et sans télécommande :

- Un passage court ne devient pas une émission suivie.
- Environ 15 minutes d'image, oui.
- Deux fois le même jour de la semaine et la même heure, oui (une habitude). Deux heures différentes, non.
- Une chaîne en favori baisse la barre à 8 minutes. Si on retire le cœur, ce raccourci s'en va. Le cœur tout seul ne suit pas toutes les émissions de la chaîne.
- Le bouton « Suivre » épingle tout de suite. On peut retirer l'épingle.
- « Plus belle la vie » et « Plus belle la vie S02E05 » sont la même série. Les accents aussi.
- Un carnet illisible ne plante pas : on repart de zéro.
- « Commence dans 5 minutes », « a commencé il y a 12 minutes », « est terminée ».
- Le délai choisi (2, 5, 10 ou 15 minutes) décide du bandeau. La rangée, elle, montre jusqu'à 90 minutes avant.
- Moins d'une minute après le début : pas de phrase « il y a 0 minute ».
- « Reprendre depuis le début » seulement si la chaîne **déclare** un rattrapage. Sinon le bouton n'est pas là. On n'invente pas d'adresse.
- « Rediffusion » seulement si le guide a un autre passage du même titre.
- Le même rappel ne revient pas. Un autre moment (bientôt, puis déjà commencée) est un autre message.
- Deux lignes identiques dans le guide ne font qu'une carte.
- Guide vide, titre vide, horaire à l'envers : rien, pas d'erreur.
- « Dans 5 minutes » est le même calcul que l'horloge soit en UTC ou en heure locale : on compare des instants, pas des textes d'heure.
- Le créneau jour/heure suit le décalage du fuseau, y compris après minuit (22 h 30 + 2 h = 0 h 30 le lendemain).
- Les 16 langues de l'app ont une phrase. Une langue inconnue retombe sur le français.

Commande lancée, dans le dossier `android-app` :

`flutter test`

Résultat lu à la fin : `All tests passed!` — 283 tests réussis, 1 test ignoré (déjà ignoré avant ce travail, hors émissions suivies).

`flutter analyze --no-fatal-infos --no-fatal-warnings` (la même commande que la chaîne d'intégration) s'est terminée avec le code 0. Elle a listé 242 remarques, presque toutes des infos déjà là avant (style `const`). Aucune ligne `error •`. Sur les fichiers de cette fonction, un avertissement déjà présent dans le lecteur (`primary` inutilisé) reste. Ce n'est pas une preuve que l'écran est bon sur une box.

## Ce qui n'est PAS prouvé

- Aucun essai sur une vraie box (Android TV, Fire TV, ou la box du propriétaire).
- Personne n'a vérifié à l'écran que le bandeau se lit bien à 3 mètres, ni que la télécommande arrive sur les boutons.
- Personne n'a vérifié qu'un vrai guide IPTV (XMLTV ou Xtream) contient les bonnes heures pour tes chaînes.
- Le rattrapage (« reprendre depuis le début ») dépend du fournisseur. Le test vérifie seulement la décision « la chaîne l'a déclaré, ou non ». Il ne joue pas la vidéo.
- La note d'une minute d'image n'est pas mesurée sur une box : le lecteur note une fois par minute **seulement si l'image tourne**. Un zapping plus court ne compte pas. Ce rythme est dans le code ; il n'a pas été chronométré sur un appareil.
- La batterie et le processeur n'ont pas été mesurés. Le code évite de relire le guide plus d'une fois par minute, et seulement s'il y a déjà une émission suivie. Ce n'est pas une mesure.

## Comment ça marche (simple)

1. Tu regardes une émission assez longtemps, ou tu appuies sur **Suivre** dans la barre du lecteur (OK ouvre la barre, gauche/droite jusqu'à Suivre, OK).
2. L'accueil montre la rangée **Tes émissions** : en cours, bientôt, déjà commencées. OK ouvre la chaîne. Rien ne s'ouvre tout seul.
3. Un bandeau en haut de l'accueil, pas sur l'image :
   - « X commence dans N minutes » → **Regarder**
   - « X a commencé il y a N minutes » → **Regarder en direct**, et **Reprendre depuis le début** si la chaîne le permet
   - « X est terminée » → **Rediffusion** si le guide en a une plus tard, et **Reprendre depuis le début** si le rattrapage existe
   - **Plus tard** cache ce rappel. Il ne revient pas pour le même moment.
4. Réglages → En plus :
   - **Tes émissions** : OK coupe ou rallume.
   - La ligne du délai : OK passe à 2, 5, 10 ou 15 minutes.

Chaque profil a son carnet. Le profil 1 n'efface pas les données d'avant. Couper la fonction arrête l'apprentissage et cache le bandeau. Le direct continue comme avant.

## Essai sur ta box

À faire toi-même. Ce n'est pas déjà fait.

1. Installe la version de **cette branche** (pas l'application déjà chez les clients). Le lien public `zuno-tv` ne doit pas changer.
2. Ouvre une chaîne dont le guide affiche un titre. Laisse l'image au moins une minute.
3. OK, puis droite jusqu'à **Suivre**, puis OK. Un message dit que l'émission est suivie.
4. Retour à l'accueil. Si le guide connaît un passage proche, la rangée **Tes émissions** apparaît. Sinon, la rangée reste vide : ce n'est pas un bug si le guide est vide.
5. Quand un passage est dans les 5 minutes (ou le délai choisi), le bandeau s'affiche **sur l'accueil**, pas pendant que tu regardes. **Regarder** ouvre la chaîne. **Plus tard** le cache. Reviens à l'accueil : le même message ne doit pas revenir.
6. Réglages → En plus → OK sur **Tes émissions** pour couper. Le bandeau et la rangée disparaissent. Le direct marche toujours. OK encore pour rallumer.
7. OK sur la ligne du délai : le nombre de minutes change (2, 5, 10, 15).

Si une étape ne se passe pas comme ça, c'est un défaut à corriger. Ne pas le prendre pour un succès.
