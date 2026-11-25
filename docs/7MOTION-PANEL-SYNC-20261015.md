# 7 MOTION mobile — fiabilité du panel et des suppressions

## Périmètre et preuve

Correctif mobile construit sur la base publiée `37fdf3305c5de9d35e20fd6567df38008fc7a7ee`, après les patchs Sport et Radio déjà employés par la chaîne mobile. Le site marketing, le Worker et le panel ne sont pas modifiés.

Le téléphone observé dans le panel est un SM-S938B sous Android 16. Son code de version `1791468669` correspond à `0.3.5-sport-test.110`. Sa licence est active. Le panel ne contient aucun journal récent de cet appareil : l'exécution sur le téléphone physique reste donc à vérifier après installation du nouvel APK.

Trois défauts reproductibles du client ont été corrigés :

- Le curseur de réception pouvait avancer après une synchronisation échouée. Il n'avance désormais qu'après une application réussie ; une panne réseau provoque une nouvelle tentative. Le curseur est propre à chaque appareil et une ancienne boucle arrêtée ne peut plus l'écrire.
- Plusieurs synchronisations pouvaient appliquer leurs réponses dans le désordre. Elles sont maintenant sérialisées ; un événement reçu pendant une synchronisation entraîne une nouvelle lecture avant de terminer.
- Une sauvegarde cloud pouvait recréer une source retirée par le panel. Une suppression conserve désormais une empreinte locale persistante, vérifiée avant et après l'import, y compris quand celui-ci est déjà en cours. Les alias M3U `get.php` et Xtream sont reconnus. Une nouvelle attribution explicite autorise à nouveau cette source ; les autres sources restent protégées.

Les listes personnelles non visées sont conservées. La récupération sur une installation neuve est maintenue. Les empreintes de suppression sont locales : elles survivent au redémarrage, mais pas à une désinstallation ou à l'effacement des données. Aucune sauvegarde distante n'est écrasée par ce correctif.

## Vérifications avant livraison

- 26 tests des trois fichiers directement concernés réussis : 9 réception, 8 réconciliation, 9 sauvegarde.
- Les régressions de synchronisation concurrente et de reprise après erreur échouent avec le code précédent et réussissent avec le correctif.
- Application du patch vérifiée depuis une copie propre de la base mobile et comparaison des six fichiers modifiés : identiques.
- Analyse des fichiers concernés : aucune erreur ni avertissement ; neuf informations de style/dépendance de test préexistantes.
- 60 contrôles des protections de configuration et de livraison réussis.
- Suite mobile locale complète : 1 493 tests réussis, 38 ignorés, 3 échecs liés aux capacités réseau de l'environnement à confirmer en CI (résolution locale via proxy et énumération des interfaces réseau).

## Livraison

Le patch est ajouté au constructeur mobile existant et au détecteur de changements. Un workflow distinct vérifie les régressions sans secret de signature ni droit d'écriture.

Les contrôles de signature, l'environnement protégé et la garde de publication sont inchangés. La fabrication signée reste limitée à la PR de test propriétaire `ccr-b93e1afd-gwirw0` vers `ccr-sport-preuve-20261008`. La livraison cible uniquement `7motion-test`. Aucun déploiement Worker/panel ni publication Store n'est ajouté.

L'installation de l'APK et l'essai réel sur le téléphone ne peuvent pas être déclarés réussis à partir des seuls tests automatisés. L'essai attendu est : attribuer une liste de test, vérifier sa réception, la retirer du panel, vérifier sa disparition, fermer puis rouvrir l'app et confirmer qu'elle ne revient pas.
