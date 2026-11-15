# NovaTube TV — refonte, premier lot (WIP)

**Sources de présentation préparées. Aucun nouvel APK compilé, installé, signé ou publié. Ne pas fusionner comme une application terminée.**

Cette proposition concerne NovaTube TV native **334.2.6**, package `com.manthefew`, et non NovaTube mobile Flutter. Le lecteur d'un APK tiers de référence n'est pas substitué au lecteur actuel.

## Modifications

- Accueil simple : boutons distincts **Ajouter un lien M3U** et **Se connecter avec Xtream**, ouverture du bon formulaire, listes existantes et ouverture de la liste via les fonctions actuelles.
- Palette par défaut vert pétrole sombre / noir, accent turquoise discret, mot-symbole assorti. Un thème explicitement imposé par le propriétaire reste prioritaire.
- Navigation à la télécommande contournant les actions masquées ; deux entrées côte à côte ou empilées selon la largeur.
- Identité MAC, clés, essais, licences, paiement et intégration Atlas inchangés. Pas de mention du panel dans les nouveaux textes clients.

## Reproduction hors ligne

Utiliser le kit privé `NOVATUBE-4K-Maintenance-Privee.zip`, version Library 7, sources 334.2.6. Ne jamais publier son dossier de signature.

```sh
python apply_ui_patch.py --maintenance /chemin/NOVATUBE-4K-maintenance --output /chemin/nouveau-dossier
NOVATUBE_MAINTENANCE=/chemin/NOVATUBE-4K-maintenance python -m unittest discover -s tests -v
```

Le script vérifie les huit empreintes de sources, refuse les sources supplémentaires et l'écrasement, et copie uniquement les sources Java. `AtlasActivation.java`, `AtlasPanel.java`, `M3uGateway.java` et `AtlasCinema.java` restent identiques. Les changements de `DirectSources.java` ne concernent que le choix initial du formulaire ; sauvegarde/import/authentification restent identiques.

## Protection vidéo

Base APK SHA-256 : `cc3481f0039cde8225b0dcce6ea93aad76a2bc424469663be782e28e6d2266d5`.

```sh
python tools/video_guard.py freeze /chemin/NOVATUBE-4K-Atlas.apk video-lock.json
python tools/video_guard.py verify video-lock.json /chemin/candidat.apk
```

Le garde-fou fige 2 054 entrées de la base, dont le DEX principal, les 21 bibliothèques natives, les dispositions et ressources. Seul le DEX secondaire et les fichiers de signature sont exclus. Le manifeste reste figé pour ce lot de revue : la hausse de version nécessite un contrôle distinct avant distribution.

Ce garde-fou ne prouve pas la qualité visuelle, le HDR, la fluidité, le certificat de signature ni l'absence d'interaction indirecte de l'interface avec le lecteur. Les comparaisons SHIELD restent indispensables.

## Vérifications locales

26 tests Python exécutés avec le kit propriétaire (16 garde-fou + 10 sources) ; 18 contrôles numériques de palette en compilant/exécutant la classe réelle sur JVM ; syntaxe Java des neuf sources analysée. Ces deux derniers outils et les résultats détaillés accompagnent l'archive de travail remise au propriétaire. Sans le kit, les dix tests de sources sont explicitement ignorés.

Aucune compilation contre le SDK Android, aucun test Android ni comparaison d'image SHIELD n'ont été réalisés pour ce lot. Le SDK/émulateur était absent et son téléchargement direct n'a pas abouti.

La nouvelle page TV à trois colonnes n'est pas encore intégrée. L'exclusion des écrans contenant une surface vidéo reste volontairement intacte : l'ancien fond peut donc encore y apparaître. La mise en page complète TV, les essais télécommande/lecture et la comparaison vidéo sont des étapes de validation restantes, pas des résultats acquis.

Aucun changement dans android-app/, le backend, le panel, les licences, la production ou le lien public de téléchargement. Aucune clé, aucun identifiant fournisseur, aucun APK dans cette proposition.
