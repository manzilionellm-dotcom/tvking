# Conventions de code — 7 MOTION

<!-- Codename interne / dépôt : `tv_king`. -->


Projet **Flutter** (Dart). Cible : Android mobile + Android TV / Fire TV + Google TV.
À terme : iOS / iPadOS / Apple TV / Web (panneau admin).

## Règles non négociables

1. **Pédagogie d'abord.** Commentaires en français, abondants, explicatifs.
   Le projet sert aussi de support d'apprentissage à son auteur.
2. **Aucune playlist pré-remplie**, aucune URL de flux IPTV en dur dans
   le code de production. Les fichiers `fake_*` peuvent contenir des
   placeholders à des fins de dev uniquement.
3. **Pas de magie noire.** Toute dépendance ajoutée à `pubspec.yaml`
   doit être documentée (que fait-elle, pourquoi on la choisit).
4. **Pas de `print()`** — utiliser `debugPrint()` ou un logger.
5. **Couleurs et tailles** : uniquement via `AppColors` / `AppTextStyles`.
   Jamais de `Color(0xFF…)` ni de `fontSize:` magique en dur dans l'UI.

## Architecture

```
lib/
├── core/        # transverse (thème, widgets génériques, utils)
├── features/    # une fonctionnalité = un dossier
│   └── <feature>/
│       ├── domain/         # modèles purs (pas de Flutter)
│       ├── data/           # sources (M3U parser, Xtream client, SQLite...)
│       └── presentation/   # widgets + écrans + (plus tard) providers Riverpod
└── shared/      # ce qui est partagé entre features (peu)
```

## Numéro de version : la règle de la maison

Décision du propriétaire (07/09/2026), valable pour **toutes** les apps —
téléphone, box, et celles qui viendront. Il veut « un suivi comme de père
en fils, sans que les apps se perdent ».

**Chaque app porte DEUX numéros, et il ne faut jamais les confondre.**

| | Qui le lit | Forme | D'où il vient |
|---|---|---|---|
| `versionCode` | Android seul | horodatage (`1788127315`) | `date +%s` ou `run_number` |
| `buildLabel` | **le client et le support** | `19881`, `19882`… | `ci/build_label.sh` |

`versionCode` doit rester **strictement croissant à vie** : Android refuse
d'installer un paquet dont le numéro est inférieur à celui déjà installé.
Le parc porte déjà des horodatages — on ne peut plus redescendre, jamais.
C'est pour ça qu'on n'a pas pu simplement « repartir à 1 ».

`buildLabel` est le numéro **des humains** : `1988` (l'année du
propriétaire) suivi d'un compteur. On le lit à voix haute au téléphone, on
le compare d'un coup d'œil. Il s'affiche en grand dans « À propos ».

### Si tu ajoutes une app, ou un canal de publication

1. Le canal se demande à `ci/release_tag.sh <phone|tv> <branche>`.
2. Le numéro se demande à `ci/build_label.sh <owner/repo> <canal>`.
3. Tu l'injectes au build : `--dart-define=APP_BUILD_LABEL=$BUILD_LABEL`.
4. Tu l'écris dans `version.json`, champ `buildLabel`.

**Ne recopie jamais ces calculs dans un workflow.** Le jour où une copie
dérive, deux apps donnent deux numéros pour la même version et le support
ne sait plus quoi croire. Une seule implémentation, autant d'appelants
qu'on veut — même raison que `cloudflare/device_profiles.js`.

Le compteur monte **à chaque publication, pas à chaque compilation** : il
est lu depuis le dernier `version.json` réellement publié. Une compilation
qui ne publie rien ne consomme aucun numéro, et le client ne voit jamais
de trous dans la série.

### Le numéro remonte jusqu'au panel

L'app envoie son `buildLabel` au serveur dans le heartbeat
(`subscription_backend.dart`) ; le Worker le range dans
`devices.build_label` ; le panel l'affiche **dans la fiche MAC**, en gros,
avec le verdict : *dernière version* / *ancienne version*.

Le verdict n'est calculé **qu'à un seul endroit** :
`cloudflare/app_versions.js`. Il compare le numéro remonté au
`version.json` **réellement publié** sur le canal de la plateforme — le
même manifeste que le bouton « Vérifier les mises à jour » de l'app lit
(`update_service.dart`). Si tu ajoutes une plateforme, ajoute son canal
dans `VERSION_CHANNELS`, et nulle part ailleurs : le jour où le panel
viserait un autre canal que l'app, il dirait « à jour » pendant que la box
propose une mise à jour.

Les apps installées **avant le 07/09/2026** ne connaissent pas le numéro
maison. Elles ne disparaissent pas du panel pour autant : le verdict
retombe alors sur le `versionCode`, et le panel dit sur quoi il s'appuie.

## Workflow git

- Une branche par fonctionnalité (`claude/<sujet>` ou `feature/<sujet>`).
- Commits fréquents, messages clairs.
- On commit dès qu'une étape compile et tourne.
