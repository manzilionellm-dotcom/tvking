# Suppression dans l’application puis actualisation

Retour utilisateur après installation du buildLabel 1988119 : la liste supprimée dans l’application revient à l’actualisation. Le premier correctif traitait les suppressions du panel, pas ce cas.

## Cause reproduite

Le geste de suppression pose bien une empreinte locale. SourceOptOuts annulait son effet si assigned_at était absent de la réponse serveur. Un réveil WebSocket générique effaçait aussi toutes les empreintes. Enfin, la restauration cloud ne consultait pas les suppressions volontaires.

## Correction

Une suppression datée reste prioritaire quand le serveur n’apporte aucune preuve d’attribution plus récente. Un réveil générique demande une relecture sans lever les suppressions. Une attribution explicitement plus récente reste acceptée. Le backup consulte les suppressions volontaires avant et après le téléchargement, en reconnaissant les alias get.php/Xtream. Aucune suppression serveur ni modification de licence.

## Validation

Deux tests d’intégration utilisant le vrai dépôt mobile, SQLite et un serveur simulé échouent sur le code livré, puis passent avec la correction : supprimer dans l’app puis actualiser ; supprimer dans l’app puis restaurer un ancien backup. Le test vérifie aussi le réveil générique et une réattribution plus récente. Installation neuve et restauration de sources personnelles non supprimées conservées.

35 tests ciblés réussis. Analyse ciblée sans erreur ni avertissement. Livraison signée et essai sur téléphone physique à compléter.

## Limites

Les empreintes locales ne survivent pas à une désinstallation ou un effacement des données. Un serveur sans date d’attribution ne peut pas prouver une réattribution du même compte : une simple actualisation ou un réveil générique ne doit pas annuler la suppression. Le client peut toujours ajouter volontairement une source via le formulaire d’ajout.
