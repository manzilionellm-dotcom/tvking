# Sécurité — application téléphone 7 Motion

Audit du code sur `claude/motion-mobile-106` (base `32d7280a`). Correctifs limités à ce qui est réversible et ne change pas la signature, l'`applicationId`, ni la façon dont un téléphone déjà installé accepte une mise à jour.

Aucune obfuscation n'est inviolable. Ce document ne dit pas que l'application est imprenable.

## PROUVÉ

Même machine que `docs/MOBILE-106.md` : Flutter 3.47.5, Dart 3.13.4.

- `flutter analyze --no-fatal-infos --no-fatal-warnings` : sortie **0**, **0** erreur.
- `flutter test` : **1433** réussis, **36** ignorés, **0** échec, environ **71 s** (suite complète, `update_and_posture_test.dart` inclus).
- Empreinte APK, tests unitaires sans téléphone :
  - manifeste sans `sha256` → on n'interdit pas l'installation ;
  - `sha256` qui n'est pas 64 caractères hex → refus ;
  - empreinte égale aux octets → accepté ;
  - empreinte différente → refus.
- Posture, test unitaire : `suPresent: true` est « notable » et **ne constitue pas** une fonction qui coupe la lecture. `DevicePosture.unknown` (canal natif absent) ne marque rien.

`ci/release_tag.sh phone claude/motion-mobile-106` imprime `latest`. Cette branche ne publie pas `phone-latest`. Le champ `sha256` ajouté au `version.json` du workflow n'est écrit que dans les étapes de publication, qui ne s'exécutent pas ici.

## Secrets, clés, URL

| Constat | Où | Décision |
| --- | --- | --- |
| Pas de clé TheSportsDB dans l'app. Les scores passent par `GET /api/sports/live` | `live_scores_service.dart` | On ne l'ajoute pas |
| TMDB : le commentaire dit que la clé reste côté Worker | `tmdb_meta_service.dart` | Inchangé |
| Panel en HTTPS, deux hôtes | `backend_hosts.dart` : `https://app.7themotion.com` puis le Worker `workers.dev` | Inchangé. Épingler le certificat Cloudflare casserait les clients au prochain renouvellement. Pas d'épinglage |
| Flux IPTV souvent en HTTP, voulus ainsi | lecteurs, formulaires Xtream / M3U | On ne force pas HTTPS sur l'URL du fournisseur |
| Sel du chiffrement v1 `defew.tv.cred.v1` | `secret_cipher.dart` | Ce n'est pas une clé. La v1 dérive de l'ANDROID_ID. La v2 enveloppe une DEK dans le Keystore. Documenté dans le fichier, pas réécrit (réécrire casserait le déchiffrement des mots de passe déjà posés) |
| PIN par défaut `0000`, stocké en HMAC-SHA256 salé et itéré, plus un blocage progressif | `app_pin_settings.dart` | 4 à 8 chiffres restent devinables hors ligne. On ne promet pas le contraire. Le défaut est voulu pour la première ouverture |

## Identifiants au repos

`PlaylistRepository` chiffre `xtream_password` à l'écriture via `SecretCipher` (AES-GCM). Préférence : DEK 32 octets enveloppée par une clé Android Keystore non exportable (`getCredentialKey` dans `TvkingDevicePlugin.kt`). Repli v1 : dérivation ANDROID_ID. Une valeur ancienne en clair reste lisible (fail-open) pour ne pas vider les listes déjà installées.

Limite écrite dans `secret_cipher.dart` et toujours vraie : la copie cloud / la restauration sur **un autre** appareil n'a pas de clé serveur. Un backup qui emporterait la base emporterait le clair de cette copie. Le manifeste généré en CI pose `android:allowBackup="false"` (le dossier `android/` n'est pas dans git, `flutter create` le régénère). On n'a pas changé cette étape.

## Réponses du panel et du Worker

`RemoteSourceRepository.sync` n'accepte plus qu'un objet JSON. Un tableau ou un texte n'efface rien : on renvoie une erreur réseau et on garde les listes. Un ordre doit avoir un id entier > 0 et un type connu (`source_remove`, `source_activate`, `source_update`). Un type inconnu est acquitté pour ne pas boucler, et n'est pas appliqué.

L'effacement de liste n'est reconnu que si `sources` est un tableau présent et vide, sans objet `source`. L'absence du champ n'efface pas (anciennes réponses).

## Permissions et composants exportés

Déclarés dans les plugins, fusionnés au manifeste par Gradle :

