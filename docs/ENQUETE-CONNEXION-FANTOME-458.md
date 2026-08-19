# Enquête « connexion fantôme » — ligne Xtream 1 connexion (19/08)

## Le symptôme

Le client regarde un **film** (Cinéma), quitte le lecteur, ouvre une **chaîne
en direct** → « Limite de connexions atteinte (1/1) ». Boîte noire : le panel
répond **458 + page HTML** au lieu du flux, et `player_api.php` confirme
`Active · 1/1`. Quelque chose tient donc réellement la ligne à ce moment-là.

## ⚠️ LE TEST À FAIRE D'ABORD (1 minute, tranche la moitié des hypothèses)

**But : savoir si la session fantôme est côté APP ou côté FOURNISSEUR.**

1. Quitter toute lecture (retour à l'accueil), **attendre 1 minute** montre
   en main. Ne rien toucher d'autre (pas de zapping, pas de bande-annonce).
2. Ouvrir la Boîte noire (Réglages → appui long sur la version) et appuyer
   sur **« Vérifier le compte »**.
3. Lire la ligne `Compte : Active · connexions X/1` :
   - **`0/1` au repos** → la ligne SE LIBÈRE : le coupable est dans l'app.
     Les horodatages en millisecondes du journal (événements `creneau`,
     `relay`, `epg`, `sync`) diront QUI tenait la ligne au moment du refus.
   - **`1/1` au repos** (après 1 min sans aucune lecture) → session fantôme
     **côté fournisseur** : son panel garde la session ouverte bien après la
     fermeture de la socket. Aucun code ne peut aller plus vite — c'est à
     lui d'ajuster (timeout de session de son panel). Le dire clairement au
     client plutôt que d'empiler des correctifs.

Refaire ensuite le scénario exact (film → quitter → chaîne) et, si le refus
revient, ouvrir la Boîte noire **tout de suite** : copier le rapport. Les
nouveaux événements `creneau` y encadrent chaque fermeture/ouverture à la
milliseconde près.

## Ce que cette version change (v. branche `claude/7motion-android-tv-compat-e0rtyp`)

### Correctif : l'URL directe jouée « en douce » à l'ouverture

La vue vidéo native joue à son rattachement `_pendingUrl ?? _lastUrl ??
initialUrl`. Le lecteur TV plein écran était créé avec `initialUrl` = l'URL
panel **directe**. Quand le rattachement (~100-300 ms) arrivait avant que
l'écran ait obtenu le créneau réseau et posé l'URL du relais — ce qui est
quasi systématique au retour d'un film, car le créneau doit d'abord démonter
l'aperçu d'accueil (jusqu'à 1,2 s) — **ExoPlayer ouvrait sa propre connexion
au panel, hors relais et hors créneau**, qui se chevauchait ensuite avec
celle du relais → 458 sur une ligne 1 connexion. Les cinq correctifs
précédents (StreamSlot, closeOtherPlaybacks…) ne pouvaient pas l'attraper :
ce chemin les contournait tous. Le lecteur est maintenant créé **sans**
`initialUrl` : rien ne se joue tant que le chemin officiel (créneau →
relais/direct) n'a pas décidé de l'URL. Tests :
`test/features/player/native_video_controller_attach_test.dart`.

### Correctif : la sortie du lecteur est désormais ATTENDUE par le suivant

`dispose()` est synchrone : la fermeture réseau (stop natif + session
relais) partait sans être attendue, et l'écran se désinscrivait du créneau
dans la foulée — le prochain `claim()` ne trouvait plus personne à démonter
et ouvrait pendant que l'ancienne socket se fermait. Nouveau :
`StreamSlot.handOff()` — la fermeture devient un **détenteur de transition**
que le prochain `claim()` attend (plafonné 1,2 s, fail-open, retrait
automatique). Tests : `test/core/playback/stream_slot_test.dart`.

### Correctif : l'anti-gel ne « répare » plus une pause volontaire

Un film en pause > 15 s était vu comme un gel → réouvertures silencieuses
(`setUrl`) : le film repartait tout seul ET rouvrait une connexion panel.
La pause volontaire ré-arme maintenant l'horloge anti-gel.

### Nouveauté (demande exploitant) : « pause longue = connexion rendue »

Film en pause **> 20 s** → `stop()` (socket panel fermée), position
mémorisée, l'écran de pause reste affiché. Reprise (OK/lecture/seek/retour
d'arrière-plan) → ré-ouverture + seek à la position. Jamais en direct, jamais
sur un fichier local. Pendant la pause, la file de téléchargements peut
profiter de la ligne (elle est re-suspendue à la reprise). Politique testée :
`test/core/playback/vod_pause_release_policy_test.dart`.

### Instrumentation (pour trancher les hypothèses restantes SUR LA BOX)

- Journal de la Boîte noire horodaté à la **milliseconde**.
- `creneau` : sortie du lecteur (début/fin de fermeture réseau, durée du
  stop natif), attente réelle de `claim()` (avec alerte « BUDGET ATTEINT »
  si un démontage n'a pas fini dans les 1,2 s), pause longue rendue/reprise.
- `epg` : début/fin/durée de chaque téléchargement `xmltv.php` — certains
  panels non standard comptent ce téléchargement comme une connexion ; s'il
  y a corrélation entre « guide en cours » et 458, on le verra noir sur
  blanc.
- `sync` : chaque re-import automatique du catalogue (veilleur 60 s,
  synchro panel) avec la source et le déclencheur.

## Hypothèses restantes et comment le journal les départage

| Si le journal montre… | Alors… |
|---|---|
| 458 dans la seconde qui suit « Sortie du lecteur → fermeture réseau lancée » | Le panel garde la session quelques secondes après la socket (hyp. A courte) : le calendrier 458 (~45 s) doit finir par passer. |
| « Vérifier le compte » = 1/1 au repos 1 min après tout arrêt | Session fantôme côté fournisseur (hyp. A longue) : à traiter chez lui. |
| 458 pendant « Téléchargement du guide (xmltv) démarré » | Le panel compte xmltv comme une connexion (hyp. B) : il faudra suspendre la synchro EPG pendant les lectures. |
| « Créneau obtenu après ~1200 ms — BUDGET ATTEINT » récurrent | Un démontage ne finit jamais dans le budget : chercher l'événement de fermeture manquant juste avant. |

## À ne pas faire (rappels)

- Ne pas publier `build-android.yml` avec `make_release=true` (116 clients).
- Ne pas déclencher la cascade de sondes multi-signatures sur une ligne
  1 connexion.
- Ne pas annoncer « corrigé » sans preuve terrain (journal + test du haut).
