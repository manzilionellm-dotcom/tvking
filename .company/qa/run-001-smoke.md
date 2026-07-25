# QA run-001 — E2E smoke TV (Playwright/Chromium 1920×1080, serveur production)
15/15 PASS, zéro erreur console/page sur tout le parcours :
1. Accueil : focus initial posé dans le contenu (CTA hero), pas perdu sur <body>
2. ArrowRight déplace le focus (D-pad)
3. Cartes porteuses de data-focus-key
4. Page détail : focus par défaut sur le CTA Lecture (data-focus-default)
5. CTA focusé → /watch/…
6. Lecteur : focus par défaut dans le scope (bouton play/pause)
7. Confinement : ArrowLeft/Up martelés → le focus ne sort JAMAIS de l'overlay (sidebar inatteignable)
8. Reprise : position persistée (tvking.v1.resume) après 5 s de lecture
9. BACK (Escape) : sortie lecteur → page détail
10. Reprise effective : lecteur rouvert à 0:06 (position sauvegardée)
11. MediaFastForward : playhead +10 s (0:06 → 0:16)
12. MediaPlayPause : pause effective (playhead immobile)
13. Enter sur carte → page détail (navigation client)
14. Retour → focus RESTAURÉ sur la carte d'origine (mémoire de route)
15. Zéro erreur console sur l'ensemble
Suites unitaires : 21/21 verts (spatial, resume, invariants catalogue).
Note : la restauration du focus vit en mémoire de session (navigation client) — perdue sur rechargement
complet de page, comportement attendu et acceptable (une box ne recharge pas entre deux écrans).
