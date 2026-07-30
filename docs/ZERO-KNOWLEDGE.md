# Architecture Zero-Knowledge — chiffrement côté client & panel aveugle

Objectif : le serveur (et donc le panel d'administration) ne doit avoir accès à
**aucune** donnée réelle de l'appareil — ni contenu, ni métadonnée, ni métrique.
La confidentialité est une **propriété d'architecture**, pas une permission :
même un opérateur du panel, ou un serveur compromis, ne peut rien apprendre
au-delà d'un état binaire présence/absence.

## Vue d'ensemble

```
APPAREIL (box TV)                        SERVEUR (coffre aveugle)         PANEL MAÎTRE
─────────────────                        ────────────────────────         ────────────
secret 256 bits (localStorage,           Map<slotId, {v, iv, ct}>         ADMIN_SECRET
jamais transmis)                         · slotId : 64 hex opaques        (Bearer)
  │ HKDF-SHA-256                         · ct : taille FIXE unique             │
  ├── clé AES-256-GCM  ──────┐           · AUCUN horodatage / IP / UA          ▼
  └── clé HMAC-SHA-256 ──┐   │           · éviction FIFO (sans dates)     présence/absence
                         │   │                     ▲                      UNIQUEMENT
   « resume/v1 » ──HMAC──┘   │                     │
        = slotId aveuglé     │      PUT/GET/DELETE /api/vault/[slot]
                             │                     │
   store « Reprendre » ──────┴─ pad 16 KiB ─ AES-GCM ─► enveloppe opaque
```

## Chiffrement côté client (`app/lib/zk.ts`, `app/lib/zkClient.ts`)

- **Secret d'appareil** : 32 octets CSPRNG, générés à la première utilisation,
  persistés uniquement dans le `localStorage` de la box (`tvking.v1.zk.secret`).
  Il ne transite jamais sur le réseau.
- **Dérivation** : HKDF-SHA-256 (sel public fixe) → deux clés indépendantes :
  une clé AES-256-GCM (chiffrement) et une clé HMAC-SHA-256 (aveuglement des
  identifiants). Compromettre l'une ne révèle rien sur l'autre.
- **Chiffrement** : AES-256-GCM, IV aléatoire de 12 octets par dépôt, tag
  d'authenticité de 16 octets (toute altération ⇒ échec de déchiffrement).
- **Identifiants aveuglés** : le nom logique du dépôt (ex. `resume/v1`) n'est
  jamais envoyé ; le serveur ne voit que `HMAC(clé appareil, label)` en hex.
  Non inversible, non corrélable entre appareils.

## Fermeture du canal « taille » (anti-inférence de quantité)

Le chiffrement seul ne cache pas la **taille**, or la taille révèle une
quantité (nombre de positions de lecture, etc.). Donc :

- tout payload est rembourré dans un bloc de **taille fixe unique**
  (`BUCKET_BYTES = 16 KiB`, préfixe de longueur + zéros) **avant** chiffrement ;
- le serveur **rejette** toute enveloppe dont le chiffré ne fait pas
  **exactement** 16 KiB + 16 octets de tag (`parseEnvelope`) ;
- 1 entrée ou 100 entrées ⇒ empreinte réseau et stockage identiques au bit près.

## Minimisation des données côté serveur (`app/lib/vault.ts`)

Un enregistrement du coffre est `{ v, iv, ct }` — rien d'autre, vérifié par
test. En particulier :

- pas d'horodatage : l'éviction au plafond (`MAX_SLOTS`) est **FIFO sur
  l'ordre d'insertion**, précisément pour ne pas stocker de dates ;
- pas d'IP, pas de user-agent, pas de type de contenu, pas de compte utilisateur ;
- champs excédentaires ou variantes d'encodage ⇒ rejet (forme canonique seule) ;
- `DELETE` idempotent : effacer un slot absent répond comme un slot présent
  (pas d'oracle d'existence via l'API d'écriture).

## Panel aveugle (`/panel`, `/api/panel/status`)

- Auth : `Authorization: Bearer <ADMIN_SECRET>` — le secret posé par le
  workflow GitHub « Set admin password ». Comparaison en **temps constant** ;
  **fail-closed** (503) si le secret n'est pas configuré.
- La réponse ne contient que des valeurs du type `Presence = "present" | "absent"`,
  produites par l'unique goulot `presenceOf()` :
  - état global du coffre : au moins un dépôt existe, oui/non — jamais un compte ;
  - état d'un slot précis : présent/absent — le maître doit déjà **posséder**
    l'identifiant aveuglé (communiqué hors bande par l'appareil, affiché dans
    Réglages) ; aucune énumération n'est possible.
