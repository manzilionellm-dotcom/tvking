# Construction séparée de NOVATUBE

Ce dossier prépare **NOVATUBE**, nouvelle application Android :

| Valeur | Identité imposée |
| --- | --- |
| Branche | `feature/novatube-play-aab` |
| Base | `zuno-mobile-0.1.5-test` |
| Commit source | `93d367e501905e0bd2478d021013d93e43b5794b` |
| Package et namespace | `com.sevenmotion.novatube` |
| Nom | `NOVATUBE` |
| Entrée Flutter | `lib/main_zuno_mobile.dart` |
| Version | `0.1.5` |
| versionCode | `5` |
| Clé d'upload | Nouvelle clé `novatube-upload`, dédiée à NOVATUBE |

## Accord avant compilation

Le propriétaire doit d'abord voir les fichiers modifiés et approuver la
compilation de leur commit exact. Aucune compilation Flutter, Android ou JVM
ne doit être exécutée pour NOVATUBE avant cet accord. Les lectures, contrôles
de syntaxe et tests Python de validation de fichiers ne construisent pas l'app.

Le workflow `.github/workflows/novatube-play-aab.yml` a uniquement un événement
`workflow_dispatch`. Ses entrées obligatoires sont `confirme=COMPILER_NOVATUBE`
et `reviewed_commit=<SHA complet approuvé>`. Si la branche a changé depuis la
revue, le job ne démarre pas. Aucun job ne publie sur Google Play, une release
GitHub, un domaine de téléchargement ou un environnement ZUNO/7 MOTION.

Les exclusions de cette branche dans `build-zuno-tv.yml` et `quality-zuno.yml`
empêchent leurs déclenchements habituels au push. Elles n'altèrent pas leurs
copies sur les autres branches. Ne pas ouvrir de PR avant l'accord : le dépôt
possède également des workflows hérités déclenchés par les PR, dont `qa-gates`.

## Limite GitHub à résoudre avant le premier lancement

Un nouveau workflow uniquement manuel, ajouté seulement à une branche de
travail et jamais exécuté, peut être absent du registre GitHub Actions.
La documentation GitHub exige la présence du fichier sur la branche par
défaut pour son amorçage ; elle indique également qu'après une première
exécution, l'API/CLI peuvent le lancer sur une autre branche ou un tag.

La commande `gh workflow run novatube-play-aab.yml --ref
feature/novatube-play-aab` ne supprime pas cette contrainte d'enregistrement.
Ne pas modifier `main`, changer la branche par défaut, recycler le workflow
de signature ZUNO/7 MOTION ni ajouter un déclencheur automatique pour la
contourner. Si aucun point d'entrée indépendant déjà enregistré et autorisé
n'est disponible, signaler ce blocage au propriétaire et attendre sa décision.
Un fichier YAML préparé n'est pas un run réussi, ni un AAB construit.

Références officielles :

