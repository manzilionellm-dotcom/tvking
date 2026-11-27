# NovaTube Max TV — Rapport de performance

27 novembre 2026

[Données par essai](mesures.json)

## Décision de publication

NovaTube Max TV · paquet com.sevenmotion.novatube.tv

La PR #275 corrige l’enregistrement HLS et deux ouvertures concurrentes du lecteur. La reprise d’un catalogue envoyé par Atlas est prouvée jusqu’au redémarrage de l’application Android. La supériorité régionale reste à mesurer sur les deux appareils Android TV demandés.

| Objectif | Preuve disponible | Décision |
| --- | --- | --- |
| SHIELD et box de 1 à 2 Go | 0 appareil physique sur 2 qualifié. Les essais Android documentés utilisent des émulateurs. | Seuil de 3 secondes non validé sur matériel. |
| Atlas, 5 000 chaînes HTTP | 2 APK sur 2 ont persisté la révision 1 et les 5 000 adresses distinctes après redémarrage. | P0 reproduit, expliqué et validé sur Android émulé. |
| Capture HLS | 6 segments sur 6 reçus une fois. Vidéo et audio identiques à la source pour le lecteur et le fichier. | Validé pour le HLS MPEG-TS multiplexé en clair. |
| Mémoire après fermeture | La mémoire augmente pendant les fermetures. Après 15 min, le tas natif alloué du candidat reste plus haut qu’au début. | Évaluer la dérive à durée de repos et PID identiques. |
| Lecture continue, émulateur américain | NovaTube 44be9e25 a présenté un gel à 57 min 53 s. Le témoin strict du même APK a progressé sur 1 836 paires de captures en 72 minutes. Televizo a progressé sur 1 598 paires en une heure. | Cause du gel historique INCERTAINE. Qualifier la lecture du candidat fe134dd4 sur le matériel demandé. |
| Europe et États-Unis | Comparaison croisée sur deux émulateurs à sortie américaine. Le candidat fe134dd4 atteint 2,564 s contre 2,292 s pour Televizo. Avec l’affichage au relâchement court (61e93832), le P95 atteint 3,020 s contre 2,646 s pour Televizo dans un duel distinct. | Classement des deux marchés INCERTAIN. |

La PR peut rester en revue avec une diffusion du candidat en test interne. Le score de preuve de la première place reste à 3/10. Il qualifie la preuve disponible pour le classement.

