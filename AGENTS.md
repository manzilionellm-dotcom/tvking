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

## Publier : la deuxième règle de la maison

Décision du propriétaire (10/09/2026), après avoir attendu trente
minutes une mise à jour qui n'était jamais partie :

> « Toujours, si on corrige quelque chose, ça se publie. »

**« Vert » ne veut pas dire « livré ».** Un correctif peut compiler,
passer les tests, et ne jamais atteindre une seule box. C'est arrivé :
le build TV ne partait que sur commande manuelle, et personne ne le
savait — aucune erreur, aucune alerte, juste un client qui appuie sur
« Vérifier les mises à jour » et à qui l'app répond, très honnêtement,
qu'il est déjà à jour.

### La famille, et qui suit quoi

Quatre apps sortent du MÊME code Flutter. Elles doivent donc se
reconstruire et se publier ensemble, comme des frères :

| App | Suit | Publie sur |
|---|---|---|
| Téléphone | `lib/**` | `phone-latest` |
| Box TV | `lib/**` | `seventv-latest` |
| Windows | `lib/**` | `windows-latest` |
| Samsung | `lib/**` | `tizen-latest` |
| **LG** | `tv-tizen-webos/**` | `webos-latest` |

**LG est à part, et c'est voulu** : ce n'est pas du Flutter mais une app
HTML/JS autonome. Elle ne doit pas se reconstruire quand `lib/` change —
ça ne la concerne pas. C'est la seule exception, et elle a une raison.

### Ce que ça t'impose si tu ajoutes une plateforme

1. Son workflow se déclenche sur `paths: lib/**` (plus `pubspec.yaml`,
   `assets/**`, `packages/**`, `ci/**`) — pas seulement sur son propre
   fichier, sinon son canal se fige pour toujours.
2. Il publie **sans qu'on le lui demande**. La condition « faut-il
   publier ? » vit dans UNE variable (`env.PUBLIER`), lue par toutes les
   étapes concernées. Ne la recopie pas : le jour où une copie dit oui
   pendant que l'autre dit non, on publie un APK sans le manifeste qui
   l'annonce — donc un bouton de mise à jour qui pointe vers le vide.
3. Son app **propose** la mise à jour au client, elle n'attend pas qu'il
   la cherche. Voir `lib/features/tv/core/tv_update_watch.dart` : au
   démarrage ET au réveil, jamais pendant la lecture, une seule fois par
   version.

### Le garde-fou n'est pas « ne pas publier »

Publier automatiquement fait peur : et si le code est cassé ?

**Il ne peut pas partir cassé.** Un build qui ne compile pas ne produit
aucun paquet, donc ne publie rien. C'est exactement ce qui a protégé le
parc le 09/09 : la compilation était cassée, les quatre builds sont
tombés, et **aucun client n'a rien reçu**. La sécurité est là, pas dans
un interrupteur manuel qu'on oublie d'actionner.

## Workflow git

- Une branche par fonctionnalité (`claude/<sujet>` ou `feature/<sujet>`).
- Commits fréquents, messages clairs.
- On commit dès qu'une étape compile et tourne.
