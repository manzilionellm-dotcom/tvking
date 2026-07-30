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

# Décisions — multiplexage M3U, bascule de chaîne et plan d'administration
- **Un slot pool par compte maître, pas un sémaphore global** : la contrainte réelle est « N
  connexions simultanées par ligne d'abonnement ». Deux comptes = deux budgets indépendants.
- **Bascule (`starved`) plutôt que coupure** : un flux évincé qui a encore des spectateurs ferme sa
  montée et rend son slot, mais garde son `Broadcaster`, son cache et ses sockets clientes. Les
  clients tiennent sur leur file (`EDGE_CLIENT_QUEUE_BYTES` = durée de couverture au débit
  d'égress) ; passé `EDGE_STARVE_GRACE_MS`, ils sont terminés proprement plutôt que laissés muets.
- **Le permis libéré est remis au demandeur** (file avec priorité en tête), sinon le flux qui
  s'efface reprend son propre permis dans le même tick et la bascule n'a jamais lieu — bug réel,
  couvert par un test dédié dans `slots.test.ts`.
- **Une chaîne basculée se remet en file sans droit de bascule** : sinon deux chaînes peuplées se
  chassent l'une l'autre indéfiniment.
- **Délai de décantation (`EDGE_SWAP_SETTLE_MS`, 100 ms) avant de rendre le slot** : fermer une
  socket localement ≠ l'origine la voit fermée. Mesuré : sans ce délai, l'origine du test e2e
  observait deux requêtes simultanées lors d'une bascule ; avec, chaque requête arrive alors que
  l'origine n'a qu'une socket ouverte.
- **Empreinte d'appareil maître** (`edge`/`vlc`/`kodi`/`tivimate`/`exoplayer`) vérifiée à chaque
  ouverture par `assertMirrorsMasterSignature` : toute variation par client serait une poignée de
  corrélation pour l'origine, donc c'est une faute, pas un détail.
- **Plan d'administration désactivé sans jeton** : cette API peut faire pointer le proxy vers une
  nouvelle origine. Jeton comparé en temps constant ; identifiants de compte exposés par NOM
  seulement ; sessions = identifiants opaques (le tableau de bord ne peut pas montrer ce que le
  proxy refuse de collecter).
- **Refus de redimensionner un budget sous des flux vivants** : changer la capacité d'un pool en
  cours d'usage casserait la comptabilité des permis — l'API répond 400 et demande l'arrêt.
- **Vérifié au navigateur (Chromium + Playwright)** : le tableau de bord a révélé deux bugs que les
  tests ne pouvaient pas voir — CSP `default-src 'none'` qui bloquait son propre `fetch` SSE, et
  annulation comptée comme refus dans les métriques.
