# Décisions (run-001, 2026-07-25)
- **Périmètre TV uniquement** (instruction humaine) : zéro modification des workflows/mobile.
- **Logique pure extraite pour testabilité** : la géométrie du D-pad (`app/lib/spatial.ts`) et le
  stockage de reprise (`app/lib/resume.ts`) sont des modules purs testés en node, consommés par les
  composants client. Pas de jsdom au run-001 (coût > valeur) — les composants restent couverts par
  build + lint + tsc + usage des modules purs.
- **Stockage versionné** (loi 4) : clé `tvking.v1.resume`, enveloppe `{v:1, entries:{}}`, parse
  défensif (donnée corrompue → repart propre, jamais de crash).
- **CI qa-gates** sur push/PR : lint, typecheck, tests, build — la seule porte de merge. Pas de SBOM/
  osv-scanner au run-001 (surface deps: 3 deps runtime, lockfile commité) → backlog.
- **Pas d'auto-merge** : repo sans branch protection configurable d'ici (MODE DÉGRADÉ §0.2) ; la PR
  reste ouverte, checks verts = fin légale (a).

# Décisions (run-002, 2026-07-25) — revue des builds
- **Périmètre inchangé : TV uniquement.** Revue faite sur 31 workflows, 22 releases et 7 PR ; les
  workflows APK (mobile *et* TV) et la PR #5 « mobile premium » ne sont pas touchés. Seule l'app TV
  web de ce dépôt est modifiée.
- **Ce qui a été « conçu avant » et posé maintenant** — trois sources, toutes tracées :
  1. `docs/RESEARCH-TV-UX.md` : navigation à facettes (§5), état « Rappel activé » du modèle
     tri-state sport (§5), recherche qui cherche vraiment (§5), confort visuel / point blanc chaud
     (§3). Conçus dès le référentiel, jamais implémentés.
  2. Backlog run-001 : B3 (Ma liste réelle), B4 (recherche), B7 (boutons inertes).
  3. **PR #6 « fondations qualité TV », ouverte depuis le 2026-07-24 et jamais mergée** : frontières
     d'erreur `app/error.tsx` / `app/global-error.tsx`, télémétrie sans PII, porte de budget de
     taille. Portées ici plutôt que laissées mourir dans une branche.
- **Les tuiles de facette ne sont plus du contenu.** Une tuile « Football » ouvrait `/title/sd1`,
  c'est-à-dire une fiche détail (et un lecteur !) pour un logo. Elles portent maintenant un `href`
  propre, sont exclues de `allItems`, et ouvrent une page de facette. −24 pages absurdes, +12 utiles.
- **Stockage versionné, même contrat que la reprise** (loi 4) : `tvking.v1.mylist`,
  `tvking.v1.reminders`, enveloppe `{v:1, ids:[]}`, parse défensif, plafond LRU 200.
- **Snapshots stables pour `useSyncExternalStore`** : les lectures de stockage sont mises en cache
  par chaîne brute (`lib/collections.ts`, `lib/resume.ts`). Sans cela, un objet neuf à chaque lecture
  fait boucler React à l'infini — piège vérifié au banc, pas une précaution théorique.
- **Le contrat télécommande est pur et testé** (`lib/playerKeys.ts`) : une touche média de box ne
  peut pas être synthétisée en test, donc la table clé → action est testée séparément et le
  composant ne fait qu'appliquer l'action. Ajout de `MediaTrackNext` (absente jusqu'ici).
- **Confort visuel appliqué en logiciel** : une app web ne peut pas piloter le rétroéclairage ; on
  reproduit les deux effets documentés (voile noir = luminance perçue, voile chaud en `multiply` =
  point blanc). Désactivé par défaut, jamais imposé.
- **Budget de taille : le plus gros chunk passe de 224 à 228 Ko (+1,8 %)** — dépassement du budget
  run-001 assumé et écrit (data/perf/run-002-baseline.md) : les surfaces devenues fonctionnelles
  sont des composants client. La porte automatique porte désormais sur le total du JS client (+10 %).
- **Pas d'auto-merge, pas de PR ouverte d'office** : la branche est poussée, la décision de merge
  reste humaine (protection de main non configurable d'ici).
