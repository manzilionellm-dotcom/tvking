# Stabilité de lecture — Zuno (branche `claude/zuno-stabilite`)

Ce document sépare ce qui a été **exécuté sur cette machine** de ce qui
ne peut se voir **que sur une box**. Rien ici n’a été publié
(`publish` n’a pas été lancé). Le binaire « 4K Player » et le Worker
Cloudflare n’ont pas été touchés.

## Ce qui a changé

Coupure réseau, gel, fin de flux : le lecteur attend **1 s, puis 2 s,
4 s, puis 8 s** (plafond) avant de ré-ouvrir. Huit essais silencieux
côté natif, puis l’écran prend le relais avec la même attente, puis
s’arrête et propose « Réessayer ».

Pendant cette attente :

- le volume reste à 0 jusqu’à la **nouvelle** image ou le nouveau
  « je joue » (l’ancien tampon HDMI, surtout en AC-3, ne doit pas
  parler en même temps que le flux qu’on rouvre) ;
- un second essai n’est pas programmé tant que le premier attend ;
- si une image a déjà été vue **et** que l’adresse est la même, on ne
  pose pas le panneau opaque (fond sombre) par-dessus. Le natif garde
  une petite copie de la dernière image (au plus 1280×720, une seule,
  pas une file). Sans copie (coupure dans les premières secondes), le
  panneau avec le numéro et le nom de la chaîne reste.

Films et séries : la même attente, et on rouvre **à la seconde** où
on en était, pas au générique. La rangée d’accueil et la colonne
Films / Séries s’appellent « Reprendre où tu t'es arrêté ». OK lance
5 secondes avant l’endroit quitté (jamais en dessous de 0). Moins de
30 secondes, ou l’épisode « suivant », partent du début.

Le tampon de démarrage (**1 s**) et le groupement du zap (**180 ms**)
n’ont pas été allongés. Les monter a déjà laissé des chaînes sur le
logo (v99–v101).

## Prouvé par un test exécuté

Machine : Linux, Flutter 3.47.5 (Dart 3.13.4), Gradle 8.10.2,
OpenJDK 21. Pas de box, pas de flux IPTV.

### Kotlin (`logic-test`, `gradle test`)

BUILD SUCCESSFUL. Tous les tests de ce module sont passés, y compris
les anciens (session, son exclusif, voix, gain).

Nouveaux (`ReconnectPlanTest`) :

- délais : 1000, 2000, 4000, puis 8000 ms ;
- un essai déjà armé n’en programme pas un second ;
- au 9e essai, on abandonne ;
- un zap remet le compteur à 0, la même adresse le garde ;
- le volume ne remonte qu’une fois, au signal « nouvelle session » ;
- image déjà vue + même adresse → pas de panneau opaque ;
- annuler l’attente ne remet pas le compteur à zéro.

Mesures imprimées par le test (cette exécution) :

```
MESURE zap_20_microsecondes=83
MESURE budget_app_ms=1180 tampon_ms=1000 zap_ms=180
MESURE decision_reconnexion_20_microsecondes=7 dernier_delai_ms=8000
```

`zap_20_microsecondes=83` est le test **déjà là** (20 prises de son,
un seul propriétaire). Ce code (`ExclusiveAudio`) n’a pas été modifié.
83 microsecondes, c’est le temps de décider qui a le son, pas le temps
d’afficher une image.

`budget_app_ms=1180` = 180 ms (on groupe les touches Haut/Bas) + 1000 ms
(données minimum avant de lancer la lecture). Ces deux chiffres sont
**les mêmes qu’avant** cette branche. Leur somme est sous 2 s. Ce n’est
pas le temps jusqu’à la première image : le réseau et le décodeur n’y
sont pas.

`decision_reconnexion_20_microsecondes=7` : vingt calculs de délai et
de « garder l’image », 7 microsecondes. C’est le coût de la décision,
pas une ouverture de chaîne.

### Flutter (`flutter test`)

Passés, cette exécution :

- `test/features/player/` (bail, époque, secours d’adresse, pistes,
  relais, **reconnect_plan_test**) — 42 tests, dont la mesure :

```
MESURE zap_20_microsecondes=148
MESURE budget_app_ms=1180 tampon_ms=1000 zap_ms=180
MESURE decision_reconnexion_20_microsecondes=39 dernier_delai_ms=8000
```

Le 148 microsecondes est le même test de bail qu’avant (code du bail
non modifié). Le 39 microsecondes est la décision de reconnexion, en Dart.

- `test/features/cinema/resume_start_test.dart` — 5 tests, passés :
  film à 2 min 05 → reprise à 2 min 00 ; épisode à 10 min → reprise à
  9 min 55 ; épisode « suivant » → début ; moins de 30 s ou « depuis
  le début » → début ; la rangée d’accueil garde le film et l’épisode,
  pas le titre trop court.
