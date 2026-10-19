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

1. **APK signé produit et publié sur le canal de test.** Après intégration de la PR 126 dans la branche autorisée, la [construction 39213400467](https://github.com/manzilionellm-dotcom/tvking/actions/runs/39213400467) a réussi et publié `108-test.189` sur `zuno-tv-test`. Les tentatives automatiques sur les branches de travail restent refusées avant compilation par les protections d’environnement ; ces protections n’ont pas été modifiées. La release clients `zuno-tv` reste en version 107.
2. **Persistance après réinstallation : conditionnelle.** Les refus locaux survivent au redémarrage, mais pas à l’effacement de toutes les données de l’application. Après réinstallation, il faut une révocation côté serveur ou une sauvegarde v2 effectivement envoyée puis restaurée. La variante TV actuelle ne démarre pas `CloudBackupRepository` dans `main_tv.dart` ; le correctif de backup sécurise le dépôt partagé utilisé par les autres parcours. Une suppression locale hors ligne ne peut pas être promise au-delà d’une désinstallation immédiate.
3. **Mémoire : débit des lots borné, pas mesure de consommation totale.** Le mapping XMLTV, les identifiants de chaînes et le moteur vidéo consomment toujours de la mémoire. Le guide préparé utilise du disque ; la publication atomique peut temporairement nécessiter davantage d’espace.
4. **Points restant à reproduire sur appareil :** pause volontaire face au watchdog de 15 secondes ; attachement tardif d’une vue vidéo après transfert audio ; temps de démarrage lors d’un blocage de plugin. Ce sont des pistes identifiées à la lecture du code, non des correctifs revendiqués ici.
5. **Validation matérielle attendue :** mise à jour depuis la v107 sans désinstallation ; petite box 1–2 Go et appareil récent ; Wi-Fi coupé/rétabli ; serveur lent/403/500 ; suppression pendant import volumineux ; zapping répété ; Home/retour/veille ; 24 h puis 72 h de lecture. Relever crash/ANR, mémoire après stabilisation, temps de première image, reprises et doublons audio.

## Livraison et préparation Google Play

La [PR 126](https://github.com/manzilionellm-dotcom/tvking/pull/126) est intégrée au commit `e993f6034718040a52dffd83f6955dc6ba42d0d6`. L’APK de test signé est disponible sur la [release zuno-tv-test](https://github.com/manzilionellm-dotcom/tvking/releases/tag/zuno-tv-test).

| Artefact de test | Valeur vérifiée |
| --- | --- |
| Version | `108-test.189` / `1792393595` |
| Taille APK | 55 559 425 octets |
| SHA-256 APK | `5314350e08f40d534d0ff0d931b56adc40ac4170ae96fe801e9984b413ac57d4` |
| Certificat de signature | `5145b8e019f6d5fb96a207f2e73673fd954f799966fd598889211556cbdf9e61` |
| Compatibilité de l’APK | Android API 21+, ARM 32 bits, ARM 64 bits, x86_64 |
| Preuve de publication | Release `zuno-tv-test`, artefact APK 655530458 ; capture conservée hors dépôt public |

Google a accordé l’accès à la production au compte ; cela ne signifie pas que la nouvelle version est déjà disponible au public. L’application Play examinée est `com.sevenmotion.tv.seven_tv` et la version du test fermé existant est `106` / `1791125395`.

Le premier bundle signé du [run 39214731777](https://github.com/manzilionellm-dotcom/tvking/actions/runs/39214731777), version `107` / `1792394391`, a été importé mais **jamais diffusé**. Google a signalé un saut excessif de code de version. La confirmation de ce risque durable a été refusée par le contrôle automatique ; elle n’a pas été contournée. Le bundle a été retiré du brouillon de release et reste récupérable dans la bibliothèque d’artefacts de Play.

La [PR 127](https://github.com/manzilionellm-dotcom/tvking/pull/127), intégrée au commit `649b967d5a7649ec6dafa6c3b5d0aa738ece326b`, sépare désormais la numérotation Play des horodatages des APK hors Store : version `108`, code `1791125396`, soit le code publié précédent + 1. Trois tests Python vérifient notamment le refus d’un saut, d’une réutilisation et d’un dépassement. Les contrôles qualité de la PR ont réussi ; le seul build automatique refusé était celui interdit sur la branche de travail, avant toute étape de compilation.

La nouvelle construction signée est le [run 39217573754](https://github.com/manzilionellm-dotcom/tvking/actions/runs/39217573754), avec `publish=false`, `test_box=false`, `play_aab=true`. La suite Play conserve la clé existante, retire la permission d’installation d’APK et désactive l’updater hors Store. Le bundle vise Android API 24+ et target SDK 36. Les appareils installés depuis un APK hors Store avec un code plus élevé ne peuvent pas recevoir ce code Play inférieur comme une mise à jour ordinaire ; cela ne concerne pas la progression du canal Play depuis le test fermé 106.

Dans Play Console, les fiches française et anglaise ont été enregistrées avec les termes IPTV, M3U, Xtream, guide TV et lecteur vidéo, sans promesse de contenus fournis. Cinq tags pertinents ont été ajoutés. La disponibilité a été préparée pour 177 pays/régions et le reste du monde. Android TV partage déjà le canal des téléphones/tablettes. La prise en charge exacte des modèles de TV et projecteurs reste déterminée par la compatibilité Android et le catalogue Play.

Les déclarations de publicité et de sécurité des données ont été révisées après lecture des appels réseau et du Worker de référence de production. Détail de traçabilité dans `preuves/zuno-play-preparation-20261019.json`. Les 11 déclarations apparaissent traitées ; aucune demande n’apparaît dans l’onglet « Attention requise ». Cela n’atteste pas, à lui seul, que les réponses historiques et le comportement de l’application seront acceptés lors de l’examen.

**Soumission à Google non effectuée : accès d’examen non vérifiable.** Les instructions enregistrées dans « Informations de connexion » décrivent un code `GPLAYREVIEW` et un bouton « Demo mode » absents du code de production actuel. `TvGate` bloque les licences expirées, même avec une liste personnelle. Un essai temporaire ou une activation nécessitant de contacter le développeur ne constitue pas un accès autonome et durable. Il faut un parcours de test fonctionnel et les contenus d’essai autorisés avant de remplacer ces instructions et d’envoyer la release.

Autre point concret à régulariser avant une diffusion mondiale : l’écran d’activation propose un prix et un QR WhatsApp de revendeur, sans branchement `PLAY_BUILD` ni intégration de facturation Play dans ce parcours. Les règles officielles permettent une application de consultation, mais encadrent les liens vers l’achat externe selon les programmes et pays éligibles. Aucune inscription applicable à ce parcours n’a été prouvée pendant cet audit. Voir [règles de paiement](https://support.google.com/googleplay/android-developer/answer/10281818) et [accès d’examen](https://support.google.com/googleplay/android-developer/answer/15748846). Il ne faut pas déclarer ce parcours conforme sans vérification ou adaptation.

La politique de confidentialité existante du Worker conserve également l’ancien nom « The Few » : une mise à jour cohérente avec ZUNO, l’inventaire des sources, les diagnostics et la recherche distante optionnelle reste à préparer dans le circuit de déploiement du panel, actuellement gelé. Aucun ancien Worker ni changement de garde-fou n’a été déployé pour accélérer cette publication.
