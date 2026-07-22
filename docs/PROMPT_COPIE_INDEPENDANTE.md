# PROMPT CHIRURGICAL — Chaîne « copie indépendante » (à coller dans une session Fable 5)

> Copie-colle TOUT ce bloc comme prompt de départ. Il est volontairement étroit :
> une seule chose compte — **copier des chaînes qui jouent, de façon autonome,
> stable, privée, avec un seul maître, et plusieurs bouquets possibles.**

---

## RÔLE
Tu reprends une chaîne « indépendance fournisseur » déjà en place. Tu NE
refactores rien d'autre. Tu NE touches PAS à l'app cinéma/VOD, ni au reste du
panel. Branche de travail : `claude/independence-hardening-d51mdr` (basée sur
`claude/tv-box-bulletin-localization-7xwp9f`, PAS sur `main`). Commits par
étapes qui compilent et passent la CI. Ne crée ni release ni PR sans qu'on te le
demande.

## EMPLACEMENTS EXACTS (déjà vérifiés — n'invente aucun chemin)
- Worker : `cloudflare/api_v1.js`
  - `handleMasterChannels` (copieur), `_copyXtream` / `_copyM3u` / `_rewriteOrigin`,
    `autoDetectSource`, `validateFacadeBase` / `facadeReason`,
    `handleMasterTestListGet` / `handleMasterTestListPut`, `handleMasterDiag`,
    table `master_test_list` (colonnes : `mac`, `m3u`, `gateway_base`,
    `gateway_user`, `gateway_pass`, `updated_at`).
- Worker : `cloudflare/worker.js`
  - `handleMasterListServe` (sert le M3U curé derrière réf opaque
    `/api/master-list/ml_…`), `copyMasterSourceForTest` (assigne la liste au
    testeur au redeem), `readMasterTestList`, `masterListRef`, `isMasterMac`,
    `handleInviteDiag`.
- Panel : `admin-panel/src/pages/MastersPage.tsx` (copieur + liste ORDONNÉE :
  réordonner/renommer/regrouper/supprimer/ajouter), `admin-panel/src/lib/api.ts`
  (`mastersApi`).
- Gateway : `gateway/` (Node 20 + Docker) — `Caddyfile`, `docker-compose.yml`,
  `src/config.js` (`BROADCAST_USER/PASS/MAX_STREAMS`), `src/users.js` (identité
  de diffusion), `src/hub.js` (mutualisation), `src/upstream.js` (reconnexion/
  failover), `src/xtream.js` (façade). Tests : `gateway/test/*.test.mjs`,
  `cloudflare/*.smoke.mjs`.

## CE QUI EST DÉJÀ FAIT (ne pas redéfaire)
1. Rustine `nip.io` SUPPRIMÉE. Façade = contrat strict `https://` + domaine
   (`validateFacadeBase`), sinon rejet avec message actionnable.
2. Identité de diffusion (`BROADCAST_USER/PASS`) : le copieur embarque cette
   identité dans les URLs de test à la place des identifiants fournisseur.
3. Gateway HTTPS : Caddy reverse-proxy 80/443 → gateway 8088, Let's Encrypt auto.
4. Liste de test ORDONNÉE dans le panel (l'ordre = l'ordre de lecture).
5. Diagnostic HONNÊTE : vert seulement si façade https joignable + liste servie
   + 1re chaîne réellement jouable de bout en bout.

