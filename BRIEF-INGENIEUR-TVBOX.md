# Brief — App TV Box 7 MOTION : stabilité de lecture

*Rédigé le 17/09/2026. À remettre tel quel à l'ingénieur qui reprend le
dossier. Tout ce qui est chiffré ici a été mesuré, pas supposé.*

---

## 1. Ce qu'on te demande, en une phrase

**Sur une box Android TV bas de gamme, une chaîne doit s'ouvrir vite,
rester ouverte, et ne jamais faire redémarrer l'application.**

Pas de refonte. Pas de nouvelle fonctionnalité. Trois symptômes terrain,
et tu les fais disparaître.

---

## 2. Accès

| | |
|---|---|
| Dépôt | `manzilionellm-dotcom/tvking` |
| Branche vivante | `claude/7motion-android-tv-compat-e0rtyp` |
| Point d'entrée TV | `lib/main_tv.dart` |
| Canal de publication TV | release GitHub `seventv-latest` |
| Panneau admin | `https://tvking-admin.pages.dev` |
| Backend | Worker Cloudflare, `https://app.7themotion.com` |

**Lis `AGENTS.md` avant la première ligne de code.** Ce n'est pas un
document de style : il contient les règles de numérotation des versions
et de publication, et les ignorer casse le parc.

---

## 3. Les preuves terrain — Boîte noire d'une vraie box, 17/09

L'app embarque un journal post-mortem (Réglages → Boîte noire). Voici
l'extrait rapporté, et ce qu'il dit. **Commence par là, pas par le
code.**

```
21:23:17 WARN memoire.pressure.purge {count: 4}
21:20:43 WARN memoire.pressure.purge {count: 3}
21:17:35 WARN memoire.pressure.purge {count: 2}
21:14:55 WARN sub.sync.empty {reason: remote_unknown}
21:14:51 WARN profiles.remote.sync_fail {error: SocketException:
         Failed host lookup: 'seven-motion-backend.manzilionel-lm.workers.dev'
         (OS Error: No address associated with hostname, errno = 7)}
21:09:51 WARN epg.epg.import_fail {host: thekung.801802.com,
         Failed host lookup ... errno = 7}
21:02:03 WARN player.playback_failure {channel: France 2,
         host: thekung.801802.com, uaTried: 0,
         verdict: Le flux s'est coupé en cours de lecture malgré les
         reconnexions automatiques}
20:59:50 INFO lifecycle.boot {previousSessionLines: 120}
20:55:27 WARN player.playback_failure {...}
20:53:42 INFO lifecycle.boot {previousSessionLines: 120}
```

### Ce que ça établit, fait par fait

**a) L'app redémarre.** Deux `lifecycle.boot` à 20:53:42 et 20:59:50 —
six minutes d'écart. Ce n'est pas l'utilisateur qui relance.

**b) La pression mémoire monte par paliers** (`count` 1 → 2 → 3 → 4).
Le compteur ne redescend pas. La purge ne suffit pas : quelque chose
grossit sans être rendu. C'est le suspect n°1 du redémarrage — l'OS
tue l'app, elle repart.

**c) La box a perdu le DNS pendant plusieurs minutes.** `errno = 7` sur
DEUX hôtes indépendants au même moment : notre backend de secours ET le
serveur du fournisseur. **Vérifié : les deux noms résolvent
parfaitement depuis l'extérieur.** Le problème est donc le résolveur de
la box, pas nos adresses. La question d'ingénierie est : *pourquoi
l'app ne bascule-t-elle pas sur DoH ?* (`lib/core/net/doh_resolver.dart`
existe déjà.)

**d) `uaTried: 0`.** Le diagnostic multi-User-Agent n'a essayé **aucune**
signature de repli avant de déclarer le flux mort. Ce mécanisme existe
(`mediaSourceFactoryFor`) et il ne s'est pas déclenché. À comprendre
avant de conclure « serveur du fournisseur instable » — ce verdict est
peut-être une accusation portée à tort.

---

## 4. Ce qui vient d'être corrigé — NE LE RECASSE PAS

Quatre défauts ont été introduits les 15–16/09 par une série de commits
qui tournait en rond (huit allers-retours sur le même drapeau). Ils sont
corrigés. **Des tests lisent les fichiers réels pour les empêcher de
revenir** :

