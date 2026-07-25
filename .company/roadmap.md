# Roadmap tvking-tv
## Fait (run-001)
- Baseline mesurée ; CI qa-gates ; tests unitaires logique pure ; focus scope lecteur + BACK + media keys ;
  restauration du focus ; reprise de lecture persistée v1.
## Prochain (run-002+, ordre I9)
1. Brancher données réelles (API sport / catalogue) derrière le modèle MediaItem existant.
2. Lecteur vidéo réel (HTML5 <video> HLS) derrière un PlayerService — TTFF/zapping mesurables, watchdogs S4
   (écran noir, spinner infini) télémétrés.
3. « Ma liste » réelle (persistée v1) + états vides.
4. Recherche fonctionnelle (filtre local FTS sur le catalogue).
5. E2E chemin critique (Playwright, Chromium préinstallé) : accueil → carte → détail → lecture → BACK.
6. SBOM + osv-scanner en CI ; goldens visuels des écrans TV.
7. MODULE D/V : nécessite accès stores/analytics — CHECKLIST humaine.
