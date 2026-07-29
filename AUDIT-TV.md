# AUDIT-TV — DEFEW TV / SEVEN (Android TV & Box, `lib/main_tv.dart`, ExoPlayer)

Date : 2026-07-29 · Commit audité : `25d7cb3` · Méthode : revue exhaustive
(fermeture d'imports, focus D-pad, télécommande, lecteur, listes lourdes,
veille) + baseline outillée.

## Contrainte critique du build TV — VÉRIFIÉE

Fermeture transitive des imports de `lib/main_tv.dart` calculée : **194
fichiers Dart, 0 import `media_kit`**. L'isolation tient par injection de
plateforme (`TvPlayerBuilder` / `registerTvPlayer` : Windows injecte
media_kit, Tizen AVPlay, Android TV rien → ExoPlayer natif). Aucun import
conditionnel ni `deferred` risqué.
→ **Verrouillé durablement** par un test de garde statique qui recalcule la
fermeture à chaque CI : `test/features/tv/tv_media_kit_import_guard_test.dart`.

## Critiques

| ID | Constat | Statut |
|---|---|---|
| T-C1 | Lecteurs empilés : Guide (« Revoir ») et Multi-vue poussés PAR-DESSUS le lecteur qui continue de décoder et de tenir sa connexion → 2-3 ExoPlayer, échec garanti sur compte 1-connexion | **CORRIGÉ** (pause + libération avant push, relance propre au retour) |

## Hauts

| ID | Constat | Statut |
|---|---|---|
| T-H1 | Watchdog anti-gel actif pendant la VEILLE : 5 reconnexions amont en arrière-plan puis état fatal → écran d'erreur au réveil de la box | **CORRIGÉ** (timers annulés sur paused, machines ré-armées + flux rechargé sur resumed) |
| T-H2 | Écrans Cinéma/Séries sans try/catch ni état d'erreur : une DatabaseException = squelette de chargement infini sans issue | **CORRIGÉ** (état d'erreur + « Réessayer » focusable) |
| T-H3 | Multi-vue : tuiles ouvrant l'URL brute (ni relais 1-conn, ni DoH, ni UA gagnant) | **PARTIEL** : l'empilement (T-C1) est corrigé ; le passage des tuiles par resolveSource → B-18 |

## Moyens

| ID | Constat | Statut |
|---|---|---|
| T-M1 | SnackBar TV jamais affichés (aucun Scaffold dans l'arbre) : « Multi indisponible », « Replay indisponible », « Code parental mis à jour » muets | **CORRIGÉ** |
| T-M2 | Focus initial absent (Guide, Réglages affichage, À propos, Collections) : D-pad « mort » à l'ouverture | **CORRIGÉ** (autofocus premier élément) |
| T-M3 | Dialogues de sortie sans autofocus + libellés durs en français (Modèles B/D) | **CORRIGÉ** (réutilisation de showExitDialog l10n) |
| T-M4 | Garde anti-double-lecteur absente sur 10 des 12 points d'ouverture (télécommandes qui doublent le OK) | **CORRIGÉ** (helper partagé `openTvPlayer` + verrou de process) |
| T-M5 | Écran de veille anti burn-in seulement sur le Modèle A (B/C/D marquent les OLED) | **CORRIGÉ** (watcher déplacé au-dessus des 4 templates) |
| T-M6 | Modèles C/D : passe complète du bouquet sur le thread UI à chaque événement du flux (gel récurrent proportionnel au catalogue, matérialisation complète en RAM) | **DOCUMENTÉ** (B-19 : aligner sur la pagination keyset de tv_live_screen) |

## Bas

Pagination déclenchée depuis itemBuilder (fragile) ; liste passée au lecteur
limitée aux pages chargées (zap borné) ; TvFocusable sans didUpdateWidget ;
textes durs non localisés Modèle D → consignés au backlog (B-20…B-23).

## Séquences agressives télécommande — protections constatées

Zap différé 150 ms sans connexion sur les chaînes traversées ; aperçu live
anti-rebond 600 ms (×2 petite box) + répit 1,8 s au retour de route ;
débounce catégorie 220 ms / aperçu 120 ms ; fenêtre 1,2 s sur le code caché ;
ValueNotifier ciblés (pas de setState racine). Combinées au nouveau verrou
`openTvPlayer` et aux corrections T-C1/T-H1 : plus aucun chemin connu où une
rafale de touches empile des lecteurs ou sature les connexions.

## Gros catalogues — état

Protections en place : pagination keyset SQLite (150/page) sur l'écran Live,
plafonds RAM adaptatifs (`DeviceMemory.channelCap`), cache images plafonné
(TvMemoryGuard 260/48 Mo, 160/24 Mo petite box, purge sur pression mémoire),
`memCacheWidth/Height` sur 100 % des images TV, préchargement borné
(10/rangée, LRU 600), RepaintBoundary sur affiches, nouvel index SQLite v7
couvrant le prédicat de pagination. Reste connu : Modèles C/D hors
pagination (B-19).

## Points forts confirmés (à préserver)

Machines à états critiques extraites en logique pure testée
(FreezeRecoveryPolicy, StreamStabilityMonitor, AutoplayPolicy,
QualityLadder) ; discipline mémoire de bout en bout ; anti-saturation
télécommande systématique ; isolation media_kit par injection.