- Réseau, état Wi-Fi, notifications, réveil, service de premier plan média : enregistrement programmé et lecture. On ne les retire pas : les enregistrements s'en servent.
- `ScheduledRecordingReceiver` est `exported="true"` avec `BOOT_COMPLETED`, `QUICKBOOT_POWERON`, `MY_PACKAGE_REPLACED`. Android exige `exported` pour recevoir le boot. Le service d'enregistrement est `exported="false"`.
- Miroir : projection média, service non exporté dans son manifeste. On ne l'élargit pas.

Pas de permission nouvelle dans ce lot.

## Journaux

Pas de `debugPrint` du mot de passe Xtream trouvé dans `lib/`. Les URL de flux passent par `StreamDiagnostics.maskCredentials` sur les chemins déjà masqués. La posture notable est écrite une fois dans la boîte noire (drapeaux booléens, pas un mot de passe).

## Root, émulateur, débogage

`getDevicePosture` (Kotlin) renvoie : débogueur, heuristique d'émulateur, options développeur, `test-keys`, présence d'un fichier `su` à quelques chemins connus, build débogable. `DevicePostureProbe.read` au démarrage attrape toute erreur et continue. Rien dans le lecteur ne lit `noteworthy` pour refuser une chaîne. Un faux `su` ou un émulateur du support ne bloque pas le client.

Ce n'est pas un contrôle d'intégrité. Un binaire modifié peut supprimer l'appel.

## Mises à jour

`UpdateService.downloadAndInstall` compare le SHA-256 du fichier téléchargé au champ `sha256` du manifeste **s'il est présent**. S'il est absent (manifestes déjà en ligne), l'installation continue : refuser aurait cassé les téléphones actuels. S'il est présent et faux, le fichier est effacé et l'installateur n'est pas lancé.

La signature Android de l'APK reste le contrôle de l'installation par le système. On n'a pas changé de clé. Le SHA-256 du manifeste ne remplace pas cette signature : il dit seulement « ce fichier est celui que le manifeste annonce », si le manifeste est honnête et joignable en HTTPS.

Le workflow, sur le chemin `phone-latest` uniquement, calcule `sha256sum` de l'APK et l'écrit dans `version.json`. Champ ignoré par les apps déjà installées qui ne le lisent pas.

## Protection du code — déjà dans le CI, pas renforcée au-delà

Déjà sur le build release téléphone, avant ce lot :

- `flutter build apk --obfuscate --split-debug-info=build/symbols` (les symboles restent dans l'artefact du run, pas dans l'APK servi au client si l'étape de publication ne les joint pas — les symboles servent à lire une pile, ils ne doivent pas être livrés avec l'APK) ;
- R8 : `isMinifyEnabled`, `isShrinkResources`, `proguard-android-optimize.txt` + `ci/proguard-rules.pro`.

Les règles `keep` sur `io.flutter`, `com.manzilionellm`, media_kit et Media3 sont larges. R8 ne renomme pas ces paquets. Un APK release reste lisible par jadx sur le Kotlin gardé et sur les chaînes (URL du panel, noms de canaux de notification). `--obfuscate` renomme le Dart. Ça ralentit la lecture. Ça ne l'empêche pas.

Anti-tampering « léger » retenu : la posture est une note, et l'empreinte SHA-256 refuse un APK qui ne correspond pas au manifeste quand le manifeste la porte. Pas de détection qui ferme l'app, pas de vérification de signature au runtime qui pourrait refuser une mise à jour signée avec la clé actuelle.

## PAS PROUVÉ

- Aucun APK release obfusqué n'a été ouvert dans jadx ici.
- Aucun téléphone rooté, aucun émulateur, aucun `adb backup` n'a été exécuté ici. `allowBackup=false` est une ligne du workflow, pas une mesure sur un appareil.
- Le Keystore matériel n'a pas été interrogé sur un vrai téléphone dans ce lot. Le code du plugin est lu, pas exécuté.
- L'étape GitHub Actions de cette branche (analyze, tests, APK) a son lien dans `docs/MOBILE-106.md` quand le run existe. Ce document ne invente pas un vert.

## Ce qu'il ne faut pas attendre

- Quelqu'un qui a le téléphone déverrouillé et un débogueur peut lire la mémoire du lecteur, donc l'URL du flux en cours.
- Quelqu'un qui contrôle le manifeste `version.json` et le fichier qu'il pointe peut faire installer un APK dont l'empreinte correspond. La signature Android refuse ensuite un APK signé avec une autre clé, au moment où l'utilisateur confirme. On ne court-circuite pas cet écran.
- Le PIN `0000` inchangé ne protège pas un appareil déjà dans les mains de quelqu'un d'autre.
