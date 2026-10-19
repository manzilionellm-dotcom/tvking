# Audit de stabilité ZUNO TV — 19 octobre 2026

Demande : approfondir la stabilité du dernier build, avec priorité absolue au respect des suppressions de listes, depuis le panel comme depuis l’application.

## Version examinée et périmètre

- Dernier APK publié sur le canal `zuno-tv` : version **107**, code **1791838176**, artefact mis à jour le 12 octobre 2026.
- Source de cet APK identifiée dans les journaux de construction : `fa7fa00661f79dea1997c4782c76f8265eaf7200`, [construction 38306194606](https://github.com/manzilionellm-dotcom/tvking/actions/runs/38306194606). Le pointeur du tag de release ne suffit pas à identifier la source de l’APK remplacé.
- Base de travail : `ccr-b93e1afd-gwirw0`, commit `e4e69f06d510a790e062b539208ebfbea7159d2a`. Les fichiers TV concernés ont été comparés à la source publiée ; les changements ultérieurs de cette branche concernent aussi le mobile.
- Branche corrective : `feature/zuno-stability-audit-20261019`.
- Analyse du code Flutter, du pont du lecteur natif, des imports M3U/Xtream/XMLTV, de SQLite, des sauvegardes, du protocole de révocation du panel et des barrières de livraison. Aucun flux IPTV réel ni identifiant client utilisé pour les tests.

Cet audit démontre des défauts de code et ajoute des tests de régression. Il ne mesure pas encore les plantages natifs, l’endurance ou la mémoire sur une box physique. Aucun classement de « l’application la plus stable au monde » ne serait étayé par ces résultats.

## Défauts corrigés

| Priorité | Défaut constaté | Correction et comportement attendu |
| --- | --- | --- |
| P1 | Une « réparation » recréait une ligne de playlist disparue pendant le téléchargement. | Une ligne supprimée annule l’import M3U/Xtream ; aucune réinsertion automatique. Les clés étrangères empêchent également l’écriture de chaînes orphelines. |
| P1 | Une synchronisation, un renvoi du panel ou l’ancien interrupteur de repli pouvaient rétablir une liste effacée. | Table SQLite `deleted_sources`, migration de schéma v6 vers v7 et migration des anciens refus TV. Empreintes SHA-256, sans nouvelle copie des URL ou codes en clair. Les ajouts automatiques respectent les refus. |
| P1 | Le retrait explicite d’une liste pouvait attendre un long import ou être annulé par la conservation de la « dernière bonne liste ». | Une révocation reçue via le statut est appliquée sans attendre la file des imports. Les révocations explicites de `device-source` sont traitées avant le téléchargement de la remplaçante, même si celle-ci échoue. |
| P1 | Un tableau `sources: []` retombait sur le champ historique `source` et rechargeait l’ancienne liste. | Le tableau vide fait autorité. Une réponse 200 sans contrat de sources reconnu est traitée comme une erreur réseau et ne vide pas les listes. |
| P1 | La suppression manuelle dépendait de la disponibilité du serveur. | Suppression et refus locaux avant les requêtes réseau. Le retrait serveur d’une source personnelle est tenté ensuite ; son échec ne fait pas revenir la liste sur cet appareil. |
| P1 | Une ancienne sauvegarde pouvait restaurer une source supprimée ; supprimer la dernière liste n’actualisait jamais la sauvegarde. | Restauration automatique avec refus durable. Sauvegarde v2 contenant les empreintes de suppression, autorisée à représenter un état volontairement vide. Envois sérialisés. Une base initiale vide sans suppression ne remplace toujours pas un backup existant. |
| P1 | Les lots XMLTV étaient envoyés à l’isolate principal sans attendre SQLite, ce qui pouvait accumuler le guide en RAM. | Accusé après écriture de chaque lot ; au plus un lot de données en vol. Borne de 500 lignes maintenue même lorsqu’un identifiant XMLTV cible plusieurs chaînes. |
| P1 | Un import XMLTV interrompu pouvait publier un guide partiel et retirer l’ancien contenu. | Écriture dans une table de préparation sur disque, puis publication dans une transaction courte après réussite complète. Une panne réseau conserve le guide précédent. |
| P1 | Une remise à zéro ou un recul de position était interprété comme une reprise de lecture et remettait le budget de reconnexion à zéro. | Réinitialisation du budget uniquement en cas de progression vers l’avant, en lecture effective, sans buffering ni erreur. |
| P2 | Un événement de retour au premier plan pouvait être ignoré en attendant l’accusé d’un zap. | Les événements de cycle de vie sont traités indépendamment de la génération vidéo ; les événements d’une ancienne chaîne restent filtrés. |

Un cache de playlists relu avant une suppression ne peut plus remplacer un état plus récent. Les confirmations de suppression ont été adaptées dans les 16 langues existantes pour décrire la règle durable.

## Règle de suppression retenue

Une suppression reste une suppression après synchronisation forcée, renvoi générique du panel, redémarrage ou restauration utilisant les données de refus disponibles. **Seul un nouvel ajout volontaire dans l’application rétablit la même source.** Renommer une liste ou renvoyer un ordre générique de synchronisation ne suffit pas.

La règle de conservation de la dernière bonne configuration reste applicable à un remplacement qui échoue **sans révocation explicite**. Le chemin de suppression du panel écrit des révocations dans `cloudflare/api_v1.js` et `cloudflare/source_revoke.js` ; celles-ci ont priorité. Une désactivation reste distincte d’une suppression.

La suppression depuis la TV concerne cet appareil. Pour une source personnelle reconnue par son identifiant serveur, le DELETE distant est aussi tenté. Pour une liste fournie par le revendeur, la TV conserve son refus local et ne prétend pas avoir supprimé la configuration du revendeur.

## Vérifications

[CI 39212521362](https://github.com/manzilionellm-dotcom/tvking/actions/runs/39212521362), commit de code `1f11794bcc8c879fd685d73000cf5d0f40f72910` : **succès**.

| Vérification | Résultat observé |
| --- | --- |
| Flutter 3.47.7, suite complète | **591 tests réussis**, 2 ignorés car `RUN_E2E` non défini (preuves Miniflare) |
| `flutter analyze --no-fatal-infos --no-fatal-warnings` | 0 erreur ; 32 avertissements et 245 informations non bloquantes subsistent. Il ne s’agit pas d’une analyse sans diagnostic. |
| Catalogues de traduction | 16 langues × 1 015 messages, paramètres vérifiés |
| Sécurité Worker | Job réussi, smoke + suite de sécurité |
| Protections de configuration et de publication | Job réussi ; 63 tests également exécutés localement avec succès |
| `git diff --check` | Réussi |

Les premiers correctifs lecteur/EPG avaient aussi passé la [CI 39211608562](https://github.com/manzilionellm-dotcom/tvking/actions/runs/39211608562). Les tests Flutter ont été exécutés sur GitHub Actions : le SDK Flutter et une box Android ne sont pas disponibles dans l’environnement local de cet audit.

Tests de régression ajoutés ou renforcés :

- suppression pendant un import M3U et disparition de ligne pendant un import Xtream ;
- révocation du panel pendant une synchronisation, sans attendre le téléchargement ;
- suppression hors ligne et refus HTTP 503 du DELETE distant ;
- plusieurs synchronisations, renvoi du panel, fermeture/réouverture de SQLite ;
- révocation suivie d’un remplacement en échec et d’une ancienne réponse de configuration ;
- priorité du tableau vide sur le champ historique `source` ;
- sauvegarde obsolète, sauvegarde volontairement vide, restauration des refus sur une base neuve ;
- migration SQLite v6 et migration des refus historiques ; nouvel ajout volontaire ;
- vrai isolate avec écriture volontairement ralentie ;
- panne XMLTV après plus d’un lot puis import réussi, avec conservation des autres chaînes ;
- événements réels du contrôleur simulant reset, recul, buffering, reprise et cycle de vie.

## Limites et travail sur appareils

1. **Pas de nouvel APK signé produit par cette branche.** La [tentative automatique 39212521348](https://github.com/manzilionellm-dotcom/tvking/actions/runs/39212521348) est refusée avant toute étape : `feature/zuno-stability-audit-20261019` n’est pas autorisée dans l’environnement `zuno-app-production`. Les protections n’ont pas été modifiées. Le workflow qualité est indépendant de ce constructeur.
2. **Persistance après réinstallation : conditionnelle.** Les refus locaux survivent au redémarrage, mais pas à l’effacement de toutes les données de l’application. Après réinstallation, il faut une révocation côté serveur ou une sauvegarde v2 effectivement envoyée puis restaurée. La variante TV actuelle ne démarre pas `CloudBackupRepository` dans `main_tv.dart` ; le correctif de backup sécurise le dépôt partagé utilisé par les autres parcours. Une suppression locale hors ligne ne peut pas être promise au-delà d’une désinstallation immédiate.
3. **Mémoire : débit des lots borné, pas mesure de consommation totale.** Le mapping XMLTV, les identifiants de chaînes et le moteur vidéo consomment toujours de la mémoire. Le guide préparé utilise du disque ; la publication atomique peut temporairement nécessiter davantage d’espace.
4. **Points restant à reproduire sur appareil :** pause volontaire face au watchdog de 15 secondes ; attachement tardif d’une vue vidéo après transfert audio ; temps de démarrage lors d’un blocage de plugin. Ce sont des pistes identifiées à la lecture du code, non des correctifs revendiqués ici.
5. **Validation matérielle attendue :** mise à jour depuis la v107 sans désinstallation ; petite box 1–2 Go et appareil récent ; Wi-Fi coupé/rétabli ; serveur lent/403/500 ; suppression pendant import volumineux ; zapping répété ; Home/retour/veille ; 24 h puis 72 h de lecture. Relever crash/ANR, mémoire après stabilisation, temps de première image, reprises et doublons audio.

La livraison proposée est une PR de corrections vérifiées par la suite automatique, à intégrer dans le circuit de build autorisé pour produire l’APK de test avant une éventuelle publication clients.