## ÉTAT RÉEL OBSERVÉ (à corriger / faire progresser)
Diagnostic live d'un maître (`MK:24:2A:D0:0E:F3`, ligne `line.4k-beast.top`) :
- ✅ maître reconnu · ✅ source assignée · ✅ 5 chaînes curées.
- ⚠️ **Façade injoignable (530)** : un domaine de façade est réglé mais AUCUN
  gateway ne répond dessus (probablement l'exemple `tv.mondomaine.com`).
- ⚠️ **Aucune identité de diffusion**.
- ❌ **1re chaîne injoignable (530)** : les URLs de test pointent sur ce gateway
  mort → rien ne se lit.
Conclusion : la chaîne est correcte en CODE, mais côté données/déploiement elle
est en échec. Le repli « lecture directe » (façade vide) doit rester
irréprochable, ET le mode gateway doit devenir trivial à réussir.

## MISSION (étroite — rien d'autre)
Rendre la **copie** parfaite selon CES règles, dans cet ordre :

1. **Ça copie TOUT, tout seul.** La copie doit ramener l'intégralité de la ligne
   (Xtream `get.php`/`player_api` ou M3U), SANS troncature silencieuse : au-delà
   du plafond actuel (`_COPY_MAX_CHANNELS = 6000`), pagine/charge en plusieurs
   passes et signale clairement le total réel. Le maître ne doit rien faire à la
   main pour obtenir la liste complète.

2. **Seul ce qui est copié se joue.** Le testeur ne reçoit QUE le bouquet curé
   (jamais tout le fournisseur) tant qu'un bouquet est sélectionné. Vérifie que
   `copyMasterSourceForTest` sert bien la liste curée (mode 1) et jamais le
   bouquet complet quand un bouquet non vide existe.

3. **Ça doit jouer STABLE — mieux que la source directe.** Quand la façade est
   réglée, les URLs passent par le gateway (reconnexion + failover + tampon →
   `upstream.js`/`hub.js`) et par l'identité de diffusion. Prouve la stabilité
   par un test (mutualisation : N testeurs d'une chaîne = 1 connexion amont ;
   failover : bascule sans couper). Quand la façade est VIDE, la lecture directe
   doit rester fluide (repli documenté).

4. **UN SEUL MAÎTRE, qui gère tout.** Routes `masters/*` réservées `super_admin`.
   Le maître peut AJOUTER et RETIRER des chaînes de son bouquet (déjà en place :
   liste ordonnée) — garde ça intact et fiable.

5. **PLUSIEURS BOUQUETS, hors du trio unique.** AUJOURD'HUI il n'existe qu'UNE
   liste par maître (`master_test_list.mac` = clé primaire). Fais évoluer le
   modèle pour que le maître puisse créer/nommer/gérer **plusieurs bouquets
   distincts** (ex. « Sport », « Familial »), chacun :
   - avec son propre M3U curé et sa propre réf opaque `ml_…` (service séparé) ;
   - **indépendant du trio** : un bouquet peut être bâti à partir d'une source
     COLLÉE (autre ligne Xtream/M3U) que le maître fournit, pas seulement de la
     ligne assignée — le copieur accepte déjà `paste` : généralise-le au bouquet ;
   - assignable au testeur au redeem (choix du bouquet à servir).
   Migration D1 ADDITIVE et idempotente (ne casse pas les listes existantes :
   l'actuelle devient le bouquet par défaut). Le secret gateway n'est jamais
   réaffiché ; la vraie MAC/ligne n'apparaît jamais hors panel.

## GARDE-FOUS (non négociables)
- Aucune régression lecture cinéma/VOD ni reste du panel/app.
- Maîtres/tests PRIVÉS ; MAC réelle masquée (réf opaque) ; le fournisseur ne voit
  qu'une connexion ; mot de passe fournisseur jamais réaffiché ni embarqué quand
  l'identité de diffusion est réglée.
- Aucune URL de flux IPTV en dur dans le code de prod (exemples hors prod).
- Commentaires FRANÇAIS abondants ; réutiliser l'existant avant de créer ; pas de
  `console.log` de secrets ; couleurs/tailles via les tokens Tailwind existants.
- Tout compromis (buffer, repli, auth) → le DOCUMENTER, pas deviner en silence.

## VALIDATION (tous VERTS avant push)
```
node --check cloudflare/worker.js && node --check cloudflare/api_v1.js
for f in cloudflare/*.smoke.mjs; do node "$f"; done
cd gateway && npm test
cd admin-panel && npx tsc --noEmit
```
Ajoute des smoke/unit tests pour TOUTE logique pure nouvelle (pagination,
multi-bouquets, sélection du bouquet au redeem). Pousse sur
`claude/independence-hardening-d51mdr`.

## LIVRABLE
Rapport : (1) copie complète prouvée (total réel, pas de troncature muette) ;
(2) « seul le curé se joue » prouvé ; (3) stabilité prouvée (mutualisation +
failover) ; (4) multi-bouquets opérationnels (créer/nommer/retirer/assigner),
chacun servi derrière sa réf opaque, indépendant du trio. Chaque affirmation
vérifiable dans le diff.
