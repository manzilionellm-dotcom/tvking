# Fidélisation naturelle de Zuno — recherches du 9 octobre 2026

Objectif : retrouver rapidement ce que l'on souhaite regarder et avoir envie de revenir.
Les sources décrivent des pratiques ; aucun gain chiffré de fidélisation de Zuno n'est démontré.

## Ce qui existe dans le code

Lecture de la branche de travail, base `1703d8d2e06500ff40ef2a73d6e6dda743ef6d41` :
- `tv_hub_screen.dart` assemble déjà rappels, dernières chaînes, films entamés, favoris,
  programmes suivis et suggestions « À cette heure ».
- `home_shelves.dart` choisit une rangée de départ selon les contenus disponibles.
- `time_picks.dart` classe les habitudes par créneau local.
- `show_taste.dart` distingue les visites brèves du temps réellement regardé.

L'existence dans le code ne prouve ni l'affichage sur toutes les box ni un bénéfice de rétention.
Ne pas recoder ces fonctions sans mesurer leur usage et leur accessibilité à la télécommande.

## Priorités proposées, non implémentées par cette recherche

1. **Reprise claire dès l'ouverture.** Vérifier sur une vraie télé que revenir à une chaîne
   favorite ou reprendre un film demande très peu d'actions. Conserver la différence entre
   rejoindre une chaîne en direct et reprendre un contenu à une position enregistrée.
2. **Suggestions compréhensibles.** Utiliser les programmes réellement disponibles dans
   la liste du client et son guide. Proposer une sélection courte liée à ses favoris et
   à l'heure, avec « Masquer » pour corriger une suggestion ; ne pas présenter un contenu
   absent comme regardable.
3. **Rappels choisis.** Rendre le choix de suivre ou de ne plus suivre une émission visible.
   Un rappel demandé par le client, annulable, avec ouverture du bon programme quand
   il est disponible. Mesurer les rappels désactivés aussi bien que les ouvertures.
4. **Contrôle de l'accueil.** Permettre de retirer une reprise devenue inutile et de garder
   les favoris à portée de télécommande. Vérifier les possibilités existantes avant ajout.
5. **Watch Next Android TV.** Étudier ensuite l'intégration à l'accueil système. Sur Google TV,
   Google indique une certification nécessaire : ne pas promettre une apparition universelle.
   Ne pas envoyer d'identifiants de flux dans une URL publique de recommandation.

Mesures proposées avant/après : délai ouverture → contenu choisi, nombre d'actions de
télécommande, échecs de lecture, retours volontaires à sept jours, rappels coupés.
Ce sont des mesures à établir, pas des résultats observés. Ne pas utiliser la durée
de visionnage comme seul indicateur de satisfaction.

## Sources officielles vérifiées

- Netflix, fonctionnement des recommandations : historique, préférences, langue, heure
  et durée comme signaux, classement personnalisé :
  https://help.netflix.com/en/node/100639
- Netflix, rappels choisis et annulables :
  https://help.netflix.com/en/node/101522
- Netflix, retrait de la rangée Reprendre sur TV et mobile :
  https://help.netflix.com/en/node/115312
- Android TV, Watch Next : reprise et épisodes suivants :
  https://developer.android.com/training/tv/discovery/watch-next-add-programs
- Google TV, recommandations d'intégration et certification Watch Next :
  https://developer.android.com/training/tv/get-started/google-tv

Ces pistes concernent un lecteur utilisant le contenu du client ; elles n'ajoutent
aucun abonnement, catalogue vidéo externe ou promesse de replay universel.