- `test/features/cinema/watch_progress_test.dart` — 7 tests, passés.
- `test/features/tv/home_engagement_test.dart` — 11 tests, passés.

Suite Flutter complète (`flutter test` à la racine de `android-app`) :
**282 tests passés, 1 ignoré**, 0 échec (cette exécution, environ 14 s).

`flutter analyze` sur les fichiers Dart touchés : plus d’avertissement
nouveau après retrait du champ inutilisé. Les infos `prefer_const`
déjà présentes sur l’écran du direct n’ont pas été reprises.

## Pas prouvé ici (il faut une box)

`NativeVideoView.kt` (ExoPlayer, SurfaceView, copie d’image) **n’a pas
été compilé** : pas de SDK Android sur cette machine, et le workflow
`build-zuno-tv.yml` n’a pas été lancé. Seule la règle pure
(`ReconnectPlan.kt`) a été compilée et exécutée.

Donc on ne sait pas, tant qu’une box ne l’a pas fait :

- si la copie d’image couvre vraiment la surface (sur certaines puces
  la SurfaceView passe devant les autres vues : on verrait du noir
  quand même) ;
- si le volume à 0 coupe bien l’ancien AC-3 sur la barre HDMI ;
- en combien de secondes la première image arrive vraiment ;
- si une coupure Wi-Fi réelle revient toute seule.

Le tampon de 1 s n’a pas été baissé. Descendre sous 1 s de données
avant de jouer n’a pas été essayé : le risque est une image qui
saute, et ça ne se juge pas dans un test sans flux.

## Test simple sur la box

Une seule chaîne qui démarre d’habitude, et un film. Prévoir une
montre. Ne pas publier l’APK : build avec `test_box=true` et
`publish=false` seulement.

1. Ouvrir une chaîne. Attendre que l’image tourne **au moins 10 secondes**
   (la copie n’existe pas avant).
2. Couper le Wi-Fi 20 secondes, puis le rallumer.
3. Noter : est-ce que la dernière image reste (pas un écran noir plein),
   est-ce qu’on entend **une** chaîne au retour, est-ce que ça revient
   sans appuyer.
4. Refaire en coupant le Wi-Fi **dans les 3 premières secondes**. Là,
   une carte avec le numéro et le nom est normale (pas encore de copie).
5. Zap : cinq appuis simples sur Haut. Pour chaque chaîne qui démarre
   d’habitude vite, dire si la carte « chargement » reste plus longtemps
   qu’avant, à vue de nez au-dessus de 2 secondes. Cette machine n’a
   pas mesuré ce temps-là.
6. Lancer un film, regarder deux minutes, Retour. Sur l’accueil, la
   rangée « Reprendre où tu t'es arrêté » doit montrer le film. OK doit
   reprendre près de ces deux minutes, pas au début. Pareil pour un
   épisode.
7. Pendant le film, couper le Wi-Fi 15 secondes puis le rendre. Le film
   doit repartir près de la même minute, pas au début, et pas afficher
   « lecture impossible » au premier trou.

Si l’étape 2 montre un écran noir, ou si deux sons se mélangent, le
correctif n’est pas bon sur cette puce. Le ramener tel quel, avec le
modèle de la box.

## Conflits possibles avec les autres branches

Non faits ici : qualité d’image / FFmpeg (`claude/zuno-image`), cache
du catalogue (`claude/zuno-catalogue-cache`).

Fichiers en commun probables :

| Fichier | Ici | Risque |
| --- | --- | --- |
| `NativeVideoView.kt` | reconnexion, volume, copie d’image, enveloppe `FrameLayout` | **fort** avec `zuno-image` (décodeur, pistes, FFmpeg). Le tampon 5 s / 45 s / 1 s / 2 s et le choix FFmpeg audio n’ont pas été changés. |
| `native_video_player.dart` | `holdFrame`, `nativeRetrying`, `keepPicture` | moyen si l’autre branche touche `setUrl` |
| `tv_player_screen.dart` | attente avant ré-ouverture, panneau | moyen |
| `tv_vod_player_screen.dart` | reconnexion du film à la même seconde | faible |
| `tv_cinema_screen.dart` | libellé de la colonne seulement | **moyen** avec `zuno-catalogue-cache` s’ils réécrivent cet écran |
| `tv_home_rails.dart` | libellé de la rangée films/séries | faible |
| `tv_cinema_common.dart` | `openVod` passe par `ResumeStart` | faible |

Pas touchés : dépôt du catalogue, index, cache disque, renderers
FFmpeg vidéo, `LoadControl` (durées identiques), release `zuno-tv`,
workflow de publication.
