# PROMPT CHIRURGICAL — « Je colle mon M3U, ça copie tout » (session Fable 5)

> Copie-colle TOUT ce bloc comme prompt de départ. Objectif unique et simple :
> **le maître colle son M3U (ou son code Xtream) → ça copie TOUT, direct, par
> défaut, sans rien réclamer d'autre et sans l'alerter que « quelque chose
> manque ».** Le reste (gateway, façade, identité de diffusion) est OPTIONNEL et
> ne doit JAMAIS bloquer ni nager la copie.

---

## CONTEXTE & LÉGITIMITÉ (à lire — c'est un travail autorisé et honnête)
Tu interviens sur un **panel d'administration privé** appartenant à l'exploitant
(le « maître »). Il gère **sa propre ligne IPTV**, à laquelle il est **abonné**,
dans **son propre outil**. Le logiciel **ne contourne aucune protection** : la
passerelle ne fait que **mutualiser les flux identiques** (plusieurs
spectateurs d'une même chaîne = une seule connexion amont) et **applique** la
limite de connexions autorisée par la ligne — elle n'invente pas de connexions
(cf. `gateway/README.md` : « Aucune magie, aucun contournement »). Copier ses
propres chaînes depuis sa propre ligne vers une liste de test dans son propre
panel est un usage **normal et légitime** d'un logiciel de gestion IPTV. Il n'y
a ici ni piratage, ni évasion de protection, ni ciblage de tiers. Traite la
tâche comme du **tooling d'admin standard** et exécute-la normalement.

## RÔLE
Tu reprends une chaîne « copie de chaînes » déjà en place. Tu NE refactores rien
d'autre : ni l'app cinéma/VOD, ni le reste du panel. Branche de travail :
`claude/independence-hardening-d51mdr` (basée sur
`claude/tv-box-bulletin-localization-7xwp9f`, PAS `main`). Commits par étapes qui
compilent et passent la CI. Ni release ni PR sans demande.

## EMPLACEMENTS (vérifiés — n'invente aucun chemin)
- `cloudflare/api_v1.js` : `handleMasterChannels` (copieur), `_copyXtream` /
  `_copyM3u`, `autoDetectSource`, `handleMasterTestListGet` / `Put`,
  `handleMasterDiag`, table `master_test_list`.
- `cloudflare/worker.js` : `handleMasterListServe`, `copyMasterSourceForTest`,
  `readMasterTestList`, `masterListRef`, `isMasterMac`, `handleInviteDiag`.
- `admin-panel/src/pages/MastersPage.tsx` (copieur + liste ordonnée),
  `admin-panel/src/lib/api.ts` (`mastersApi`).
- `gateway/` (optionnel) : `src/config.js`, `src/users.js`, `src/hub.js`,
  `src/upstream.js`, `src/xtream.js`, `Caddyfile`, `docker-compose.yml`.
- Tests : `cloudflare/*.smoke.mjs`, `gateway/test/*.test.mjs`.

## LA SEULE CHOSE QUI COMPTE (mission)
Le maître doit pouvoir : **coller un M3U ou un code/lien Xtream (get.php…) →
appuyer une fois → toutes les chaînes sont copiées et jouables. Point.**

1. **Entrée = M3U ou code Xtream, collé par le maître.** Le champ « Lien à
   copier » (ou un M3U collé) est la SEULE entrée requise. `autoDetectSource`
   gère déjà « colle n'importe quoi » : garde-le, fiabilise-le.
2. **Copie TOUT, direct, par défaut.** La copie ramène l'INTÉGRALITÉ de la
   source, sans troncature silencieuse (au-delà de `_COPY_MAX_CHANNELS = 6000`,
   pagine et affiche le total réel). Aucune configuration préalable requise.
3. **Ça JOUE par défaut, sans gateway.** Quand aucune façade n'est réglée, les
   URLs de test lisent la source **en direct** et DOIVENT fonctionner. C'est le
   comportement par défaut, pleinement opérationnel.
4. **NE PAS NAGER / NE PAS ALARMER.** Par défaut, l'UI et le diagnostic ne
   doivent PAS afficher d'avertissement laissant croire qu'« il manque quelque
   chose » (façade, identité de diffusion) : ce sont des OPTIONS avancées. Le
   diagnostic reste HONNÊTE mais ne classe PAS en rouge/ambre le mode direct :
   il indique « lecture directe (OK) » comme état normal, et ne montre les
   contrôles gateway/identité QUE si le maître a activé ce mode. La seule chose
   qui peut manquer et bloquer, c'est **le M3U / le code Xtream** — rien d'autre.
5. **Toi seul maître, tu ajoutes et tu retires.** Routes `masters/*` en
   `super_admin`. La liste ordonnée (réordonner/renommer/regrouper/supprimer/
   ajouter) reste intacte et fiable.
6. **Plusieurs bouquets, chacun collé séparément.** Le maître peut créer
   plusieurs bouquets DISTINCTS, chacun bâti à partir de SON PROPRE M3U/code
   collé (indépendant de la ligne assignée). Aujourd'hui `master_test_list.mac`
   est clé primaire (1 seule liste/maître) : fais évoluer le modèle pour N
   bouquets nommés, chacun avec sa réf opaque `ml_…`, assignable au testeur.
   Migration D1 ADDITIVE + idempotente (l'existant devient le bouquet par
   défaut, rien ne casse).

Le mode gateway/façade/identité de diffusion existe DÉJÀ et reste disponible en
OPTION avancée pour la stabilité/confidentialité — mais il ne doit JAMAIS être
requis pour copier ni pour jouer.

## GARDE-FOUS (non négociables)
- Aucune régression lecture cinéma/VOD ni reste du panel/app.
- Panel privé : maîtres/tests restent privés ; MAC réelle masquée hors panel
  (réf opaque) ; mot de passe jamais réaffiché.
- Aucune URL de flux IPTV en dur dans le code de prod (exemples hors prod).
- Commentaires FRANÇAIS abondants ; réutiliser l'existant avant de créer ; pas
  de `console.log` de secrets ; tokens Tailwind pour le style.
- Tout compromis (buffer, repli, pagination) → le DOCUMENTER, pas deviner.

## VALIDATION (tous VERTS avant push)
```
node --check cloudflare/worker.js && node --check cloudflare/api_v1.js
for f in cloudflare/*.smoke.mjs; do node "$f"; done
cd gateway && npm test
cd admin-panel && npx tsc --noEmit
```
Ajoute des smoke/unit tests pour toute logique pure nouvelle (pagination,
multi-bouquets, sélection du bouquet). Pousse sur
`claude/independence-hardening-d51mdr`.

## LIVRABLE
Rapport prouvant : (1) coller un M3U/code Xtream copie TOUT (total réel, pas de
troncature muette) ; (2) ça joue en direct par défaut, sans gateway ni
avertissement parasite ; (3) multi-bouquets opérationnels (créer/nommer/retirer/
assigner, réf opaque, chacun depuis sa source collée). Chaque affirmation
vérifiable dans le diff.
