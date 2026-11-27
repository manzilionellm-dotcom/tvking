# NovaTube Max TV sur box physique

Ce banc Linux lance 100 zaps entre deux mires HLS 1080p25, puis 80 minutes de lecture de la dernière chaîne. Il identifie par SHA-256 l’APK de référence `fe134dd4` ou la version `caf2209b` qui corrige le cadrage pendant une coupure. Les essais de mise au point du lanceur utilisent des captures synthétiques. Une qualification matérielle exige un nouveau dossier de mesures produit sur la box.

## Préparer le poste du banc

1. Brancher une TV de test par USB ou utiliser une session ADB locale déjà appairée. Relever sa série avec `adb devices -l`. Le poste sert la vidéo sur son adresse IPv4 de réseau privé, port 18471, accessible à la box. Réserver une session terminal interactive pour ouvrir la première mire avec la télécommande.
2. Installer Android Platform Tools (ADB), Python 3 avec Pillow, FFmpeg avec libx264 et drawtext, Node.js et npm. Le banc lance deux encodeurs en temps réel. Prévoir un poste capable d’encoder deux flux H.264 1080p25 simultanément.
3. Récupérer l’archive `apk-candidat`, en extraire `NovaTube-TV-emulateur.apk` sur le poste et conserver le fichier original. L’APK contient les variantes ARM et x86. Pour tester le correctif de cadrage, choisir `caf2209b` (SHA-256 `7936acfa8e1064b8d2c58314c59d1ae5f4a2ebed4c5c56beefdcb0b1c6f629ad`). Le témoin `fe134dd4` conserve son empreinte `aa93b4b959bb93d0e863d338be98445254f3412100302870a6c58a4d52662b34`. [APK du correctif](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46062060492/artifacts/15229840261) · [APK témoin](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46052117945/artifacts/15225143357)
4. Dans un checkout de ce dépôt, préparer la branche du banc et le code Atlas de référence. Les chemins ci-dessous partent du checkout du banc.

```sh
git fetch origin qa/novatube-physical-fe134dd4
git switch --detach FETCH_HEAD
git fetch origin 77ce78f49b65f674e8493e8573a6dcc7b62eae6d
git worktree add --detach ../atlas-qa 77ce78f49b65f674e8493e8573a6dcc7b62eae6d
npm ci --prefix ../atlas-qa/android-app/cloudflare --no-audit --no-fund
```

## Lancer le contrôle

Remplacer les trois valeurs par la série ADB de la box dédiée, le chemin de l’APK et l’adresse LAN du **poste**.

```sh
serie_box='SERIE_ADB_DE_LA_BOX'
apk_box='/chemin/vers/NovaTube-TV-emulateur.apk'
ip_poste='192.168.1.20'
banc='android-app/ci/novatube_tv/physical_campaign.py'
python3 "$banc" --serial "$serie_box" --apk "$apk_box" --check
python3 "$banc" --serial "$serie_box" --apk "$apk_box" \
  --media-ip "$ip_poste" --atlas-dir ../atlas-qa/android-app/cloudflare \
  --output "$PWD/mesures-box-01"
```

Le précontrôle lit les propriétés Android TV, le modèle, le SoC déclaré par Android, la RAM utilisable par le noyau, la définition, la densité, les utilisateurs et la table des redirections. Une installation ou des données conservées de `com.sevenmotion.novatube.tv` sur un utilisateur empêchent une nouvelle installation. Android reçoit aussi l’option `-R` qui interdit le remplacement. Sur une box dédiée qui porte déjà l’APK QA, ajouter `--reuse-exact` aux deux commandes. Le lanceur recopie le binaire installé et exige exactement l’empreinte du fichier fourni, y compris si les deux versions sont admises par le banc. L’application reste installée à la fin de l’essai.

Atlas démarre sur un port éphémère de la boucle locale du poste. La seule redirection créée sur la box relie le port 8788 à ce service. Si le port est occupé, le lanceur s’arrête. La redirection créée est libérée à la fermeture normale. La liste M3U et ses segments circulent directement sur le LAN. L’écran et les réglages d’économie d’énergie restent sous le contrôle de l’opérateur : prévoir une session de plus de 80 minutes et consigner tout réglage de mise en veille utilisé pendant l’essai.

Quand le lanceur affiche l’URL, ajouter la liste dans NovaTube, ouvrir **Mire A en plein écran** et appuyer sur Entrée sur le poste lorsque la mire bouge. La confirmation exige une requête réussie de segment A depuis l’adresse LAN de la box et un compteur de mire en mouvement sur les captures Android.

## Lire les mesures

- `device.json` identifie le matériel et l’APK. `MemTotal_kib` mesure la RAM exposée au noyau. Consigner aussi le modèle commercial et le pays où se trouve effectivement la box si l’essai sert au classement régional.
- `pilot.json` conserve les échantillons horodatés de chaque zap. `zap_summary` donne les nombres prévus, tentés, confirmés et strictement sous trois secondes. Le P95 utilise le rang 95 sur les 100 tentatives. Les délais sans confirmation sont classés après les délais mesurés. Un P95 indéterminable vaut `null`. Une série interrompue conserve sa dernière tentative enregistrée.
- `hour-samples.jsonl` conserve les captures décodées de la période de 80 minutes. Le résultat `all_sampled_pairs_moved` exige un compteur avançant sur chaque paire consécutive de la bonne chaîne. `hour-process.jsonl` et `hour-cadence.jsonl` documentent le processus et les fenêtres Media3 disponibles. Un gel plus court que l’intervalle entre deux observations peut échapper à l’échantillonnage.
- Les délais partent de l’envoi de la touche ADB et finissent à la réception de deux captures Android successives montrant un compteur qui avance sur la bonne chaîne. Le transport et les captures entrent dans ce délai. Pour mesurer **télécommande physique → dalle**, enregistrer le geste et l’écran sur une horloge commune et décoder l’acquisition avec `read_display_capture.py`. Si le compositeur de la box masque la surface vidéo dans `screencap`, la campagne ADB s’arrête et une acquisition externe devient nécessaire.

Contrôles à blanc depuis ce checkout :

```sh
(cd android-app/ci/novatube_tv && python3 -m unittest -v test_physical_campaign)
```
