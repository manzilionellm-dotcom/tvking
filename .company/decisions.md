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

# Décisions — proxy de bord (server/edge/)
- **Service Node autonome, pas un route handler Next.js** : l'invariant « une seule connexion
  montante » n'existe que par processus. En serverless (instances multiples, invocations
  indépendantes), chaque instance ouvrirait sa propre montée — le contraire du but visé.
- **Mutex sur le cycle de vie du hub, pas un booléen** : chaque `await` (slot global, TCP, TLS,
  en-têtes) est une fenêtre de course entre « est-ce ouvert ? » et « ouvre ». Le compteur de preuve
  s'incrémente à l'appel de `open()`, pas à sa résolution, pour attraper deux montées parallèles.
- **Plafond global = sémaphore + éviction LRU des flux sans spectateur, puis 503** : au-delà du
  plafond on refuse honnêtement plutôt que d'ouvrir une seconde connexion en silence.
- **En-têtes montants construits, jamais transférés** : `StreamHub` ne reçoit pas les en-têtes
  clients (frontière structurelle). `Via` (RFC 9110 §7.6.3) et pas de `Forwarded` (RFC 7239), dont
  l'objet est de révéler la chaîne cliente. Les journaux n'enregistrent aucun identifiant client et
  rédigent les URL d'origine (jetons d'abonnement).
- **Cache par référence, jamais de copie** ; file par abonné bornée en *drop-oldest* (le direct
  privilégie la fraîcheur) avec comptage des pertes ; cache vidé à l'arrêt d'un flux (rejouer du
  direct périmé serait pire qu'un démarrage propre).
- **Linger (15 s par défaut)** : fenêtre de zapping — revenir sur un flux quitté ne rouvre rien.
- **Périmètre non couvert (assumé)** : collapse d'une playlist HLS segmentée, TLS/auth côté LAN.
