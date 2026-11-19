# Polices embarquées et démarrage TV hors ligne

L'APK du run 301 a produit une erreur réseau de chargement d'Inter lors du
démarrage hors connexion sur API 29. Embarquer les fontes corrige cette
dépendance réseau avérée. Cela ne démontre pas que cette erreur explique le
splash persistant : les contrôles de démarrage du nouvel APK restent nécessaires.

## Fichiers identiques au catalogue existant

Les 14 TTF sont les octets **non modifiés** référencés par `google_fonts 6.3.3`,
la version résolue pour ce build. Leurs tailles et SHA-256 ont été vérifiés
contre les descripteurs du package officiel, puis leurs tables TrueType ont été
inspectées : fontes statiques, poids correspondant au fichier, version et
copyright conservés. Le total non compressé est de **2 388 328 octets**.

| Famille | Poids normaux embarqués | Version des TTF | Usage |
| --- | --- | --- | --- |
| Inter | 400, 500, 600, 700, 800 | 3.019, git `0a5106e0b` | Lecture TV (rôles 400, 500, 700) et textes partagés. 600 et 800 restent pour la Maison |
| Oswald | 500, 600 | 4.103 | Fichiers conservés dans l'inventaire hors ligne. Les titres TV ne le chargent plus : chasse trop étroite à 3 m |
| JetBrains Mono | 400, 600 | 2.211 | Activation, identifiants et diagnostics TV |
| Bricolage Grotesque | 700, 800 | 1.001 | Titres Maison Noir partagés |
| Manrope | 500, 700, 800 | 4.504 | Textes et boutons Maison Noir partagés |

L'inventaire vient des appels `GoogleFonts` dans `app_text_styles.dart`,
`tv_tokens.dart`, `tv_app_tokens.dart`, du thème `tv_app.dart` et des poids passés
à leurs méthodes. Aucun appel ne demande une variante italique. Les `copyWith`
existants, y compris l'italique du texte d'abonnement et les graisses modifiées
après chargement, restent inchangés. Les glyphes non couverts gardent le repli
système existant.

Le catalogue est fixé à `google_fonts: 6.3.3` dans le pubspec pour éviter qu'une
résolution ultérieure change les fichiers attendus. Cette version nécessite
Flutter 3.35 / Dart 3.9 au minimum ; les workflows existants utilisent Flutter
3.47.7. Cette fixation ne modifie ni le minSdk Android, ni les ABI, ni les styles.

Source vérifiée :

- Archive : <https://pub.dev/api/archives/google_fonts-6.3.3.tar.gz>
- SHA-256 de l'archive : `ba03d03bcaa2f6cb7bd920e3b5027181db75ab524f8891c8bc3aa603885b8055`
- Descripteurs : `lib/src/google_fonts_parts/part_*.g.dart` dans cette archive.
- TTF : URLs de contenu `https://fonts.gstatic.com/s/a/<sha256>.ttf` inscrites
  dans `assets/fonts/provenance.json`, avec taille, poids, version et copyright.
- Licences OFL 1.1 : cinq fichiers originaux du dépôt officiel `google/fonts`,
  chacun lié à un commit exact et une empreinte dans la même provenance.

La licence officielle Manrope garde sa mention 2018 ; les TTF distribués
contiennent aussi la mention 2019 de Sharanda. Le registre affiche les deux,
sans réécrire le fichier de licence original.

## Chargement et périmètre

Les dossiers `assets/fonts/` et `assets/fonts/licenses/` sont déclarés comme
assets Flutter. Les noms `Inter-Regular.ttf`, `Oswald-Medium.ttf`, etc., suivent
le suffixe reconnu par le chargeur 6.3.3. Une fonte variable nommée `[wght].ttf`
ne remplacerait pas ces fichiers dans son mécanisme de recherche.

`configureTvFontLoading()` pose `allowRuntimeFetching = false` au tout début de
`bootstrapZunoTv`, avant les thèmes. Le PC partage ce bootstrap ; les entrées
mobile et Privé conservent leur configuration de téléchargement. Les styles
communs retrouvent néanmoins les mêmes assets embarqués, prioritaires sur le
réseau. Aucun préchargement attendu au démarrage n'est ajouté.

`runGuarded` enregistre les licences pour tous les flavors. Cette inscription
est idempotente et paresseuse : les textes de licence ne sont lus qu'à la
consultation du registre.

La dépendance de test `path_provider_platform_interface` est déclarée
explicitement pour rendre le cache de fontes indisponible sur toutes les
plateformes de test. Elle est déjà une dépendance transitive de `path_provider`
dans l'application ; aucun nouveau service de production n'est ajouté.

## Contrôles reproductibles

Depuis `android-app/` :

```sh
python -B ci/verify_bundled_fonts.py
python -B -m unittest discover -s ci -p test_bundled_fonts.py
flutter test test/core/theme/bundled_fonts_test.dart
```

Le test Flutter utilise le vrai bundle et le vrai `FontLoader`, vide le cache
mémoire du package et rend son cache disque indisponible. Un client HTTP
interdit tout téléchargement. Il charge les 14 variantes des styles existants,
construit aussi le thème Inter Material 3 et attend `GoogleFonts.pendingFonts()`
avant de rendre les textes. Un cas négatif retire le manifeste d'assets et exige
une erreur explicite sans requête HTTP. Les cinq licences doivent être exposées
une seule fois. Ce test nécessite un SDK Flutter ; il ne doit pas être présenté
comme exécuté sur une machine qui n'en dispose pas.

Après compilation, sur **l'APK signé exact** soumis aux contrôles Android :

```sh
python -B ci/verify_bundled_fonts.py --apk /chemin/vers/zuno-tv.apk
```

Le vérificateur compare les 14 fontes, les cinq licences et la provenance
embarquée à la source inspectée. Il refuse les fichiers absents, dupliqués ou
altérés, même si leur taille reste identique. Les ZIP créés par ses tests Python
sont des fixtures d'archive ; ils ne prétendent pas constituer une application
Android exécutable.

Cette vérification complète les contrôles existants du certificat, du SHA de
l'APK et du démarrage hors ligne API 29/API 35. Elle ne remplace aucun d'eux.
L'absence d'erreur de police et l'affichage réel des écrans doivent encore être
confirmés sur ce nouvel APK, après installation fraîche sans cache de fontes.
