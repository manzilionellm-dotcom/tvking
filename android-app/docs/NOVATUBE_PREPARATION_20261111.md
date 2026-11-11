# NOVATUBE — préparation pour accord avant compilation

État au 11 novembre 2026 : **codé, non compilé, non envoyé à Google**.

## Identité verrouillée

| Élément | Valeur |
| --- | --- |
| Dépôt | `manzilionellm-dotcom/tvking` |
| Source | `zuno-mobile-0.1.5-test` |
| Commit source | `93d367e501905e0bd2478d021013d93e43b5794b` |
| Branche | `feature/novatube-play-aab` |
| Dossier / entrée | `android-app` / `lib/main_zuno_mobile.dart` |
| Nom | NOVATUBE |
| applicationId / namespace | `com.sevenmotion.novatube` |
| versionName / versionCode | `0.1.5` / `5` |
| Signature | Nouvelle clé d’upload `novatube-upload`, RSA 4096 |
| Certificat public SHA-256 | `38d6dabe9a73e5ab94a56491e4da6638f5da09ef1eaa77d0eb892d5f0478824b` |

Cette branche constitue une nouvelle application. Le nouveau package isole
son stockage Android et sa signature. Aucun code n’est fusionné dans `main`,
aucune fiche Play n’est créée ou modifiée, aucune clé historique n’est lue
ou remplacée.

## Modifications fonctionnelles

- Identité NOVATUBE dans le manifeste, le flavor, le logo, les titres de
  secours du Cast et les 16 fichiers de traduction.
- Logo source fourni (`881777.jpg`) copié à l’identique sous
  `assets/branding/novatube_logo.jpg`. Les icônes classiques et adaptatives
  en dérivent par redimensionnement et marge, sans redessin du lettrage.
- Cadres, disposition, tailles et parcours existants conservés, sauf les
  éléments dont le retrait a été demandé pour cette distribution Play.
- Politique Play immuable : pas de sources attribuées par MAC, enrôlement
  commercial, essais de contenu, activation Gold, promotions du panel,
  achats WhatsApp/revendeur ou mise à jour par APK historique.
- Aucun contrôle de licence distante ne bloque les sources saisies manuellement.
- Import M3U/Xtream, Cast, profils, favoris, historique, EPG et lecture conservés.
- Sections et contenus identifiés adultes filtrés aux frontières de listes,
  caches, fiches, historique, téléchargements et routes de lecture.
- Ponts natifs issus du socle mobile validé, dans le namespace NOVATUBE.
  L’activité laisse le plugin de diagnostic gérer son propre canal, au lieu
  de l’écraser par un handler incomplet.

Le filtrage adulte réutilise les mots-clés et catégories de la source. Il
peut masquer des titres généraux contenant ces mots ; il n’analyse pas la
vidéo. Le JPG fourni est carré et comporte des marges : le logo complet
reste visible dans le cadre précédent, avec un mot plus petit qu’un logo
découpé horizontalement.

## Signature et sauvegarde

Les quatre nouveaux secrets ont été enregistrés dans les **Repository secrets**
GitHub de ce dépôt ; leur présence a été vérifiée dans la liste de paramètres :

```text
NOVATUBE_UPLOAD_KEYSTORE_BASE64
NOVATUBE_UPLOAD_STORE_PASSWORD
NOVATUBE_UPLOAD_KEY_PASSWORD
NOVATUBE_UPLOAD_KEY_ALIAS
```

Une sauvegarde privée nommée `NOVATUBE-upload-backup-2026-11-11.zip` est
conservée dans les fichiers personnels du propriétaire. Elle n’est pas
dans Git. Seuls le certificat **public** et son empreinte sont versionnés.
Ni la clé ni les mots de passe ne sont affichés dans ce rapport.

Le futur runner refuse tout secret absent, toute autre empreinte et toute
signature debug. Il charge le keystore dans un fichier temporaire privé
hors du checkout, puis le supprime même en cas d’échec.

## Workflow préparé

`.github/workflows/novatube-play-aab.yml` ne déclare que `workflow_dispatch`.
Il exige l’accord explicite, la branche NOVATUBE et le SHA exact revu.

```bash
flutter build appbundle --release \
  --target=lib/main_zuno_mobile.dart \
  --build-name=0.1.5 --build-number=5
```

Aucun drapeau `ZUNO_CAST_TEST` n’est passé. Le Gradle refuse également ce
drapeau si quelqu’un tente de l’ajouter à une autre commande.

Les deux workflows hérités déclenchés sur `feature/**` excluent cette
branche afin d’empêcher une compilation ZUNO lors de son push. Aucune PR
n’est ouverte : certains contrôles hérités compilent à l’ouverture d’une PR.

**Point à vérifier avant le premier lancement :** GitHub documente que
`workflow_dispatch` dépend de la présence du fichier sur la branche par
défaut ou d’un workflow déjà enregistré par une exécution. Ce nouveau fichier
est uniquement sur la branche NOVATUBE. Son enregistrement doit être vérifié
par l’API après le push ; aucun changement de `main`, déclenchement automatique
temporaire ni compilation de test n’a été ajouté pour contourner ce point.

Référence officielle :
https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_dispatch

## Vérifications réellement effectuées avant accord

| Contrôle | État |
| --- | --- |
| Tag et commit source exacts | Vérifiés |
| Syntaxe Python, JSON ARB, YAML et XML Android | Vérifiée |
| Tests Python du vérificateur de manifests et de rapports | 13 réussis |
| Correspondance certificat public / empreinte | Vérifiée |
| Empreintes du logo et de 12 ressources Android | Vérifiées |
| Lettrage dans la zone sûre d’icône adaptative | Rayon maximal 29,839 dp, inférieur à 33 dp |
| Revue statique du code et des imports | Effectuée, sans analyse Dart |
| `git diff --check` | Réussi |
| Tests Flutter core/manuels préparés | 11 cas, non exécutés |
| Tests de widgets NOVATUBE préparés | 9 cas, non exécutés |
| Compilation Flutter/Android/JVM | Non lancée |
| Essais sur téléphone réel / Cast réel | Non effectués |
| Vérification du véritable AAB | En attente d’un AAB compilé |
| Envoi à Google / publication | Aucun |

L’absence de compilation signifie que la validité Dart/Kotlin et le résultat
fonctionnel ne sont pas encore établis. Aucun AAB ni numéro de run de
compilation ne peut être annoncé à ce stade.

## Contrôles prévus après accord

Le workflow doit réussir les tests retenus et construire le bundle avant de
le vérifier avec `bundletool` et `jarsigner`. Les assertions portent sur le
package, la version, le code version, le label, les composants Cast/lecture,
les bibliothèques Flutter release et l’empreinte de signature NOVATUBE.
L’artefact ne sera créé qu’après toutes ces vérifications, avec les rapports,
le SHA du commit, la somme du fichier et le numéro de run. Aucun envoi à
Google Play n’est inclus.

La liste complète des fichiers à revoir figure dans
`../ci/novatube/changed-files.txt`.