- [Événements GitHub Actions](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_dispatch)
- [Lancement manuel d'un workflow](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)

## Signature et sauvegarde

Les seuls secrets utilisés par cette chaîne sont :

- `NOVATUBE_UPLOAD_KEYSTORE_BASE64`
- `NOVATUBE_UPLOAD_STORE_PASSWORD`
- `NOVATUBE_UPLOAD_KEY_PASSWORD`
- `NOVATUBE_UPLOAD_KEY_ALIAS`

Ils sont attendus dans les secrets GitHub Actions du dépôt, avec une nouvelle
clé indépendante. Aucun secret `ANDROID_*`, aucun `key.properties` hérité,
aucune clé debug ni clé ZUNO/7 MOTION ne peut servir de repli.

Le certificat public `novatube-upload-cert.pem` et `fingerprint.json` sont
versionnés pour que la signature attendue soit revue avec le code. Le JSON
doit contenir `package`, `alias` et `sha256` (64 caractères hexadécimaux sans
séparateurs). Il ne contient aucune clé privée ni aucun mot de passe.

Le fichier temporaire du runner est créé hors du dépôt avec le mode `0600`,
vérifié contre l'empreinte publique, utilisé par Gradle puis supprimé même
en cas d'échec. La sauvegarde durable de la clé et des mots de passe est une
opération privée distincte, à confirmer au propriétaire lors de sa création.
Les métadonnées des secrets GitHub ne constituent pas une sauvegarde exportable.
Ce dossier et les artefacts du workflow ne doivent jamais contenir cette clé.

## Icône exacte et absence de rognage

`branding.json` lie le logo fourni et les ressources classiques/adaptatives
revues visuellement à leurs empreintes SHA-256. Format :

```json
{
  "source_path": "android-app/assets/novatube/logo-source.png",
  "source_sha256": "<empreinte exacte du fichier fourni>",
  "generated_icons": {
    "android-app/android/app/src/main/res/mipmap-mdpi/ic_launcher.png": "<empreinte exacte>"
  }
}
```

Les chemins sont relatifs à la racine du dépôt. Le manifeste réel contient
les cinq densités classiques, le XML adaptatif et ses ressources. Le contrôle
refuse toute image absente ou modifiée depuis la revue. Le contrôle des sommes
ne remplace pas la vérification visuelle du texte dans les masques Android.

## Vérifications effectuées après accord

1. Source issue du tag exact, commit approuvé, identité Gradle/Flutter, politique
   Play immuable, icônes et certificat public.
2. Régressions Python : mauvais package/version, debug, lanceur TV, Cast absent,
   service de lecture incorrect, rapports de tests interrompus ou en échec.
3. Tests JVM existants du handoff réseau Cast avec les dépendances épinglées.
4. Analyse Flutter et tests des nouvelles exclusions Play, de l'import réel
   M3U/Xtream, du Cast, des profils/favoris, de l'EPG et de la lecture.
   Les anciens tests d'activation commerciale ne constituent pas les critères
   attendus de NOVATUBE. Les nouveaux tests vérifient leur désactivation.
5. Construction avec la commande exacte suivante, sans le mode Cast de test :

```bash
flutter build appbundle --release \
  --target=lib/main_zuno_mobile.dart \
  --build-name=0.1.5 --build-number=5
```

Les wrappers Gradle absents du tag sont extraits d'un projet Flutter temporaire.
Seuls `gradlew`, `gradlew.bat` et `gradle-wrapper.jar` manquants sont copiés :
aucune réécriture du manifeste ou de la configuration native NOVATUBE.

6. `bundletool validate`, puis lecture du manifeste du véritable AAB : package,
   nom/version, lanceur mobile, Cast et services de lecture.
7. Comparaison SHA-256 du signataire avec le certificat public approuvé, puis
   `jarsigner -verify -strict` avec un truststore ne contenant que ce certificat.
8. Présence du moteur Flutter release pour les trois architectures attendues,
   rapports de tests réellement terminés et empreinte du verrou des dépendances.

`bundletool` est épinglé à `1.18.2`, SHA-256
`378b5434cd1378bef6b2bc527b8c7f0ff2584b273830335bce54d6d0813c8584`,
fourni par l'[asset officiel Google](https://github.com/google/bundletool/releases/tag/1.18.2).

## Livrable et limites du rapport

L'artefact `NOVATUBE-0.1.5-5-verified-<commit>-<tentative>` n'est créé qu'après
la réussite de toutes les étapes. Il contient l'AAB, son SHA-256, le manifeste
extrait, le rapport de signature, les tests, la version Flutter exacte et la
provenance (commit, numéro/URL du run, versions, certificat).

Aucun AAB n'est téléversé en cas d'échec. Un résultat de tests unitaires ou de
widgets n'est pas un essai sur téléphone : la provenance indique explicitement
`deviceTests: not-run`. Aucun contrôle de ce workflow ne constitue une
acceptation Google Play. Les champs `googleUpload` et `published` restent
`false` : toute création de fiche ou publication attend une autorisation séparée.