- [PR #275 et discussion technique](https://github.com/manzilionellm-dotcom/tvking/pull/275)
- [Premiers résultats publiés et liens vers les essais](https://github.com/manzilionellm-dotcom/tvking/pull/275#issuecomment-7219132737)

## Point de départ et versions comparées

Repères du rapport initial du 27 novembre. Les résultats de catalogue ci-dessous proviennent du banc Linux décrit dans ce rapport.

| Scénario initial | Témoin | Correctif alors en revue |
| --- | --- | --- |
| Lecture M3U, 20 000 chaînes, médiane / P95 | 102,6 / 126,6 ms | 24,9 / 38,3 ms |
| Recherche de secours, 20 000 homonymes, médiane | 788 ms | 3,4 ms |
| Serveurs locaux pour 16 demandes simultanées | 16 | 1 |
| Enregistrement sur une source HTTP 200 vide | Encore actif après 14 essais | Fermé après 3 essais, en 6,09 s |

### Quelles versions répondent à quelle question ?

| Version applicative | Mesures associées |
| --- | --- |
| fffc1378 | Témoin des mesures initiales, des 100 zaps, des lancements, des fermetures répétées et d’Atlas. |
| 14bdcae6 | Candidat de ces mêmes séries, avant le correctif des doubles appuis. |
| 44be9e25 | Version avec correction du double appui. Ouvertures comparées dans les ordres A/B et B/A, puis contrôle externe des zaps. |
| 8bb86add et suivants | Chronométrage par vue et par révision. Les campagnes et les APK exacts sont identifiés à côté de chaque mesure. |

Le rapport initial situait le démarrage à froid sur cinq essais à 2,875 s puis 3,228 s en médiane. Pendant dix zaps, le CPU passait de 64,9 % à 52,7 % d’un cœur et la mémoire de 145,6 à 147,0 Mio. Les séries plus longues de ce rapport ont des fenêtres et des binaires explicités séparément.

- [Historique de la PR et du banc de départ](https://github.com/manzilionellm-dotcom/tvking/pull/275)

## Lancements et 100 zaps

Campagne Android 11 sur mire HLS locale. Dans chaque cellule, le témoin précède le candidat.

| Opération | Essais valides | Médiane | P95 |
| --- | --- | --- | --- |
| Lancement à froid | 30 / 30 | 4,239 s / 2,337 s | 6,917 s / 3,026 s |
| Retour à chaud | 30 / 30 | 0,138 s / 0,168 s | 2,845 s / 2,498 s |
| Zap, touche → rappel natif | 100 / 100 | 3,023 s / 3,752 s | 3,262 s / 4,154 s |

Le témoin correspond à fffc1378 instrumenté par b475f0b3. Le candidat correspond à 14bdcae6 instrumenté par b53eb8f5. Les lancements utilisent les variantes de profil. Les essais vidéo utilisent les variantes de lecture. Un lancement à froid attribué au lanceur a été écarté de chaque série. Les mesures à chaud conservent le processus. Les deux sessions se sont déroulées sur deux instances hébergées.

Les 100 zaps ont tous produit un rappel natif de rendu sur chaque APK. 46 zaps du témoin et 1 zap du candidat ont pris moins de 3 secondes. L’écart de P95 atteint 0,892 seconde sur cette paire. Une variation de charge entre les hôtes peut contribuer à l’écart.

![Distribution des 100 zaps de chaque APK et cible de trois secondes](zapping.png)

Sur les fenêtres de cadence émises avant la succession de zaps, les journaux totalisent 851 images rendues et 12 perdues sur 34,652 s pour le témoin, puis 848 rendues et 171 perdues sur 41,179 s pour le candidat. Les fenêtres ont des durées différentes. Cette observation ne couvre pas une heure de lecture.

- [100 zaps et lancements · témoin](https://github.com/manzilionellm-dotcom/tvking/actions/runs/45998784741)
- [100 zaps et lancements · candidat](https://github.com/manzilionellm-dotcom/tvking/actions/runs/45998775045)

## Aperçu et plein écran

### Du relâchement de l’aperçu au rendu

| Mesure | Témoin | Candidat |
| --- | --- | --- |
| Libération de l’aperçu | 39,941 ms | 50,493 ms |
| Initialisation du décodeur rapportée par Media3 | 160 ms | 323 ms |
| De l’initialisation achevée au premier rendu | 102 ms | 1 602 ms |
| De l’ouverture native de la source au rendu | 295 ms | 1 997 ms |
| De la prise en charge de la commande au rappel natif | 3,907 s | 2,798 s |

Cette décomposition porte sur une ouverture par version. Les origines de temps diffèrent selon la ligne. Les valeurs natives sont incluses dans la durée totale. Le compteur Flutter du candidat a annoncé 2,419 s, soit 379 ms avant le rappel natif. Le chronomètre révisé exige le premier rendu de la vue et de la révision actives.

### Un appui OK isolé et horodaté sur le même appareil

Sur la construction 497455cc, l’aperçu est libéré en 19,362 ms et le décodeur est initialisé en 57 ms. Media3 émet le signal 239 ms après l’ouverture native, entre 558 et 1 129 ms après l’injection du seul appui. La réception par le fil principal intervient 2 196 ms après l’émission. Flutter confirme la vue 3 et la révision 0 en 3 189 ms depuis la prise en charge de l’appui.

Les 2 196 ms utilisent la même horloge monotone Android aux deux extrémités. Sur un premier essai de validation (8bb86add), Flutter confirmait le rendu en 3,135 s. Ces ouvertures individuelles n’établissent aucun P95. Une capture optique synchronisée permettrait de dater l’apparition sur la dalle.

- [Mesure de livraison du rendu sur la même horloge](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46008613279)
- [Journal et APK de la mesure par vue et révision](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46005227751)
- [Source Media3 1.5.1](https://github.com/androidx/media/blob/1.5.1/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/video/VideoRendererEventListener.java#L226-L230)

## Trente ouvertures à chaud

Parcours complet sur le même processus Android, avec retour à l’accueil entre deux ouvertures.

| Mesure | Témoin | Candidat |
| --- | --- | --- |
| Touche → signal Flutter, médiane | 3,292 s | 5,464 s |
| Touche → signal Flutter, P95 | 8,262 s | 11,287 s |
| Touche → rappel natif apparié, P95 | 8,262 s | 11,286 s |
| Libération de l’aperçu, P95 | 31,7 ms | 43,9 ms |
| Initialisation du décodeur, P95 | 124,0 ms | 146,0 ms |
| Ouverture native → émission Media3, P95 | 259 ms | 424 ms |

Sur la paire fffc1378 / 14bdcae6, les deux APK ont produit 30 signaux Flutter en 30 essais. Le seuil de trois secondes est atteint 13 fois sur le témoin et 7 fois sur le candidat. Le témoin et le candidat ont tourné sur des hôtes distincts. Chaque rappel Media3 a été apparié à sa vue. Sur trois essais du candidat, Flutter a devancé le rappel natif de 50, 145 et 294 ms. Les médianes par blocs de dix passages vont de 2,914 à 5,958 s pour le témoin et de 3,345 à 9,850 s pour le candidat.

### Ce qui s’est passé pendant l’essai à 11,287 s

Sur le 29e passage du candidat, la libération de l’aperçu a pris 24,391 ms. Media3 indique une initialisation du décodeur en 129 ms et une émission du premier rendu 304 ms après l’ouverture native. À la réception par le fil principal, les rappels « décodeur prêt » et « premier rendu » sont séparés de 9,440 s. Les instants d’émission de ces mêmes événements sont séparés de 116 ms. Flutter a reçu sa confirmation 1 ms après la ligne de rendu native.

La différence entre ces deux intervalles situe une attente supplémentaire d’environ 9,32 s sur la livraison du second rappel par rapport au premier. Un enregistrement visuel synchronisé reste nécessaire pour dater le premier pixel visible.

- [Campagne des 30 passages, deux versions](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46001357861)
- [Media3 1.5.1 · émission du premier rendu](https://github.com/androidx/media/blob/1.5.1/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/video/VideoRendererEventListener.java#L226-L230)

## Effet du correctif du double appui

Deux hôtes Android 11. Chacun a exécuté les deux APK sur la même mire, dans les ordres opposés.

| Appui OK simple | Avant · 14bdcae6 | Après · 44be9e25 |
| --- | --- | --- |
| 30 ouvertures, médiane | 3,441 s | 3,659 s |
| 30 ouvertures, P95 | 6,162 s | 5,544 s |
| Moins de 3 secondes | 8 sur 30 | 6 sur 30 |
| Hôte A puis B, P95 sur 15 essais | 6,176 s | 6,667 s |
| Hôte B puis A, P95 sur 15 essais | 4,658 s | 5,025 s |

Le délai relie la prise en charge de l’appui au rappel natif apparié de la nouvelle vue. Le P95 du groupe de 30 prend le 29e délai trié. Pour chacune des séries de 15, le P95 est le maximum. Le candidat a le plus grand maximum sur chacun des deux hôtes. Une accélération reproductible reste INCERTAINE.

### Après un déplacement de la sélection suivi d’un double OK

Le témoin a traité deux fois l’ouverture de l’aperçu dans 5 essais sur 6. Une seule première image était attribuable sans ambiguïté dans cette série. Le candidat a produit 6 premières images attribuables sur 6 et aucun double traitement. Sur le double appui sans déplacement, les deux versions ont donné 6 ouvertures attribuables sur 6.

Pour les appuis simples, le P95 de libération de l’aperçu passe de 144,0 à 93,5 ms. Le P95 d’initialisation du décodeur passe de 152 à 159 ms et celui de l’ouverture native jusqu’à l’émission du premier rendu passe de 305 à 378 ms. La mémoire totale annoncée par le noyau des deux émulateurs est de 1,93 Gio.

- [Journaux d’ouverture dans les deux ordres](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46004804211)
- [Correctif du double appui](https://github.com/manzilionellm-dotcom/tvking/commit/44be9e254e4fe0e41cd743d74885a2eb3fea91fc)

## Premier rendu sur le candidat final

Le candidat e322cceb attribue le signal du moteur vidéo à la source qui l’a émis. Les tests ont alterné un flux HLS et un flux MPEG-TS progressif sur une même vue.

| Passage au plein écran, un appui OK | Durée observée |
| --- | --- |
| Libération du lecteur d’aperçu | 9,513 ms |
| Initialisation du décodeur Media3 | 104 ms |
| Ouverture native de la source → émission du signal de rendu | 243 ms |
| Injection de la touche → émission du signal, intervalle | 282 à 853 ms |
| Émission du signal → réception du rappel natif | 1 904 ms |
| Prise en charge de la touche → confirmation Flutter | 2 615 ms |

Une vieille notification du lecteur pouvait être attribuée à la nouvelle chaîne lors de changements rapides. Le correctif associe chaque source à sa génération et utilise l’instant consigné par le moteur de rendu. Les quatre zaps alternés ont produit des confirmations de la bonne source sur les générations 1 à 4, en 2,150 s, 2,585 s, 2,223 s et 2,724 s.

Cette série vérifie l’attribution du rendu et explique comment un rappel peut arriver tard. La cible de 3 secondes concerne l’image visible sur chacun des deux appareils physiques.

- [Tests horodatés de changement de source sur Android](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46013659090)
- [Correctif du suivi des générations](https://github.com/manzilionellm-dotcom/tvking/commit/e322ccebbb6f672deffa8b5719cd543d38ecdf3a)

## Plein écran après lancement à froid

Après un lancement Android à froid, le banc ouvre un aperçu, puis demande le plein écran. Lancements à froid acceptés sur les 30 prévus : 30 côté témoin et 30 côté candidat.

| Étape · médiane / P95 (effectif) | Témoin fffc1378 | Candidat 8bb86add |
| --- | --- | --- |
| Commande → rappel natif (s) | 2,920 / 4,041 (30) | 3,581 / 4,284 (30) |
| Commande → signal Flutter (s) | 2,920 / 3,908 (30) | 3,583 / 4,285 (30) |
| Libération aperçu (ms) | 19,088 / 56,674 (30) | 19,999 / 73,954 (30) |
| Initialisation décodeur (ms) | 150,500 / 211,000 (30) | 174,500 / 331,000 (30) |
| Ouverture native → signal Media3 (ms) | 288,000 / 621,000 (30) | 329,500 / 951,000 (30) |

Sur les 30 ouvertures corrélées de chaque version, le rappel natif intervient en moins de 3 secondes dans 17 cas sur le témoin et 4 cas sur le candidat. Ces nombres proviennent des durées individuelles `input_handler_to_native_callback_ms` dans `cold_fresh_fullscreen` des [données par essai](mesures.json). Le rappel inclut le délai du fil principal. La date d’apparition du premier pixel sur une dalle physique reste INCERTAINE.

Les deux séries utilisent une mire locale identique sur deux hôtes émulés. Les fichiers sont indexés par lancement. Une première campagne qui avait écrasé des traces individuelles a été écartée. Les délais publiés portent sur les essais effectivement corrélés.

- [Témoin · traces des lancements](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46014962700/job/140559636076)
- [Candidat · traces des lancements](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46014962700/job/140559635448)

## Essai du plein écran sans fondu

Seule l’animation d’entrée changeait. Deux hôtes ont chacun essayé les deux APK dans des ordres opposés, six fois par condition.

| P95 du premier numéro lisible en plein écran | Avec le fondu | Sans le fondu |
| --- | --- | --- |
| Hôte A puis B | 5,560 à 7,420 s | 5,148 à 7,089 s |
| Hôte B puis A | 4,570 à 5,945 s | 4,699 à 6,208 s |
| 12 ouvertures réunies | 5,560 à 7,420 s | 5,148 à 7,089 s |
| P95 de notification dans l’application | 3,718 s | 3,939 s |

La dernière capture sans repère lisible et la première capture décodable encadrent le délai. Le numéro suivant confirme que la vidéo avance. Le marqueur central peut rester masqué par l’habillage alors que d’autres pixels vidéo sont déjà visibles. Avec 12 observations, le P95 empirique est le maximum.

Les 24 ouvertures ont produit une vidéo animée et un rappel attribuable. L’effet observé change de sens d’un hôte à l’autre. Sur les douze paires comparables, aucun écart ne dépasse l’intervalle d’incertitude de sa capture.

Le fondu de la PR est conservé. La variante expérimentale est restée sur une branche de test.

- [Deux ordres, captures et repères de chacune des 24 ouvertures](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46015591621)

## De la révision Atlas au catalogue sur la TV

Sur les deux APK, le même ordre du panel a été suivi jusqu’à sa persistance dans SQLite et à son accusé.

| Catalogue HTTP | Révision | Témoin | Candidat | Résultat sur chaque APK |
| --- | --- | --- | --- | --- |
| 5 000 chaînes | 1 | 582 ms | 939 ms | 5 000 URL distinctes, 40 catégories, 1 GET |
| 20 000 chaînes | 2 | 3,633 s | 5,563 s | 20 000 URL distinctes, 40 catégories, 1 GET |

Il s’agit d’une observation complète par cellule, sur les APK de profil. Le vérificateur a relu les données alors que le processus était arrêté, puis après le redémarrage. La même révision restait confirmée et le nombre de téléchargements restait à un. Sur la paire d’APK précédente, les confirmations 5 000 chaînes étaient de 670 et 437 ms.

### Pourquoi les premiers essais expiraient à 100 secondes

Les journaux des deux anciens essais montrent trois arrêts rapprochés. BootGuard a détecté une boucle de démarrage et suspendu l’import distant. Le banc corrigé attend le signal de démarrage stable avant chaque arrêt. Lors d’un autre essai, la reconnaissance de texte a lu la tuile Direct derrière l’avis de retrait de l’ancienne liste. Le banc vérifie désormais l’écran atteint et ferme l’avis.

### Cas de coupure de l’accusé

Le test d’intégration interrompt le premier accusé après l’écriture, rouvre la base et relance la synchronisation. Le Worker local reçoit la même révision, et la deuxième lecture indépendante retrouve 5 000 chaînes distinctes. Un ordre suivant dont l’URL répond 403 reste sans accusé et le catalogue précédent reste disponible.

- [Trace initiale et mode sans échec](https://github.com/manzilionellm-dotcom/tvking/actions/runs/45993205826)
- [Témoin · conservation et accusé](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46001425716/job/140513745889)
- [Candidat · conservation et accusé](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46002360434)
- [Correction du banc de navigation et de redémarrage](https://github.com/manzilionellm-dotcom/tvking/commit/5996fb7fb11b00c6b91e009ee64a925d73193532)

## Enregistrement et mémoire

La capture HLS est comparée à la source, image par image et bloc audio par bloc audio, pendant la lecture et sur le fichier terminé.

| Mire HLS contrôlée | Mesure |
| --- | --- |
| 1080p, 30 images/s, 6 secondes | 180 images vidéo et 283 blocs audio identiques par empreinte après décodage, sur les deux sorties. |
| Réseau amont | 1 connexion TCP, 6 segments distincts, 1 requête par segment. |
| Enregistrement | 12 162 472 octets sur la mire 1080p. Les régressions couvrent les manifestes compressés avec gzip et les adresses sans extension redirigées vers un .m3u8. |
| Formats | Segments MPEG-TS en clair, avec son multiplexé. fMP4, pistes audio externes et flux chiffrés restent hors du périmètre validé. |

### Après une fermeture complète du lecteur et de l’aperçu

| Repos après fermeture | Témoin · PSS | Candidat · PSS |
| --- | --- | --- |
| 0 s | 147,56 Mio | 144,57 Mio |
| 30 s | 115,56 Mio | 112,62 Mio |
| 60 s | 115,52 Mio | 112,15 Mio |
| 120 s | 115,30 Mio | 112,27 Mio |
| 300 s | 115,58 Mio | 113,04 Mio |

La PSS mesure la mémoire résidente attribuée au processus, en partageant le coût des pages communes. Le candidat rend 31,53 Mio entre la fermeture et cinq minutes. Entre 30 secondes et cinq minutes, sa PSS augmente de 0,42 Mio. Chaque série conserve le même PID. Une seule fermeture laisse ouverte la question d’une rétention qui s’accumule au fil des usages.

- [Relevés dumpsys et révisions Atlas de la première paire](https://github.com/manzilionellm-dotcom/tvking/actions/runs/45997873071)
- [Capture HLS et test des manifestes gzip](https://github.com/manzilionellm-dotcom/tvking/commit/63f18bf3ecb424a1e5af9da319d21564ef92027b)
- [Redirection vers un manifeste HLS](https://github.com/manzilionellm-dotcom/tvking/commit/779f57e8078439783345d60ee67741b6ba10ec67)

## Mémoire sur 30 fermetures

Mesures dumpsys à l’accueil. Chaque APK a conservé son processus pendant les 30 cycles et les 15 minutes de repos.

| PSS du processus | Témoin | Candidat |
| --- | --- | --- |
| Médiane, fermetures 1 à 5 | 169,90 Mio | 169,13 Mio |
| Médiane, fermetures 26 à 30 | 187,23 Mio | 181,44 Mio |
| Avant la série | 163,77 Mio | 164,70 Mio |
| Après 15 min de repos | 160,92 Mio | 157,71 Mio |

![PSS après chacune des 30 fermetures et pendant quinze minutes de repos.](memoire.png)

Les médianes des cinq premiers et cinq derniers cycles augmentent de 17,33 Mio pour le témoin et de 12,31 Mio pour le candidat. Sur le candidat, le tas natif alloué passe de 46,25 à 58,05 Mio entre le début de la série et la fin du repos. Une activité Android est restée en mémoire. Le retour de la PSS totale sous son niveau initial et la rétention native peuvent coexister. Une fuite lente reste INCERTAINE.

- [Mesures par cycle et relevés Android complets](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46001357861)

## Origine de la mémoire retenue

Profilage Android 11 sur huit ouvertures du correctif double appui, avec compteurs du processus et échantillonnage des allocations natives.

| Observations, même processus | Après le 1er cycle | Après le 8e cycle | Après 120 s |
| --- | --- | --- | --- |
| Mémoire native allouée | 44,10 Mio | 47,30 Mio | 47,02 Mio |
| Descripteurs de fichiers | 138 | 140 | 140 |
| Fils d’exécution | 47 | 54 | 54 |
| Objets Binder locaux | 54 | 104 | 65 |

La PSS du processus est passée de 176,50 Mio après la huitième fermeture à 147,43 Mio après deux minutes. Le gestionnaire de ressources Android ne déclarait aucun décodeur actif pour ce processus aux huit contrôles après fermeture, ni au repos.

### Ce que le profil d’allocations a identifié

Sur 34 relevés, le solde estimé des allocations présentes atteint 6,25 Mio. Les piles du pilote graphique EGL de l’émulateur associées à getGLString représentent 2,75 Mio (44 %). Les symboles officiels du moteur Flutter, vérifiés par identifiant de compilation, rattachent 3,00 Mio aux tracés, aux glyphes, aux textures et au texte de Skia. Les allocations EGL passent de 0 à 2,75 Mio au fil des réouvertures, puis restent à 2,75 Mio pendant les 130 dernières secondes. Le rendu représente ainsi 5,75 Mio sur 6,25 (92 %). Les 0,50 Mio restants se répartissent entre le compilateur JIT et la table des classes d’Android.

Les allocations sont échantillonnées par pas de 256 Kio. L’origine de ces allocations est identifiée. Leur croissance éventuelle à durée d’utilisation prolongée reste INCERTAINE. Une qualification sur puce physique distinguera le comportement du pilote embarqué de celui de l’émulateur.

- [Profil natif complet, compteurs et libération des décodeurs](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46012585463)
- [Comparaison de l’activité du fil principal sur les deux versions](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46009984660)

## Classement par région

Les 12 combinaisons de région, d’appareil et de lecteur restent à qualifier sur le matériel physique demandé.

| Application | Europe | États-Unis · observations en laboratoire |
| --- | --- | --- |
| NovaTube Max TV | INCERTAIN | P95 de mouvement de 3,020 s sur 61e93832 (100/100 confirmés) et de 2,564 s sur fe134dd4 (100/100), dans deux duels distincts avec les mêmes APK Televizo. |
| Televizo 1.9.9.44-d | INCERTAIN | 100/100 zaps confirmés et P95 de 2,646 s face à 61e93832. Le P95 face à fe134dd4 était de 2,292 s. |
| TiviMate 5.3.3 | INCERTAIN | Installé sur Android TV émulé. Le premier lancement a présenté des conditions comportant un engagement personnel d’indemnisation. La lecture n’a pas été lancée. |

Les APK TiviMate et Televizo ont été obtenus depuis les sites de leurs éditeurs. Les appareils virtuels américains ont été localisés à partir des données du banc ou du point de sortie réseau. Les segments étaient servis en boucle locale. Le délai d’un fournisseur IPTV et les conditions du réseau résidentiel dans chaque région restent à mesurer.

### Décision de classement

Le classement des trois applications sur les deux appareils est INCERTAIN en Europe et aux États-Unis. Sur le dernier duel, Televizo arrive en tête au P95 agrégé de mouvement. Le tableau laisse le score vide pour les lectures que le banc n’a pas lancées. Le score de preuve de la première place de NovaTube demeure à 3/10.

- [Pilote commun des trois lecteurs](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46004506404)
- [Vérification du parcours Televizo](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46007134467)
- [Sites des éditeurs · TiviMate](https://tivimate.com)
- [Sites des éditeurs · Televizo](https://televizo.net)

## États-Unis · campagne antérieure sur e322cceb

Les 100 commandes de la campagne finale visent la même mire et utilisent la même détection externe que la série Televizo.

| Observation à l’écran | NovaTube e322cceb | Televizo 1.9.9.44-d |
| --- | --- | --- |
| Bonne chaîne dans une première capture, médiane | 3,147 s | 1,552 s |
| Bonne chaîne dans une première capture, P95 | 3,323 s | 1,652 s |
| Bonne chaîne détectée en moins de 3 s | 26 sur 100 | 100 sur 100 |
| Mouvement confirmé, médiane | 3,484 s | 1,865 s |
| Mouvement confirmé, P95 | 3,693 s | 1,964 s |
| Mouvement confirmé en moins de 3 s | 0 sur 100 | 100 sur 100 |
| Succès / commandes | 100 / 100 | 100 / 100 |

Televizo occupe le premier rang des deux lecteurs mesurés sur le P95 de confirmation du mouvement, avec 1,729 s d’avance. Le classement porte sur Android TV 36 émulé, avec des flux HLS locaux à deux chaînes. Les temps incluent la capture du repère à l’écran. La dernière instance NovaTube a utilisé une sortie réseau américaine IAD, celle de Televizo une sortie PDX. La région du centre d’hébergement du candidat n’a pas été renseignée par le banc. La paire antérieure utilisait PDX pour les deux lecteurs.

La première détection atteste que le contenu demandé est visible. La deuxième exige deux numéros de trame distincts et atteste que la nouvelle chaîne est en mouvement. Les deux versions de NovaTube ont chacune leur série indépendante.

- [Candidat e322cceb, preuve télécommande et capture](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46018013177/job/140570041755)
- [Client Televizo et captures](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46007134467/job/140533021307)

## Comparaisons croisées du guide et de l’animation de chargement

Chaque comparaison utilise deux émulateurs Android TV 36, avec 1 536 Mio de RAM configurée et la même mire HLS locale 1080p25. Sur chaque hôte, le banc installe successivement les deux APK et alterne 50 fois les chaînes A et B pour chacun. Le second hôte inverse l’ordre. Les numéros de trame à l’écran identifient la chaîne demandée et confirment que l’image avance. Les quatre séries de 100 zaps ont confirmé la bonne chaîne en mouvement à chaque essai. Les durées incluent l’acquisition des captures Android.

| Comparaison et version | Première bonne mire, P95 | Mouvement confirmé, médiane | Mouvement confirmé, P95 | Mouvement en moins de 3 s |
| --- | ---: | ---: | ---: | ---: |
| 1 · Témoin e79928e4 | 3,416 s | 3,575 s | 3,835 s | 0/100 |
| 1 · Lecture unique du guide, 1fb89439 | 3,418 s | 3,560 s | 3,762 s | 0/100 |
| 2 · Lecture unique du guide, 1fb89439 | 4,398 s | 4,061 s | 4,936 s | 0/100 |
| 2 · Même guide et animation isolée, a6a5ba5a | 4,335 s | 3,888 s | 4,845 s | 3/100 |

L’APK du guide est identique dans les deux comparaisons (SHA-256 `f1a6d4c814efe001808fa84d3f692799932279c659b6257ba8b11cc2b8a3100d`). Son P95 de mouvement passe de 3,762 à 4,936 s entre les deux paires d’hôtes. Les écarts de 73 ms et de 91 ms se lisent à l’intérieur de leurs campagnes respectives. L’avantage sur une box physique demeure **INCERTAIN**.

| Comparaison · ordre d’installation et sortie réseau | P95 mouvement du témoin | P95 mouvement du candidat |
| --- | ---: | ---: |
| 1 · Témoin puis guide, PDX | 4,026 s | 3,930 s |
| 1 · Guide puis témoin, PDX | 3,828 s | 3,741 s |
| 2 · Guide puis animation isolée, IAD | 4,971 s | 4,906 s |
| 2 · Animation isolée puis guide, DFW | 3,922 s | 3,564 s |

Sur les 400 zaps, le repère central était illisible dans au moins une capture avant l’apparition de la chaîne attendue. L’ancienne mire a été identifiée sur zéro de ces captures. Les deux états optiques décrivent ce que la sonde a pu lire. Pour la comparaison 1, le P95 entre l’ouverture native de la source et l’émission Media3 atteint 916 ms sur le témoin et 931 ms sur le guide. Le délai d’acheminement de ce signal au rappel natif atteint respectivement 1 592 et 1 624 ms au P95. La comparaison 2 donne 1 064 et 1 034 ms pour l’ouverture jusqu’à l’émission, puis 2 231 et 2 030 ms pour l’acheminement. Les rappels sont appariés sur la vue et la génération de la source. Les deux zaps de calibration par installation sont exclus.

Dans la seconde comparaison, une installation a atteint l’écran de bienvenue sans focus sur le bouton M3U. Le pilote a expiré avant le premier zap. La reprise a sélectionné le bouton par son libellé à l’écran et a exécuté les deux versions dans l’ordre prévu avec les mêmes APK. Le premier hôte a conservé sa série complète. Le calcul repose sur les deux séries de 50 effectivement observées par version.

- [Captures horodatées par essai, empreintes et résumés des deux comparaisons dans `crossed_optical_qa_20261127`](mesures.json)
- [Comparaison 1, témoin puis guide](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46045175781/artifacts/15222888586) · [Guide puis témoin](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46045175781/artifacts/15223535612)
- [Comparaison 2, guide puis animation](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46045807927/artifacts/15223103699) · [Animation puis guide après reprise du parcours initial](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46047921372/artifacts/15223492396)

## États-Unis · comparaison croisée de NovaTube et Televizo sur les mêmes émulateurs

Les deux APK ont été installés en ordre inverse sur deux émulateurs Android TV 36, à raison de 50 zaps par lecteur et par hôte. L’un utilisait une sortie réseau MSP, l’autre une sortie IAD. Chaque paire partage la mire HLS locale, la touche de chaîne et le même observateur indépendant. NovaTube est le véritable candidat applicatif a6a5ba5a avec l’animation isolée. L’expérience réservée aux mires sans carton est analysée séparément ci-dessous.

| Mesure sur 100 zaps | NovaTube a6a5ba5a | Televizo 1.9.9.44-d |
| --- | ---: | ---: |
| Première image de la bonne chaîne, P95 | 4,538 s | 2,466 s |
| Mouvement confirmé, médiane | 4,606 s | 2,667 s |
| Mouvement confirmé, P95 | 5,047 s | 2,936 s |
| Mouvement en moins de 3 s | 0/100 | 98/100 |
| Bonne chaîne confirmée en mouvement | 100/100 | 100/100 |
| Ancienne mire observée avant la première nouvelle mire | 0/100 | 86/100 |

Le P95 de mouvement est de 4,688 s pour NovaTube et 2,893 s pour Televizo sur l’hôte MSP (NovaTube testé en premier). Sur l’hôte IAD, avec l’ordre inverse, il atteint 5,146 s et 2,940 s. Televizo précède NovaTube sur les deux hôtes. Son avance au P95 agrégé atteint 2,111 s. Le résultat concerne ces émulateurs à sortie américaine. Le classement des trois lecteurs sur les box physiques en Europe et aux États-Unis reste **INCERTAIN**. Les résultats historiques sur e322cceb et les comparaisons entre variantes de NovaTube utilisent d’autres séries.

- [NovaTube puis Televizo sur MSP](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46049151157/job/140675837083) · [Televizo puis NovaTube sur IAD](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46048554397/job/140673834776)
- [Les 200 essais horodatés et les identités des exécutables se trouvent dans `same_emulator_televizo_a6a5ba5a`](mesures.json)

## Reprise du candidat fe134dd4 après une interruption du média

Trois émulateurs Android TV 36 ont installé l’APK de la campagne de zapping, après contrôle de son SHA-256. Chaque instance a reçu le flux HLS directement par `10.0.2.2`. Pendant l’interruption, le port du lecteur répondait HTTP 503 et une sonde indépendante continuait de lire les segments sur le port d’origine. Aucune requête média du lecteur n’a obtenu HTTP 200 pendant ces intervalles.

| Coupure | Réponses 503 au lecteur | Image observée | Premier segment HTTP 200 après rétablissement | Deux avancées consécutives visibles après rétablissement |
| --- | ---: | --- | ---: | ---: |
| 5 s | 4 | La mire avance sur les 9 paires pendant la coupure. | 2,293 s | ≤ 1,347 s |
| 15 s | 6 | L’image reste sur la trame 2 549 en fin de coupure et au premier contrôle après rétablissement. | 0,808 s | ≤ 2,123 s |
| 60 s | 26 | La mire se fige puis l’image conservée apparaît agrandie. | 0,253 s | ≤ 3,020 s |

À 5 s, le tampon explique le mouvement observé avant le transfert du premier nouveau segment. Les marqueurs correspondant à des segments obtenus pour la première fois après rétablissement avancent à nouveau au plus tard à 3,580 s. Sur les trois essais, des captures réalisées environ 40 s après le rétablissement confirment que la lecture se poursuit. Une seule interruption par durée a été mesurée, avec une distribution d’erreurs HTTP propre à ce banc.

Pendant la coupure de 60 s, sur l’image de 1 920 × 1 080 pixels, les deux premières frontières de couleur passent des abscisses 320 et 640 aux abscisses 776 et 1 552. L’agrandissement horizontal atteint **2,425 fois**. La capture prise après environ 43 s de coupure et la première capture après rétablissement sont identiques. Le cadrage retrouve ses dimensions normales lorsque la lecture reprend. La coupure de 15 s conserve le cadrage initial sur les quatre captures enregistrées.

[Mesures individuelles et empreintes des archives](fe134dd4-mesures.json) · [Campagne de coupures](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46060741078) · [Banc prévu pour la SHIELD et la box de 1 à 2 Go](https://github.com/manzilionellm-dotcom/tvking/blob/14705bb6b89848bc689cc4e2a5ef2513e4afa39c/android-app/ci/novatube_tv/CAMPAGNE-BOX.md)

## Cadrage corrigé et zapping de caf2209b

`caf2209b` est issu du candidat de zapping `fe134dd4`. La copie de la dernière image utilisait un rectangle calculé à partir de la taille de la vue pour découper la surface vidéo. Le correctif copie toute la surface dans un bitmap limité à 1 280 × 720 pixels et garde le rapport largeur/hauteur de la vue. Sur les deux émulateurs corrigés, le bitmap effectivement affiché mesurait 792 × 445 pixels. [Correction en revue](https://github.com/manzilionellm-dotcom/tvking/pull/280) · [API PixelCopy d’Android](https://developer.android.com/reference/android/view/PixelCopy)

Trois instances Android TV 36 ont reçu la même coupure HTTP 503 de 60 s. Les horloges du lecteur et les copies de l’écran documentent le passage à l’image conservée et son retrait sur les deux instances corrigées. Chaque délai de reprise est une borne supérieure depuis la réouverture du chemin média jusqu’à deux avancées successives de la bonne chaîne.

| Version | Cadrage de la copie | Captures identiques de la copie | Durée minimale avec les mêmes pixels | Reprise automatique |
| --- | --- | ---: | ---: | ---: |
| Témoin fe134dd4 | Coin supérieur gauche agrandi ×2,425 | 153 | 43,633 s | ≤ 3,363 s |
| Correctif caf2209b, essai 1 | Mire entière, compteur central lisible | 140 | 43,977 s | ≤ 3,774 s |
| Correctif caf2209b, essai 2 | Mire entière, compteur central lisible | 142 | 43,767 s | ≤ 3,031 s |

Les mêmes repères étaient à 320, 640 et 410 pixels en lecture normale, à 776, 1 552 et 995 pixels pendant le gel du témoin, puis à 321, 641 et 411 pixels pendant le maintien par le correctif. La comparaison valide la correction du cadrage. L’effet sur le temps de reprise reste INCERTAIN. [Traces des trois interruptions](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46062060492)

![Mire avant, pendant et après une coupure de 60 secondes sur la version de référence et la version corrigée](cadrage-coupure-60s.png)

### Même APK face à Televizo

Le duel a relu les APK installés sur deux émulateurs Android TV 36. Chaque appareil a exécuté 50 zaps par lecteur avec les mêmes mires HLS et dans l’ordre inverse de l’autre appareil. Les deux sorties réseau sont américaines (PDX). Les temps commencent à l’envoi de la touche et incluent la capture de l’écran.

| Lecteur | P95 de la première image de la chaîne demandée | P95 du mouvement confirmé | Bonne chaîne en mouvement en moins de 3 s |
| --- | ---: | ---: | ---: |
| NovaTube caf2209b | 2,049 s | 2,478 s | 100/100 |
| Televizo 1.9.9.44-d | 1,813 s | 2,155 s | 100/100 |

Televizo précède NovaTube au P95 du mouvement sur les deux instances. Sur la première, les délais sont de 2,054 s et 2,437 s. Sur la seconde, ils sont de 2,184 s et 2,505 s. L’écart groupé est de **323 ms**. La comparaison avec les temps de `fe134dd4` correspond à des hôtes différents et ne permet pas d’attribuer une évolution de vitesse au correctif. [Données par zap, essais de cadrage et empreintes](caf2209b-mesures.json) · [Duel optique](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46062431135)

## États-Unis · candidat à indication compacte face à Televizo

Le prototype de la PR #279 conserve le nom de la chaîne demandée dans une pastille de chargement en haut de l’écran. Il dégage la zone vidéo lors des changements de chaîne ordinaires autorisés. Le candidat `fe134dd4` a été compilé avec `NOVATUBE_TV=true`, `NOVATUBE_QA_METRICS=true` et `NOVATUBE_COMPACT_ZAP=true`. L’indication compacte est désactivée par défaut. Le test emploie Televizo officiel 1.9.9.44-d et l’APK NovaTube d’empreinte SHA-256 `aa93b4b959bb93d0e863d338be98445254f3412100302870a6c58a4d52662b34`.

Deux émulateurs Android TV 36, configurés avec 1,5 Gio, ont chacun servi aux deux lecteurs, en ordre inverse. Sur chaque hôte et pour chaque lecteur, 25 touches ont demandé A et 25 ont demandé B. Les bornes supérieures optiques vont de l’envoi de la touche à la capture de la bonne chaîne puis à une deuxième capture successive dont le numéro de trame avance. Les deux sorties réseau sont américaines et les segments HLS sont servis localement.

| Mesure | NovaTube fe134dd4 | Televizo 1.9.9.44-d |
| --- | ---: | ---: |
| Première image de la bonne chaîne, P95 | 2,124 s | 1,933 s |
| Mouvement confirmé, médiane | 2,213 s | 1,941 s |
| Mouvement confirmé, P95 | 2,564 s | 2,292 s |
| Bonne chaîne confirmée en mouvement | 100/100 | 100/100 |
| Mouvement en moins de 3 s | 100/100 | 100/100 |
| Au moins une capture sans mire identifiable avant la cible | 97/100 | 0/100 |
| Ancienne mire vue avant la première nouvelle mire | 6/100 | 83/100 |
| Ancienne mire revue entre la première nouvelle image et la confirmation du mouvement | 0/100 | 0/100 |

| Sortie réseau et ordre | P95 première image, NovaTube / Televizo | P95 mouvement, NovaTube / Televizo | Moins de 3 s, NovaTube · Televizo |
| --- | ---: | ---: | ---: |
| MSP · Televizo puis NovaTube | 2,312 / 1,966 s | 2,693 / 2,327 s | 50/50 · 50/50 |
| PDX · NovaTube puis Televizo | 1,823 / 1,667 s | 2,218 / 1,964 s | 50/50 · 50/50 |

Televizo arrive en tête des deux lecteurs au P95 agrégé du mouvement sur ces deux émulateurs. L’écart agrégé est de 0,272 s. La campagne précédente sur a6a5ba5a s’est déroulée sur d’autres hôtes. La différence entre les deux campagnes inclut la variabilité du banc et des délais de capture. Le P95 interne de NovaTube entre ouverture native et première image Media3 est de 398 ms. Celui de l’action au rappel Flutter est de 749 ms. Ces durées utilisent la télémétrie du lecteur.

La capture PNG de calibration montre « Loading the channel… Mire A » et la mire A dont le numéro 1 104 est lisible au centre. L’image originale 1 920 × 1 080 et son empreinte SHA-256 `b417c1d23c48d9a1f902abf2d1d8c875165e1135cf07ab5fd8354642949b344a` sont conservées. Cette capture établit la présentation effective de l’indicateur sur le banc. Sa fréquence sur les 100 zaps chronométrés reste INCERTAINE.

![Indication de chargement de Mire A et mire A, image 1 104](transition-compacte-preuve.png)

Deux hôtes supplémentaires ont chacun produit 50 observations NovaTube seules. Sur la sortie ATL, le P95 de mouvement atteint 3,144 s et 31/50 zaps passent sous 3 s. Une capture Android tronquée a interrompu la préparation de Televizo. Sur la sortie SEA, le P95 atteint 2,576 s et 50/50 zaps passent sous 3 s. Televizo a signalé que la liste était inaccessible avant toute mesure. Les 100 essais non appariés sont archivés par hôte, hors classement. La paire de remplacement a réutilisé les mêmes APK et le même chronométrage. La préparation de Televizo vérifie l’intégrité de la capture, l’accès aux deux adresses depuis Android et permet de recharger la liste avant le premier essai.

- [Prototype en revue, PR #279](https://github.com/manzilionellm-dotcom/tvking/pull/279) · [Exécutable NovaTube testé](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46052117945/artifacts/15225143357)
- [Televizo puis NovaTube · job et archives](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46052117945/job/140688747176) · [NovaTube puis Televizo · job et archives](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46055720434/job/140697601254) · [Essai unilatéral ATL](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46052117945/artifacts/15225278194) · [Essai unilatéral SEA](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46054264546/artifacts/15226711600)
- [Échantillons, deux premières cibles de calibration, empreintes et mesures par hôte](mesures.json)

## États-Unis · dernier essai du relâchement court, NovaTube et Televizo

La variante `61e93832` affiche la pastille de destination dès le relâchement d’un appui court admissible. Le délai de 180 ms avant changement de chaîne, le moteur de lecture et les protections sont conservés. Les trois drapeaux de l’essai précédent ont été repris, y compris `NOVATUBE_COMPACT_ZAP=true`. L’empreinte SHA-256 de l’APK NovaTube testé est `f4f0c085a2c6b88e42691c9eea8505dc488be6429fa611d64ff1a5ff62312727`. L’APK et le certificat de Televizo 1.9.9.44-d sont identiques à ceux de la campagne précédente.

Les deux ordres ont été fixés avant le lancement. Chaque émulateur Android TV 36 a testé chacun des deux lecteurs sur 50 zaps avec le même catalogue local, 25 demandes A et 25 demandes B. Le contrôle HTTP depuis Android et la vérification des captures PNG précèdent les mesures. Le décodeur optique indépendant et les critères de succès sont ceux de la campagne précédente.

| Mesure | NovaTube 61e93832 | Televizo 1.9.9.44-d |
| --- | ---: | ---: |
| Première image identifiée, P95 | 2,516 s | 2,230 s |
| Mouvement confirmé, médiane | 2,630 s | 2,143 s |
| Mouvement confirmé, P95 | 3,020 s | 2,646 s |
| Bonne chaîne et mouvement confirmés | 100/100 | 100/100 |
| Mouvement en moins de 3 s | 92/100 | 100/100 |
| Première capture, mire illisible | 0/100 | 0/100 |
| Première capture, ancienne chaîne | 100/100 | 91/100 |
| Première capture, cible | 0/100 | 9/100 |
| Ancienne mire observée avant la première cible | 100/100 | 91/100 |
| Ancienne mire revue entre première cible et confirmation du mouvement | 0/100 | 0/100 |

| Sortie réseau et ordre | P95 mouvement, NovaTube / Televizo | Moins de 3 s, NovaTube · Televizo |
| --- | ---: | ---: |
| MSP · Televizo puis NovaTube | 2,506 / 2,149 s | 50/50 · 50/50 |
| SJC · NovaTube puis Televizo | 3,033 / 2,702 s | 42/50 · 50/50 |

Le P95 de mouvement présente un écart de 0,374 s entre les deux lecteurs. Televizo arrive en tête au P95 agrégé des deux hôtes de cette campagne. Le P95 de l’ouverture native au premier rendu Media3 de NovaTube est de 372 ms. Le 95e centile de l’action au rappel Flutter est de 628 ms.

Pour le critère de vitesse, fe134dd4 reste le candidat à qualifier sur appareil physique. Il a confirmé 100/100 zaps sous 3 s dans sa campagne. La variante 61e93832 a produit une première capture lisible sur 100/100 essais, mais son propre P95 de mouvement dépasse 3 s, et Televizo la devance dans les deux ordres de passage.

Le candidat précédent fe134dd4 a montré une première capture illisible sur 97/100 zaps, l’ancienne chaîne sur 3/100 et la destination sur 0/100. Son écart avec Televizo était de 0,272 s au P95 de mouvement. Les deux versions de NovaTube ont été mesurées dans des duels distincts. Leur différence directe à hôte identique reste INCERTAINE. L’intervalle entre appui et première capture peut contenir des images intermédiaires.

Sur les deux hôtes, la première capture de calibration montre « Loading the channel… Mire B » sur l’ancienne chaîne A. Les numéros de trame sont 725 sur MSP et 198 sur SJC. Les captures suivantes identifient la bonne chaîne B en mouvement. Le PNG original MSP ci-dessous a pour empreinte SHA-256 `b85cea9d43c0eb36a0160be983ea4898999a5beb01e91c7269e251d95f333cee`.

![Indication de chargement de la cible B sur la mire sortante A](transition-keyup-preuve.png)

- [Construction et deux comparaisons](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46057380301) · [Televizo puis NovaTube sur MSP](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46057380301/artifacts/15228700247) · [NovaTube puis Televizo sur SJC](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46057380301/artifacts/15227822864)
- [Observations horodatées et première capture de chaque essai](mesures.json)

## Diagnostic du carton opaque sur les deux mires de test

Pendant le zap sur les deux mires locales, la variante 901659fb retire le carton opaque qui couvre la vidéo jusqu’au signal de rendu. La référence a6a5ba5a conserve le carton. Le banc vérifie la chaîne A ou B dans chaque capture et exige deux numéros de trame croissants pour confirmer le mouvement.

| 100 zaps par version | Avec carton | Sans carton, sur les mires |
| --- | ---: | ---: |
| Première bonne mire, P95 | 4,214 s | 2,714 s |
| Mouvement confirmé, médiane | 4,054 s | 2,562 s |
| Mouvement confirmé, P95 | 4,697 s | 3,215 s |
| Première bonne mire en moins de 3 s | 33/100 | 100/100 |
| Mouvement confirmé en moins de 3 s | 0/100 | 59/100 |
| Ancienne mire identifiée avant la nouvelle | 0/100 | 100/100 |
| Retour à l’ancienne mire entre la première identification et la confirmation de mouvement | 0/100 | 0/100 |

Sur l’hôte MSP, le P95 de mouvement passe de 3,517 à 2,185 s. Sur l’hôte IAD, il passe de 4,780 à 3,245 s. La variante sans carton expose l’ancienne chaîne avant que la nouvelle soit prête. La dernière acquisition reconnaissant l’ancienne chaîne s’est achevée au plus tard 1,751 s après le début de l’injection de touche dans ces 100 essais. La référence donne au moins une capture au repère illisible sur chacun des 100 zaps, puis la nouvelle mire apparaît.

Le chemin natif change également de durée sur ces émulateurs. Au P95, la durée entre l’ouverture native et l’émission Media3 passe de 974 à 577 ms, tandis que l’acheminement de l’émission au rappel natif passe de 2 008 à 400 ms. Ces mesures horodatées et la baisse du P95 optique de 1,482 s permettent de cibler le coût de l’écran de chargement. Le comportement hors des deux mires et la qualification d’une transition destinée aux utilisateurs doivent être mesurés sur la version correspondante.

- [Avec puis sans carton, MSP](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46048309425/artifacts/15223907865) · [Sans puis avec carton, IAD](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46048309425/artifacts/15223953218)
- [Mesures détaillées et empreintes dans `crossed_optical_qa_20261127.loading_card_diagnostic`](mesures.json)

## États-Unis · lecture et reprise comparées

Deux lecteurs sur Android TV 36 émulé. Les deux sessions utilisaient les mêmes mires HLS locales à 25 images par seconde.

| Observation | NovaTube 44be9e25 | Televizo 1.9.9.44-d |
| --- | --- | --- |
| Lecture, session de 60 minutes | Dernier changement de numéro à 57 min 52,926 s. Écran d’erreur en fin de session. | 1 599 captures lisibles. Le numéro avance entre les 1 598 paires successives. |
| Coupure demandée de 5 s | ≤ 2,546 s | ≤ 2,431 s |
| Coupure demandée de 15 s | ≤ 3,187 s | ≤ 1,217 s |
| Coupure demandée de 60 s | ≤ 4,106 s | ≤ 2,440 s |
| Images perdues par le décodeur sur l’heure complète | INCERTAIN. Media3 a compté 86 759 rendues et zéro perdue dans 3 470,367 s de fenêtres. | INCERTAIN. Les captures espacées ne dénombrent pas toutes les images. |

Les délais de reprise sont des bornes supérieures entre le rétablissement du réseau et deux images numérotées en mouvement. Chaque durée de coupure a été testée une fois par lecteur. Pour 5 s, les deux lecteurs affichaient encore du mouvement en fin de coupure. Les données disponibles ne permettent ni de calculer un P95 de reprise ni de classer la perte totale d’images.

Les sessions de lecture prolongée utilisaient des instances différentes de même configuration, avec sorties réseau US via PDX pour NovaTube et MSP pour Televizo. Un intervalle entre deux captures peut masquer une brève interruption.

- [Traces NovaTube, vidéo de sortie et trafic HTTP](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46010491329/artifacts/15207672921)
- [Traces Televizo et compteurs réseau](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46014984876/artifacts/15212171566)

## États-Unis · version 44be9e25

Televizo précède NovaTube sur les deux mesures visuelles du zapping. Chaque application a affiché la bonne chaîne sur 100 commandes sur 100.

| Temps depuis la commande | Televizo 1.9.9.44-d | NovaTube 44be9e25 |
| --- | --- | --- |
| Première capture de la bonne chaîne, médiane | 1,552 s | 3,296 s |
| Première capture de la bonne chaîne, P95 | 1,652 s | 3,485 s |
| Mouvement confirmé par deux numéros successifs, médiane | 1,865 s | 3,658 s |
| Mouvement confirmé, P95 | 1,964 s | 3,887 s |
| Mouvement confirmé en moins de 3 s | 100 sur 100 | 0 sur 100 |
| Étendue des confirmations du mouvement | 1,451 à 2,055 s | 3,277 à 4,039 s |

Televizo occupe le premier rang des deux lecteurs pour le P95 de confirmation du mouvement sur ce banc. NovaTube occupe le deuxième. Écart observé de 1,923 s. La première capture montre un écart de P95 de 1,833 s. Les délais incluent le temps de prise des captures. Sa médiane était de 0,337 s pour Televizo et 0,523 s pour NovaTube. Les plages des 100 confirmations ne se chevauchent pas.

Chaque lecteur a reçu les mêmes commandes et les mêmes deux mires HLS 1080p25, sur deux instances Android TV 36 de même configuration. Les deux sorties réseau ont été identifiées US/PDX. Le noyau indiquait 1 503 188 Kio dans les deux cas. Les flux de test provenaient d’un serveur local à chaque banc.

- [Série Televizo et captures](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46007134467/job/140533021307)
- [Série NovaTube et captures](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46004506404/job/140524164768)

## Lecture observée des deux applications

La première campagne a enregistré des fenêtres de deux minutes jusqu’à une rupture de liaison avec l’observateur Android.

| Contrôle de lecture | Televizo | NovaTube |
| --- | --- | --- |
| Dernière preuve de mouvement depuis le début | 42 min 06 s | 24 min 04 s |
| Vidéo effectivement capturée | 2 519,460 s | 1 439,664 s |
| Images de capture avec repère identifié | 64 390 | 37 749 |
| Intervalles entre captures supérieurs à 41 ms | 24 500 | 13 740 |
| Trames de la mire absentes dans les intervalles continus | 1 | 0 |

L’intervalle nominal de la mire est de 40 ms. Les trous du dispositif de capture empêchent d’attribuer un nombre d’images perdues au décodeur sur l’intégralité des sessions. Le saut de trame observable de Televizo peut aussi provenir de la capture. Les deux couvertures ont des durées différentes.

Pour chaque lecteur, le transfert d’un enregistrement d’écran a échoué, puis le contrôle ADB est passé hors ligne. Le serveur continuait à répondre à des requêtes de segments. Une interruption de cette liaison d’observation ne permet pas de dater une interruption de la lecture.

- [Journal des 21 fenêtres Televizo](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46007134467/job/140533021307)
- [Journal des 12 fenêtres NovaTube](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46004506404/job/140524164768)

## Android 11 · 100 zaps suivis par Media3

100 commandes sur deux chaînes HLS locales 1080p25. 100 commandes d’injection ont abouti. 100 premiers rendus sont attribués à une commande grâce à l’horodatage, à la vue et à la révision du flux.

| Étape mesurée | Médiane | P95 |
| --- | --- | --- |
| Traitement de la touche par NovaTube → notification Dart du premier rendu | 2,476 s | 2,726 s |
| Marqueur avant injection Android → notification native | 2,631 s | 2,887 s |
| Ouverture native → signal de rendu Media3 | 0,812 s | 0,950 s |
| Initialisation du décodeur | 0,072 s | 0,100 s |
| Décodeur prêt → signal de rendu Media3 | 0,068 s | 0,090 s |

Sur les 100 commandes, 100 ont reçu le signal dans l’application en moins de 3 secondes. Le maximum confirmé est de 2,929 s. Les commandes sans preuve univoque sont au nombre de 0. Les percentiles portent sur les observations confirmées.

Émulateur Android 11, application 8bb86add, variante ec95c239. La mesure native s’arrête à l’émission du signal Media3. La notification peut parvenir plus tard à l’application. La sortie du téléviseur requiert une mesure optique distincte.

- [Journal des entrées, événements Media3 et captures Android](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46007804631/job/140535298923)

## Android 11 · une heure de lecture

Une fenêtre de 3599,983 s a été mesurée après les zaps, sur les mêmes flux de test. 61 relevés du processus ont retrouvé le même PID et le même instant de création.

| Compteurs Media3 sur les fenêtres mesurées | Résultat |
| --- | --- |
| Fenêtres de cadence complètes | 1 786 |
| Images rendues par le décodeur | 89 961 |
| Images perdues par le décodeur | 0 |
| Part perdue parmi les images rendues et perdues | 0,00 % |

Les fenêtres totalisent 3598,51 s. Sur l’axe de réception du journal, la couverture estimée est de 3598,34 s, avec 1 intervalles découverts de plus d’une seconde et un maximum de 1,422 s. Ces intervalles quantifient des lacunes de télémétrie.

Le décodeur de mire exécuté chaque minute a identifié 0 des 61 observations. Le recadrage des PNG conservés a permis de relire 5/5 compteurs de trame (0 min → A 688, 15 min → A 2188, 30 min → A 687, 45 min → A 2187, 60 min → A 686).

Les compteurs décrivent la sortie du décodeur. Les pertes du compositeur, de la sortie HDMI ou de la dalle restent INCERTAINES.

- [Journaux de cadence, identité du processus et captures PNG de la mire](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46007804631/job/140535298923)

## États-Unis · lecture longue et coupures NovaTube

Android TV 36 émulé, mire HLS locale 1080p25. Révision applicative 44be9e25, compilation de mesure 2e018b0f. Sortie réseau américaine via PDX, région physique de l’hôte INCERTAINE.

L’observation a duré 3 600,058 s. Le dernier changement de numéro apparaît à 57 min 52,926 s. Le numéro 999 reste visible jusqu’à 58 min 02,052 s, puis les 52 dernières captures perdent le repère. L’écran final signale que la chaîne ne répond plus et propose une relance manuelle. La lecture continue sur 60 min échoue sur cet essai.

1 479 des 1 531 captures ont identifié la chaîne A. Le même PID est présent sur les 172 contrôles, sans exception fatale relevée. Durant la fenêtre analysée, le serveur a renvoyé 3 464 réponses HTTP 200. Le dernier segment TS, n° 1 879, a reçu HTTP 200 à 14 h 55 min 28 s UTC. La source répétait sa mire de 120 s et devait rester disponible 110 min. Faute de sonde de la source après la dernière requête, la cause de l’arrêt est INCERTAINE.

Media3 a dénombré 86 759 images rendues et 0 perdues (0,000 %) dans 1 733 fenêtres totalisant 3 470,4 s. Ces compteurs portent sur la sortie du décodeur.

### Coupures du serveur de mire

| Demandé (observé) | Paquets rejetés | État avant rétablissement | Mouvement après rétablissement |
| --- | --- | --- | --- |
| 5 s (6,07 s) | 6 | Mouvement dans les 2 dernières secondes | ≤ 2,546 s |
| 15 s (15,13 s) | 10 | Même numéro relevé sur 6,8 s | ≤ 3,187 s |
| 60 s (60,07 s) | 42 | Image figée puis repère illisible en fin de coupure | ≤ 4,106 s |

La dernière colonne chronomètre la confirmation par deux numéros à l’écran après le rétablissement. Si la lecture s’est poursuivie, ce délai mesure la détection du mouvement. Les sondages espacés ne comptent pas chaque image sur la dalle.

- [Exécution et archive des mesures](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46010491329/artifacts/15207672921)
- [Job Android TV et identité de l’exécutable](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46010491329/job/140544444051)

## Fin de la lecture sur le banc américain

À la fin de l’heure, NovaTube 44be9e25 affiche le nom de la chaîne de test et propose de réessayer.

![Capture finale du lecteur. La chaîne Mire A ne répond plus et un bouton propose de relancer la lecture.](lecture-60-min.png)

La dernière progression du numéro de trame a été observée à 57 min 52,926 s. Le serveur a répondu HTTP 200 à sa dernière requête de segment. Le dernier numéro visible, 999, correspond à la dernière trame attendue du segment 1 879. L’épuisement du tampon est compatible avec cette observation. Aucune sonde indépendante n’a vérifié ensuite que le segment suivant restait disponible, et le journal intégral des erreurs Media3 manque.

Pour reproduire cet arrêt sur le binaire final, enregistrer en parallèle la progression du manifeste depuis un second client, les requêtes du lecteur, les erreurs Media3 et la vidéo de sortie. Ces quatre traces permettront d’attribuer l’interruption au serveur, au chemin réseau ou au lecteur.

- [Capture finale et journal HTTP originaux](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46010491329/artifacts/15207672921)

### Interruptions contrôlées du tunnel sur le même APK

Deux émulateurs ont exécuté le même APK historique (`d8d4a1b3…17cb145`) pendant 80 minutes chacun. Le banc a retiré le tunnel réseau `adb reverse` pendant 110 secondes à deux reprises, aux minutes 2 et 10. Sur un émulateur, le flux passait par ce tunnel. Sur l’autre, le lecteur accédait directement au serveur de mire.

| Chemin vers la mire | Observations sur 80 minutes |
| --- | --- |
| HTTP direct | La sonde a reconnu la chaîne sur 1 944 captures sur 1 944. Les 1 943 paires successives ont montré du mouvement. Le plus long intervalle entre deux observations de mouvement a été de 3,147 s. |
| Tunnel `adb reverse` | Les deux suppressions du tunnel ont provoqué deux arrêts de l’image. La sonde a reconnu une nouvelle image 7,355 s puis 3,181 s après le rétablissement du tunnel. La capture suivante a confirmé deux numéros de trame croissants en 9,719 s puis 5,498 s après rétablissement. Le plus long intervalle entre deux observations de mouvement a atteint 109,985 s. |

Ces interventions reproduisent un gel dû au chemin réseau du banc. La cause de l’incident spontané à 57 min 53 s reste **INCERTAINE**. La campagne initiale ne disposait pas d’une sonde indépendante qui aurait pu confirmer la disponibilité du segment suivant après la dernière requête.

- [Mesures optiques et journal des interruptions, accès direct](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46029158432/artifacts/15220051776)
- [Mesures optiques et journal des interruptions, tunnel](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46029158432/artifacts/15219124914)

### Vérification sur 78 minutes avec une sonde Android indépendante

Sur l’APK diagnostique d’empreinte `9239c20e…1fc650af`, l’accès HTTP direct à `10.0.2.2` a donné 1 982 captures lisibles sur 1 982 et 1 981 paires en mouvement. Les deux coupures de 180 secondes du relais du banc ont gelé l’image sur le chemin dépendant de ce relais. Après rétablissement, la première nouvelle image était observable dans les 9,971 puis 9,636 s. Deux nouvelles trames confirmaient la reprise dans les 12,321 puis 12,008 s. Les compteurs du banc ont enregistré 95 et 96 paquets rejetés. L’APK historique d’empreinte `d8d4a1b3…17cb145` a également passé un témoin passif distinct de 80 minutes avec 2 024 repères lisibles et une progression sur les 2 023 paires successives. L’attribution de l’arrêt spontané à 57 min 53 s reste **INCERTAINE**.

- [Accès direct, 78 minutes](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46035699249/artifacts/15223271007) · [Relais avec deux coupures de 180 secondes](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46035699249/artifacts/15223349929) · [Témoin passif de 80 minutes](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46033328307/artifacts/15221204363)

### Témoin strict de 72 minutes sur l’APK historique

Sur la version 44be9e25 (`d8d4a1b3…17cb145`), les 1 837 captures ont identifié la bonne mire et les 1 836 paires ont avancé. Le plus grand intervalle observé entre mouvements est de 2,777 s. L’origine a répondu aux 2 160 contrôles et les 144 décodages indépendants ont abouti. Les 2 160 relevés ont conservé le PID 3149. Media3 a compté 107 994 images rendues et zéro image perdue pendant les 2 157 fenêtres de cadence observées. La première interrogation du tunnel par la sonde a eu lieu à 4 320,030 s, après la fenêtre optique de 4 320,000 s. La cause du gel historique à 57 min 53 s et l’endurance du nouveau prototype sur appareil physique restent **INCERTAINES**.

- [Exécution du témoin strict](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46044480391) · [Captures et mesures de la sonde](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46044480391/artifacts/15226745020)

## Televizo · Coupures et lecture prolongée

Televizo 1.9.9.44-d. Android TV 36 émulé, mémoire annoncée de 1503188 Kio. Sortie réseau US via MSP (centralus). Mire HLS 1080p25 hébergée sur le banc.

### Reprise après interruption de la source

| Coupure demandée | Durée observée | Paquets rejetés | Mouvement après retour¹ | Observation |
| --- | --- | --- | --- | --- |
| 5 s | 5,98 s | 8 | 2,43 s | Mouvement maintenu en fin de coupure |
| 15 s | 15,14 s | 16 | 1,22 s | Mouvement retrouvé après rétablissement |
| 60 s | 61,02 s | 61 | 2,44 s | Mouvement retrouvé après rétablissement |

¹ Borne supérieure du délai entre le rétablissement du réseau et deux numéros d’image successifs. Le lecteur peut continuer à diffuser les données déjà en mémoire.

### Lecture sur une heure

Durée chronométrée 3600,0 s. 1599 captures sur 1599 montrent la mire A. La première et la dernière capture lisible sont espacées de 3599,4 s. 1598 paires successives montrent une progression du numéro d’image.

Intervalle maximal sans nouvelle capture identifiée 2,45 s. Paires successives ayant conservé le même numéro 0. Le pas de capture ne permet pas de compter toutes les images perdues entre deux observations.

- [Journaux, repères vidéo, échantillons et compteurs réseau](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46014984876/job/140559707464)

## Coupures du chemin média

Un essai par durée et par APK. Un compteur incrusté dans la vidéo permet d’observer si le contenu avance.

| Durée visée | Témoin | Candidat | Observation |
| --- | --- | --- | --- |
| 5 s | 5,100 s | 5,716 s | Image encore animée en fin de coupure sur les deux APK. |
| 15 s | 15,201 s | 15,238 s | Image encore animée en fin de coupure sur les deux APK. |
| 60 s | 60,109 s | 60,053 s | Image figée en fin de coupure. Mouvement revu dans les 4,950 s et 2,568 s suivant le rétablissement. |

Le pare-feu du banc Android 11 bloquait le port HTTP de la mire. Le réseau de contrôle et la génération de la vidéo restaient actifs. Pour les coupures de 5 et 15 s sur le candidat, le compteur du pare-feu est resté à zéro et le lecteur a continué à afficher les données déjà reçues. Sur la coupure de 60 s, 31 paquets ont été rejetés. Les valeurs après rétablissement sont des bornes supérieures mesurées au nouvel échantillon animé.

Le témoin et le candidat correspondent à fffc1378 et 14bdcae6. Les trois durées représentent des situations distinctes. Les six observations précisent le comportement sur ce banc et ne suffisent pas à établir un P95 de reprise régional.

- [Captures temporelles, compteurs réseau et résultats des deux APK](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46001357861)

## Publication et critères de sortie

### Validation du candidat

Sur la révision applicative e322cceb, la suite Flutter générale de la CI compte 1 248 tests réussis et 20 ignorés. Les 263 tests de logique Kotlin du lecteur ont réussi. Les contrôles du Worker et du panel ont également réussi.

### Test interne

Construire depuis la révision retenue un AAB avec le paquet com.sevenmotion.novatube.tv et les paramètres NOVATUBE_TV et PLAY_BUILD. Vérifier le certificat d’envoi correspondant à la fiche Play et un versionCode supérieur à celui déjà accepté. L’APK de test issu du code e322cceb a le versionCode 1795787319 et une signature de test temporaire. Son empreinte SHA-256 complète figure dans les données de mesure.

### Qualification sur le matériel demandé

Reproduire en priorité l’arrêt observé en fin d’heure avec une sonde indépendante du flux sur le candidat final. Sur une NVIDIA SHIELD et une box de 1 à 2 Go, relever le modèle, la RAM, Android, le codec et les empreintes. Alterner l’ancien et le nouveau binaire sur chaque appareil. Mesurer 30 lancements à froid, 30 à chaud et 100 zaps par version. Pour le plein écran, conserver le délai télécommande → première image animée, le P95 et tous les échecs. Déclencher le test fermé une fois le P95 inférieur à 3 secondes sur chaque modèle pour le parcours visé, Atlas persistant et mémoire stable après les cycles.

### Classement et production

Réaliser le comparatif depuis des clients physiquement situés dans chaque région. Utiliser les mêmes modèles, les mêmes flux et les versions identifiées des trois applications. Compter une expiration dans le dénominateur. Publier le P95, les échecs, les trames visibles manquantes et la reprise après 5, 15 et 60 secondes de coupure. Figer le binaire et les critères avant la dernière série. Réserver cette série à la confirmation indépendante et publier les écarts défavorables ainsi que les ex æquo.

Pour la production, retenir la construction testée, vérifier qu’une mise à jour conserve listes et favoris, puis ouvrir progressivement le déploiement. Surveiller les applications sans réponse (ANR), les plantages et les échecs de lecture à chaque palier. En cas de dégradation reproductible, suspendre le palier et livrer le correctif avec un versionCode supérieur. L’indisponibilité d’un flux fournisseur sur le banc d’origine (code 884, zéro octet) laisse la performance de ce fournisseur INCERTAINE.

Le P95 correspond à la 95e observation triée sur 100 essais. Inclure les échecs dans le dénominateur et publier séparément les délais censurés. Rendre un rang par métrique, appareil et région. Une première place sur l’ensemble du protocole exige que toutes les comparaisons prévues soient mesurées et favorables, avec les ex æquo signalés.

- [Suite Flutter du candidat](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46009928576/job/140542534128)
- [APK de test et preuve de compilation](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46010144518/artifacts/15204347371)
- [Recette de construction de la fiche NovaTube Max TV](https://github.com/manzilionellm-dotcom/tvking/blob/feature/novatube-review-access-20261122/.github/workflows/novatube-max-play-review.yml)
- [Mires communes et lecture des numéros de trame](https://github.com/manzilionellm-dotcom/tvking/commit/beaf4073e4cdb6904d83239275e6e00bcdffdd8b)
