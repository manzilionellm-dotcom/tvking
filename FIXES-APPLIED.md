# FIXES-APPLIED — Corrections appliquées durant l'audit

Branche : `claude/audit-mobile-tv-delivery-ghn12o`. Chaque groupe = un commit
dédié avec tests (rollback ciblé par `git revert`). Point de restauration
global : `25d7cb3` (voir ROLLBACK-PLAN.md).

## Groupe 1 — EPG (`6433431`)

| # | Correction | Test |
|---|---|---|
| M-C1 | `resyncEpgAll` lisait la colonne inexistante `id` → resync 12 h morte. Corrigé sur `external_id`, extrait/testé, échec journalisé. | epg_resync_ids_test |
| M-C2 | `epg_programs` doublait à chaque sync. Index UNIQUE `(channel_id, start_time)` + purge des doublons hérités + INSERT REPLACE. | epg_dedup_test |
| M-H4/H5 | Sync XMLTV : timeouts (send 30 s, inter-chunk 60 s) + client IPTV (certs auto-signés + DoH). | — |
| — | `parseInIsolate` : le port onExit faisait la course avec les écritures SQLite → faux « isolate terminé » après un parse réussi. | epg suite |
| M-H6 | `SmartSearch._docCache` vidé à la suppression de playlist (fuite mémoire). | — |

## Groupe 2 — Données/réseau/cache (`f097b22`)

| # | Correction |
|---|---|
| M-H7 | Verrou de refresh par playlist (double fetch/parse concurrent). |
| M-H8 | DELETE+INSERT de refresh en transaction atomique (fenêtre « source vide »). |
| M-H9 | Cinéma/Séries → playlist ACTIVE (au lieu de la plus récente). |
| — | Dédup in-flight VOD / Séries / ShortEpg. |
| — | Index SQLite v7 `idx_channels_page` (pagination) ; purge orphelins 1×/session. |
| — | `dispose()` du XtreamClient de calibration (fuite de sockets). |

## Groupe 3 — Sécurité (`58fe41d`)

| # | Correction |
|---|---|
| S-C1 | Worker fail-closed : suppression des replis `dev-secret` (×5). |
| S-C2 | Suppression du repli `change-me` (bootstrap super_admin). |
| S-M2 | Comparaisons de secrets à temps constant (JWT + PBKDF2). |
| S-H1 | Backend crash reçoit l'erreur caviardée (fin de fuite d'identifiants). |
| S-M1 | SecretRedactor : motifs élargis + en-têtes + chemins sans extension (+3 tests). |
| S-H3 | `build-prive.yml` : garde de branche sur la release cliente. |
| S-M3 | `publish-*.yml` : run_id en variable d'env + validation (anti-injection). |

## Groupe 4a — Lecteur mobile (`8604f5d`)

M-C3 fuite mpv après fermeture · M-C4 garde anti double-ouverture · M-H1
spinner infini (borne `_isPlaying`) · M-H2 EOF impasse silencieuse · M-H3
cycle de vie (pause/reprise, sauvegarde position) · watchdog VOD · gardes
`mounted`/génération. (71 tests player verts.)

## Groupe 4b — Boot & cycle de vie (`3e1669a`)

M-C5 écran noir au boot · M-C6 dédup `RemoteSourceRepository.sync` (+2 tests)
· M-H12 disjoncteur BootGuard mobile + SafeMode · M-H13 splash infini · M-H14
sondage d'activation mort · M-H11 MAJ sûre (timeout/plafond/vérif taille) ·
timers realtime annulés en veille · timer de pub de secours.

## Groupe 5 — App TV (`66cbce7`)

T-C1 lecteurs empilés (Guide/Multi-vue) · T-H1 watchdog en veille · T-H2
Cinéma/Séries état d'erreur + « Réessayer » · T-M1 toasts TV (Overlay) · T-M2
focus initial · T-M3 dialogues de sortie l10n · T-M4 `openTvPlayer` (garde
sur 10 sites) · T-M5 veille anti burn-in 4 templates · garde de build
media_kit. (105 tests TV verts.)

## Reportés au backlog (avec justification)

M-H10 refonte retry XtreamClient · M-H16 état par profil (8 dépôts) · M-H17
consentement MAJ · S-C3 auth backup cloud · S-H2 scission client TLS · S-H4/5
durcissement admin · S-M4-M7 + S-B9-12 · T-H3/T-M6 pagination Modèles C/D ·
B-4 montées majeures · B-8 lockfile · B-9 SBOM. Détail et raisons dans
`.company/backlog.json`, AUDIT-*.md et SECURITY-AUDIT.md.

## Principe respecté

Aucune fonctionnalité supprimée ; aucune réécriture massive ; aucune
dépendance lourde ajoutée ; aucun `applicationId` ni clé de signature
modifiés ; séparation mobile/TV renforcée (jamais mélangée).
