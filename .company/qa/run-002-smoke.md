# QA run-002 — E2E smoke TV (Playwright/Chromium 1920×1080, serveur de production)

29/29 PASS, zéro erreur console/page sur tout le parcours.

| # | Vérification | Preuve observée |
|---|---|---|
| 1 | Accueil rendu | titre non vide |
| 2 | CTA du hero = vraie destination | `href=/watch/hero-ucl` (était un `<button>` inerte) |
| 3 | Tuile « Football » → page de facette | `href=/sport/football` (était `/title/sd1`) |
| 4 | Page facette remplie | rangées : En direct \| À venir \| Replays \| Analyses |
| 5 | Chip de facette active | `aria-current="page"` sur Football |
| 6-8 | « + Ma liste » : bascule, état ON, persistance après rechargement | `aria-pressed=true`, « ✓ Dans ma liste » |
| 9-10 | Page Ma liste = vraie sélection | rangée « Ma liste » contenant l'élément sauvegardé |
| 11-12 | « Me rappeler » sur un À venir | « ✓ Rappel activé », `aria-pressed=true` |
| 13 | Carte À venir porte le drapeau | pastille « 🔔 Rappel » sur la carte su1 |
| 14 | Rangée « Mes rappels » | présente sur /list |
| 15 | Recherche par suggestion | « 2 résultats pour « Yoga » » |
| 16 | Clavier D-pad | H-I-I-T → « 2 résultats pour « HIIT » », 2 cartes |
| 17 | Effacement | résultats retirés |
| 18-20 | Confort visuel « Nuit » | `--comfort-dim=0.18`, persiste entre écrans, voile `pointer-events:none` |
| 21 | MediaTrackNext | /watch/fp1 → /watch/hero-masterclass |
| 22 | BACK (Escape) | lecteur → fiche |
| 23 | Reprise persistée | `tvking.v1.resume` = `{"v":1,"entries":{"fp1":{"pos":5,"dur":40,…}}}` |
| 24 | Rangée « Reprendre » réelle | 1re carte = le programme réellement lu (fp1) |
| 25-27 | D-pad sur la recherche | focus par défaut sur la 1re suggestion, → suggestion suivante, ↓ atteint le clavier |
| 28 | D-pad sur une page de facette | ↓ descend des chips vers les cartes |
| 29 | Aucune erreur console | 0 message d'erreur sur l'ensemble du parcours |

Suites unitaires : **61/61 vertes** (spatial, resume, collections, search, playerKeys, telemetry,
invariants du catalogue et des facettes).

Non couvert ici (inchangé depuis run-001) : appareil physique (télécommande réelle, overscan réel),
et les métriques de lecture S3 (TTFF, zapping) qui restent non mesurables tant que le lecteur est un
mock — backlog B1.
