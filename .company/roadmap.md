# Roadmap tvking-tv
## Fait (run-001)
- Baseline mesurée ; CI qa-gates ; tests unitaires logique pure ; focus scope lecteur + BACK + media keys ;
  restauration du focus ; reprise de lecture persistée v1.
## Fait (run-002) — « ce qui était conçu et jamais posé »
- Navigation à facettes (12 pages statiques discipline/thème) + chips ; les tuiles de facette
  n'ouvrent plus une fiche détail pour un logo.
- « Ma liste » et « Me rappeler » réellement persistés (+ drapeau « Rappel » sur la carte, rangée
  « Mes rappels », états vides) ; CTA du hero réels.
- Recherche locale insensible aux accents + clavier D-pad + état vide.
- Rangée « Reprendre » alimentée par la reprise persistée (le store était écrit, jamais relu).
- Touche MediaTrackNext ; contrat télécommande extrait en module pur testé.
- Frontières d'erreur + télémétrie sans PII (récupérées de la PR #6, jamais mergée).
- Confort visuel (luminance + point blanc chaud) dans Réglages.
- Porte de budget de taille du JS client dans qa-gates.

## Prochain (run-003+, ordre I9)
1. Brancher données réelles (API sport / catalogue) derrière le modèle MediaItem existant.
2. Lecteur vidéo réel (HTML5 <video> HLS) derrière un PlayerService — TTFF/zapping mesurables, watchdogs S4
   (écran noir, spinner infini) télémétrés.
3. Notifications réelles pour les rappels posés (B9) — exige une surface native/box.
4. E2E chemin critique versionné dans le dépôt (Playwright, Chromium préinstallé) : le smoke
   run-002 (29 checks) est joué à la main, il doit devenir une suite commitée.
5. Saisie vocale de la recherche (B11) ; EPG live (B12, bloqué par les données réelles).
6. SBOM + osv-scanner en CI ; goldens visuels des écrans TV.
7. MODULE D/V : nécessite accès stores/analytics — CHECKLIST humaine.
