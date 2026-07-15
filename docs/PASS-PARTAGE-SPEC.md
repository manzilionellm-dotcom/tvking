# Pass Partage (« regarder ensemble » / inviter un ami) — spécification

But : un abonné **payant** (l'inviteur) fait profiter un **nouvel appareil**
(l'invité : sa femme, un ami — sans abonnement ni source à lui) d'un accès
limité, pour tester ou pour regarder un match ensemble. Puis l'invité doit
prendre un abonnement.

## 0. Deux façons d'inviter (l'inviteur choisit)

### Mode A — « Regarder ENSEMBLE » (le match / un film)
- L'inviteur **choisit une chaîne** de sa liste (le match) → elle est
  **partagée** à l'invité (nom + flux + logo seulement, PAS toute la liste).
- Accès par **SESSION** : **c'est l'inviteur qui connecte** l'invité.
  - Une session dure **~5 heures**, puis **déconnexion automatique**.
  - **Fenêtre de 2 jours** : pendant ces 2 jours, l'inviteur peut
    **reconnecter** l'invité (nouvelle session de 5 h), autant de fois qu'il
    veut.
  - La reconnexion se fait **uniquement côté inviteur** (l'invité ne peut pas
    se reconnecter seul). ⟵ *à confirmer*
  - Fin de session mais encore dans les 2 jours → l'invité voit
    « **Demande à ton ami de te reconnecter** ». ⟵ *à confirmer*

### Mode B — « TEST » (juste regarder, pas forcément ensemble)
- L'inviteur donne un accès d'essai simple, en **choisissant la durée** :
  **12 heures**, **1 jour** ou **2 jours**.
- L'invité regarde **librement** pendant cette durée (pas de session de 5 h,
  pas de reconnexion à faire). ⟵ *modèle continu*
- Ce que l'invité regarde : la **chaîne partagée** par l'inviteur (même
  principe qu'au-dessus — l'invité n'a pas de source à lui). ⟵ *à confirmer :
  une chaîne précise, ou toute la source de l'inviteur pendant l'essai ?*

### Mode C — « Partage entre MES appareils » (transfert / handoff)
- **Réservé aux appareils PAYÉS** (abonnement à l'année / à vie — jamais essai
  ni pass invité).
- L'utilisateur déplace SON abonnement entre SES propres appareils (TV ↔
  laptop ↔ téléphone).
- **Jamais en simultané** : un seul appareil actif à la fois. Activer l'accès
  sur l'appareil B **libère/coupe** l'appareil A ; on peut le ramener quand on
  veut (nouveau transfert).
- **Gratuit** — à distinguer de l'option **Famille** (simultanée, vendue par le
  revendeur). Ici c'est solo, non simultané.
- Mécanique : `POST /api/invite/transfer { mac (payé), target_mac }` → l'appareil
  cible reçoit la MÊME licence (plan + échéance) ; l'appareil source est mis en
  pause (block_status) jusqu'au prochain transfert. Anti-abus : source doit être
  payée et jouable ; on ne « transfère » pas un essai/pass.

## 1. Comment on connecte l'invité (les deux modes)

- **Par CODE** : l'inviteur génère un code à 6 chiffres ; l'invité le tape sur
  sa TV / son téléphone (écran « J'ai un code »).
- **Par MAC** (activation poussée) : l'inviteur **tape la MAC de l'invité** →
  l'appareil de l'invité s'active directement, sans code.

## 2. À la fin (les deux modes)

- Fenêtre écoulée (Mode A : 2 j ; Mode B : la durée choisie) → **blocage** +
  message :
  > « Nous sommes heureux de continuer avec vous 🙂 — pour continuer, il vous
  > suffit de prendre un abonnement. »

## 3. Limites & anti-abus

- **5 invitations par SEMAINE** par abonné (fenêtre glissante 7 j, renouvelée).
- Un appareil ne peut être invité qu'**UNE seule fois à vie** (la fenêtre ne
  se relance pas ; ni un autre code ni une autre MAC ne redonnent d'accès).
- L'émetteur doit **toujours être payé** au moment de connecter.
- Le partage ne transmet **jamais** les identifiants complets de l'inviteur :
  seulement la chaîne choisie (flux), et l'accès **meurt** avec le pass.

## 4. Panel (suivi)

- Page « Pass Partage » : liste des invitations — inviteur, invité (MAC),
  mode (Ensemble / Test), chaîne partagée, dates, expiration, statut
  (actif / session en cours / expiré). Cloisonné par revendeur.

## 5. Déjà en place (à adapter au modèle ci-dessus)

- Worker : table `app_invites`, endpoints `/api/invite/create` & `/redeem`,
  anti-abus (une fois à vie, quota hebdo 5), suivi `GET /api/v1/invites`.
- App TV : écran Pass Partage (générer / j'ai un code), deux modes au 1er
  lancement (Mode réel / Mode invité).
- **À faire** : sessions de 5 h + fenêtre 2 j (Mode A), durées 12 h/1 j/2 j
  (Mode B), invitation par MAC, partage de la chaîne choisie, message de fin,
  page panel, app téléphone.

## 6. Faisabilité du partage de chaîne (analyse)

- Une `Channel` est autonome et jouable (name + streamUrl + logo) → on la
  transporte sur l'invitation (`channel_json`) et l'app invitée la lit via
  `playChannel` / `TvPlayerScreen`. Pas besoin d'importer une liste.
- L'accès meurt tout seul à l'expiration (le worker cesse de servir la
  chaîne / la licence expire).