- `test/core/flag_secure_off_test.dart`
- `test/features/player/no_secure_flag_kills_image_test.dart`

| Défaut | Symptôme | Correction |
|---|---|---|
| `FLAG_SECURE` sur la fenêtre | son sans image sur HDMI | `clearFlags` dans `onCreate` **et** `onResume` |
| Plugin forçait `render_mode = texture` | efface le `surface` appris par la box | ne force plus rien |
| Watchdog de rendu désactivé | la box ne peut plus revenir au bon chemin | rétabli |
| `setPrioritizeTimeOverSizeThresholds(true)` | le plafond mémoire n'en est plus un → OOM | remis à `false` |
| `setMaxOffsetMs(12_000)` | saut au bord du direct → l'image coupe/revient toutes les 2 s | retiré |

**Si tu dois en rétablir un, tu dois d'abord le valider sur une VRAIE
box, puis mettre à jour l'en-tête du test.** C'est précisément l'étape
qui a manqué huit fois.

---

## 5. Les chantiers, par ordre de valeur

### 🔴 P1 — La fuite mémoire qui fait redémarrer l'app

**Le symptôme le plus coûteux : le client perd son image sans rien
avoir fait.**

Où regarder :
- `packages/native_video_player/android/src/main/kotlin/.../NativeVideoView.kt`
  — profils `DefaultLoadControl`, cycle de vie du lecteur, `release()`,
  `dispose()`, le pool OkHttp introduit le 16/09 (un pool **par
  lecteur** : combien d'instances vivent en même temps ?).
- `lib/core/observability/black_box.dart` — d'où viennent les
  `memoire.pressure.purge`, et ce que la purge libère réellement.
- `lib/features/tv/presentation/tv_live_preview.dart` et
  `tv_multiview_screen.dart` — les aperçus créent des lecteurs
  supplémentaires.

Questions à trancher :
1. Combien d'instances `NativeVideoView` coexistent lors d'un zap ? Les
   anciennes sont-elles vraiment libérées, ou seulement « pausées » ?
2. Le pool OkHttp par lecteur survit-il à `release()` ?
3. La purge mémoire libère-t-elle le décodeur, ou seulement du cache
   Dart ?

**Livrable attendu : une trace mémoire avant/après sur une box à 1 Go,
pas une opinion.**

### 🔴 P2 — L'app ne survit pas à une panne DNS locale

`doh_resolver.dart` existe. La Boîte noire montre qu'il n'a pas sauvé la
session. Trouve pourquoi :
- Est-il câblé sur **tous** les chemins réseau, ou seulement le lecteur ?
- `remote_profiles_repository.dart`, `subscription_backend.dart` et
  l'import EPG passent-ils par lui ?
- Le point d'entrée DoH est-il joignable **par IP** quand le DNS est
  mort ? (sinon il ne peut pas aider, par construction)

`lib/core/backend/backend_hosts.dart` gère déjà un basculement à deux
adresses. Vérifie que le coût d'un échec est **borné** : sur une box
sans DNS, chaque tentative paie un timeout, et on en enchaîne plusieurs.

### 🟠 P3 — `uaTried: 0` : le repli multi-signature ne se déclenche pas

`NativeVideoView.mediaSourceFactoryFor(userAgent)` sait rejouer un flux
sous une autre signature. Le journal dit qu'il n'a jamais été essayé.
Soit la condition d'entrée est trop stricte, soit l'erreur remontée
n'est pas celle qui le déclenche. Tant que ce n'est pas réglé, le
verdict « serveur du fournisseur instable » n'est pas prouvé.

### 🟠 P4 — EPG : `FormatException: Filter error, bad data`

`lib/features/epg/` — un XMLTV malformé ne doit jamais faire échouer
autre chose que l'EPG, ni consommer de la mémoire.

### 🟡 P5 — Le zap

Mesure le temps entre l'appui et la première image, sur une box à 1 Go,
avant et après tes changements. Sans ce chiffre, « c'est plus fluide »
n'est pas une livraison.

---

## 6. Comment vérifier — les commandes exactes

```bash
export FLUTTER_ROOT=/opt/flutter-sdk
export PATH="$FLUTTER_ROOT/bin:$PATH"

flutter gen-l10n          # ⚠️ OBLIGATOIRE AVANT analyze
flutter analyze --no-pub lib/ test/ packages/
flutter test --no-pub
```

**Le piège qui a coûté deux heures, deux fois :** `lib/l10n/generated/`
est dans `.gitignore`. Si tu lances `analyze` sans `gen-l10n`, tu vois
des erreurs de compilation **fantômes** sur des clés qui existent
pourtant dans les huit fichiers `.arb`. Ne cherche pas le bug :
régénère.

Banc de mesure de l'import (ne part pas dans le CI) :

```bash
flutter test test/benchmark/m3u_parse_bench.dart
```

Référence actuelle, à ne pas dégrader :

| | |
|---|---|
| 300 000 chaînes (53 Mo) | 2,6 s · +25 Mo |
| la même chose en recopiant le fichier | 3,9 s · +160 Mo |

C'est pour ça que le parseur lit à partir d'un **offset** et ne recopie
jamais. Si tu vois un `replaceAll` ou un `split` sur le contenu entier,
c'est une régression — un test le refuse déjà.

---

## 7. Publier — lis ceci, ça a déjà mordu

### Le numéro que le client lit

Deux numéros, jamais confondus (détail dans `AGENTS.md`) :
- `versionCode` : horodatage Android, **strictement croissant à vie** ;
- `buildLabel` : `1988` + compteur (`198861`, `198862`…), **le numéro des
  humains**, celui qu'on lit au téléphone au support.

Tu ne les calcules jamais à la main : `ci/build_label.sh` et
`ci/release_tag.sh`, appelés par les workflows.

### ⚠️ Plusieurs branches publient sur le MÊME canal

C'est arrivé **trois fois en deux jours**. Un correctif publié est
écrasé quelques minutes plus tard par une autre branche qui ne l'a pas.

- Un garde-fou existe pour le Worker et le panneau :
  `ci/guard_no_rollback.sh` — il refuse un déploiement qui ne descend
  pas de ce qui est en ligne.
- **Il ne couvre PAS les releases d'app.** C'est un trou connu, non
  bouché à ce jour.

**Avant de conclure « c'est publié », lis le commit inscrit dans la
release** :

```bash
curl -sL https://api.github.com/repos/manzilionellm-dotcom/tvking/releases/tags/seventv-latest \
  | grep -o 'Commit : [0-9a-f]*'
```

Si ce n'est pas ton commit, ton correctif n'est pas chez les clients,
quel que soit le vert affiché par GitHub.

### La règle de la maison sur la publication

> « Toujours, si on corrige quelque chose, ça se publie. »

Un correctif qui compile, passe les tests et n'atteint aucune box ne
compte pas. Le garde-fou n'est pas « ne pas publier » : un build cassé
ne produit aucun paquet, donc ne publie rien.

---

## 8. Ce qu'on attend de toi, concrètement

1. **Mesure d'abord.** Sur une vraie box à 1 Go. La Boîte noire est
   embarquée, sers-t'en — elle a plus de valeur qu'une hypothèse.
2. **Un défaut = un commit**, avec dans le message ce que tu as
   *mesuré*, pas ce que tu supposes.
3. **Chaque correctif porte son test**, qui doit échouer si quelqu'un le
   défait. Le modèle est en place dans les deux fichiers cités en §4.
4. **Ne touche pas à ce qui n'est pas dans ta liste.** Les quatre défauts
   du §4 viennent tous d'un chantier qui a débordé.
5. **Si tu trouves un cinquième problème, écris-le — ne le corrige pas
   dans le même commit.**

---

## 9. Le style du dépôt

Commentaires **en français**, abondants, qui expliquent *pourquoi* et
pas *quoi*. Quand un choix a une histoire — un incident, un arbitrage du
propriétaire, une leçon — elle s'écrit dans le fichier, datée.

Ce n'est pas de la décoration : **les quatre défauts du §4 ont été
introduits en effaçant les commentaires qui expliquaient pourquoi le
code était comme ça.** L'un d'eux disait mot pour mot « un buffer trop
gros faisait planter les box par manque de mémoire ». Il a été supprimé,
et le bug est revenu le jour même.
