# NOVATUBE MAX : build Play et preuve du relais média

Ces scripts ne publient rien sur Google Play et n'utilisent aucune clé de
signature durable. Le build de production est signé avec une clé de test
pour l'émulateur ; la signature stable de l'AAB est réalisée séparément.

## Compilation

Le workflow `novatube-max-play-review.yml` compile l'édition
`com.sevenmotion.novatube.tv`, version `1.0.1`, code `1794878684`, avec
`NOVATUBE_TV=true` et `PLAY_BUILD=true`. `verify_build.py` contrôle le nom,
les API 24/36, les permissions et l'identité du code Dart de l'APK et de
l'AAB. `build-identity.json` conserve les empreintes et le commit source.

## Capture réelle

Avant de lancer `novatube-max-record-review.yml`, régler
`NOVATUBE_BUILD_COMMIT` sur le commit exact du build approuvé. La capture
télécharge seulement ses artefacts vérifiés ; elle ne recompile pas une
variante de démonstration.

Le parcours utilise les écrans ordinaires : importer une liste M3U locale
contenant une mire animée générée, ouvrir Direct puis le lecteur, choisir
Cast et le récepteur explicitement nommé « NOVATUBE QA Receiver ».
L'essai de licence normal doit être disponible par le serveur de l'app.
Aucune préférence de licence ni aucun canal Flutter n'est injecté.

Le récepteur DLNA émulé répond aux vrais M-SEARCH dans Android. Il refuse
la source directe pour contrôler la reprise normale par relais, reçoit
l'URL du serveur HTTP ouvert par l'application et décode réellement ses
octets avec FFmpeg. Les transferts ADB compensent le NAT de l'émulateur.
L'état PLAYING exige des images effectivement décodées.

Le scénario vérifie ensuite le service Android de type mediaPlayback,
l'augmentation des images décodées et des octets du relais, servis en temps
réel, pendant que l'accueil Android est au
premier plan, la notification et l'arrêt après le bouton visible
« Stop casting ». La vidéo est un enregistrement continu de l'écran.

Une sortie `scenario-report.json` avec `validated: false` est seulement
un diagnostic. Une réussite automatique exige encore l'inspection visuelle
de la vidéo avant de la joindre à une déclaration Google Play. Ce contrôle
utilise un émulateur Android 14 et un décodeur DLNA émulé ; il ne prétend pas
valider un téléviseur physique ni tous les appareils Android.

Commande locale, avec Java, SDK Android, FFmpeg, Tesseract et Pillow :

```bash
bash ci/novatube_play_review/run_emulator.sh \
  build/novatube_review_input/NOVATUBE-MAX-1794878684-ci.apk \
  build/novatube_review_recording
```

Fournir aussi `NOVATUBE_BUILD_COMMIT` et garder `build-identity.json` dans le
même répertoire que l'APK : l'empreinte de l'APK réellement installé est
comparée à ce manifeste avant tout enregistrement.

Sans KVM, `NOVATUBE_EMULATOR_ACCEL=off` autorise un essai en émulation
logicielle. La [documentation Android](https://developer.android.com/studio/run/emulator-commandline)
décrit ce mode comme très lent et non pris en charge.
Un démarrage ou une capture réussie ne doit pas être présumé.