- L'interface du panel n'affiche donc que des badges binaires. Aucune quantité
  n'existe dans le contrat d'API : la fuite est impossible côté UI par
  construction.

## Ce que voit chaque acteur

| Donnée                          | Appareil | Serveur | Panel maître |
|---------------------------------|----------|---------|--------------|
| Positions de lecture (contenu)  | ✔ clair  | ✖       | ✖            |
| Nombre d'entrées / volumétrie   | ✔        | ✖ (taille fixe) | ✖ (binaire) |
| Nature du dépôt (« reprise »)   | ✔        | ✖ (label aveuglé) | ✖    |
| Horodatages d'activité          | ✔ local  | ✖ (non stockés) | ✖     |
| Présence d'une sauvegarde       | ✔        | ✔ (opaque) | ✔ présent/absent |

## Pipeline HLS chiffré (relais d'indexation aveugle)

Le même principe s'applique au **flux média** via HLS (RFC 8216). Le flux
binaire unique est découpé en segments ; chaque segment est chiffré **sur
l'appareil** avant tout envoi, et le serveur ne fait qu'**indexer et relayer**.

Fichiers : `app/lib/hls.ts` (crypto + M3U8), `app/lib/hlsStore.ts` (relais),
`app/api/hls/[stream]` (playlist), `app/api/hls/[stream]/seg/[seg]` (chunks),
`app/lib/hlsClient.ts` (publication/lecture).

- **Chiffrement natif** : AES-128-CBC, la méthode `#EXT-X-KEY:METHOD=AES-128`
  de HLS. Un IV public par segment. Clé de contenu de 16 octets dérivée du
  secret d'appareil (HKDF, info `tvking/hls/key/v1`).
- **La clé ne quitte jamais l'appareil** : le M3U8 référence un URI de clé
  **aveugle** (`tvking-key:v1`), pas un fichier de clé servi par le relais.
- **Verrou anti-oracle** : `parseManifest` / `putManifest` **rejettent** tout
  manifeste dont l'URI de clé est `http(s)://` (ou tout schéma réseau). Le
  relais ne peut donc, même mal configuré, devenir une source de clé.
- **Chunks opaques** : les segments sont stockés/servis en
  `application/octet-stream` chiffrés. Le relais ne peut ni les déchiffrer, ni
  analyser leur contenu audio/vidéo.
- **Ce que le relais indexe** (inhérent au streaming, donc visible de lui) :
  l'ordre des segments, leurs durées (`EXTINF`) et les IV publics. La durée
  totale d'un flux est donc déductible côté serveur — c'est une limite propre à
  HLS, pas une fuite de contenu. Tout le reste (image, son, clé) lui est fermé.

Lecture avec un lecteur réel (`hls.js`) : brancher un *key loader* /
*loader* personnalisé qui intercepte l'URI `tvking-key:…` et fournit la clé
résolue localement (`hlsClient.resolveContentKey()`), sans jamais la demander au
relais. La fonction `hlsClient.fetchSegment()` illustre la chaîne complète
récupération → déchiffrement pour un lecteur maison ou un test de bout en bout.

Le panel aveugle rapporte aussi la présence d'un flux (`streams`) sous la même
forme binaire présent/absent — jamais un nombre de segments ni une durée.

## Production (Worker Cloudflare)

Le stockage de démo est une Map en mémoire (`app/lib/vaultStore.ts`). Pour le
Worker `seven-motion-backend`, brancher un KV derrière la même interface
`putSlot/getSlot/deleteSlot` : le KV ne verra exactement que ce que voit la
Map — des blobs chiffrés de taille fixe sous des clés aveuglées. `ADMIN_SECRET`
y existe déjà (workflow `set-admin-password.yml`).

## Limites connues

- Le secret vit dans le `localStorage` de la box : réinitialiser l'app détruit
  la clé, donc la sauvegarde distante devient indéchiffrable (c'est le prix du
  zero-knowledge : aucune récupération côté serveur n'est possible).
- Le serveur peut observer l'« existence » d'un trafic (horaire des requêtes) ;
  il ne le **stocke** pas, mais un adversaire réseau actif le voit. Hors modèle
  de menace ici.
- Mono-instance en mémoire pour la démo ; la sémantique est conçue pour un KV.
