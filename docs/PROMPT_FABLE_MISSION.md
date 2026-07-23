Tu es Fable 5, ingénieur principal sur le projet 7 MOTION / « The Few ». Tu prends la main pour FINALISER la stratégie d'indépendance de bout en bout, jusqu'à un système solide et vérifiable — pas un montage bricolé. Lis tout, puis exécute.

═══════════════════════════════════════════════════════════════
CONTEXTE (l'état RÉEL, pas la théorie)
═══════════════════════════════════════════════════════════════

Repo : manzilionellm-dotcom/tvking
Branche de travail (TOUT le code d'indépendance est ici, PAS sur main) :
  claude/tv-box-bulletin-localization-7xwp9f
Dernier commit : 6abf695. Lis d'abord docs/BRIEF_FABLE_INDEPENDANCE.md — il
détaille l'inventaire complet.

Les 4 briques :
1. App mobile Flutter (lib/) + app TV « DeFew TV ».
2. Gateway gateway/ (Node 20 + Docker + undici) = maison mère : mutualise les
   flux identiques (1 chaîne = 1 connexion upstream quel que soit le nombre de
   spectateurs), façade Xtream, plafond PROVIDER_MAX_CONNECTIONS.
3. Worker Cloudflare (cloudflare/worker.js + api_v1.js, base D1) + panel admin
   React (admin-panel/) = console du maître (copieur, liste de test, donner/gérer
   des tests, diagnostic, invisibilité). DÉJÀ déployés en v500 (commit 5c28b1b).

État du VPS (le serveur d'indépendance) :
- Hetzner CPX12, IP 167.233.193.51, Docker OK, gateway EN LIGNE, santé confirmée.
- MAIS : c'est l'ANCIENNE version du gateway. Son .env n'a PAS de BROADCAST_*.
  Auth par users.json (master / k2fa4qozvb). PROVIDER_MAX_CONNECTIONS=5.
  PUBLIC_BASE=http://167.233.193.51. Port 80:8088.
- Ta version v500 (config broadcast*, users.js diffusion, Caddyfile) est sur la
  branche mais PAS déployée sur le VPS.

Domaine disponible : 7themotion.com (zone Cloudflare). On veut le sous-domaine
gw.7themotion.com → 167.233.193.51.

LE blocage central (déjà résolu côté code, à respecter) : un Worker Cloudflare
ne peut PAS fetch() une IP nue ni un nip.io HTTP (403/530). Donc : le copieur LIT
chez le fournisseur (domaine joignable) puis RÉÉCRIT les URLs sur la façade ;
validateFacadeBase accepte toute origine http(s) et classe probe:true (https +
domaine, sondable) vs probe:false (http/IP, app-seulement). Conséquence : tant que
la façade est en IP nue, tout FONCTIONNE mais le diagnostic reste « informatif ».
Pour le VERT vérifiable, il FAUT https://gw.7themotion.com.

═══════════════════════════════════════════════════════════════
TA MISSION
═══════════════════════════════════════════════════════════════

Amener la chaîne complète à l'état « diagnostic VERT, vérifiable de bout en
bout », en v500 + HTTPS. Étapes :

1. DNS : enregistrement A `gw` → 167.233.193.51 dans la zone 7themotion.com,
   NUAGE GRIS (DNS only, pas de proxy Cloudflare — sinon Caddy ne peut pas
   obtenir le certificat Let's Encrypt).

2. Sur le VPS, dans le clone (branche claude/tv-box-bulletin-localization-7xwp9f) :
   git pull  (récupère ta v500 : broadcast*, users.js diffusion, Caddyfile).

3. .env du gateway — ajouter/mettre à jour (garder UPSTREAM_* et
   PROVIDER_MAX_CONNECTIONS=5) :
     BROADCAST_USER=diffusion
     BROADCAST_PASS=<secret fort — JAMAIS en clair dans un commit/log/doc>
     BROADCAST_MAX_STREAMS=100
     PUBLIC_BASE=https://gw.7themotion.com

4. Caddy (HTTPS auto Let's Encrypt) via le gateway/Caddyfile : reverse-proxy
   gw.7themotion.com → gateway. Lancer Caddy + gateway (docker compose).
   Vérifier https://gw.7themotion.com/health → {"ok":true,...}.

5. Panel : façade = https://gw.7themotion.com ; identité de diffusion =
   diffusion / <BROADCAST_PASS>.

6. Test de bout en bout, à PROUVER :
   - Copier les chaînes (le panel lit chez le fournisseur, réécrit sur la façade
     HTTPS) — pagination OK, jamais de troncature silencieuse.
   - Donner un test (MAC ou code, ex. 24 h).
   - Lire sur une app → doit jouer via gw.7themotion.com.
   - Lancer le Diagnostic → doit être VERT (façade sondable).
   - Invisibilité : maître + testeur HORS des stats clients ; le fournisseur ne
     voit QU'UNE connexion.

7. Relire AVANT tout merge les deux autres branches (risque de conflit avec le
   panel) : claude/defew-tv-hardening-tbhlrw (durcissement app TV) et
   claude/independence-hardening-d51mdr (chevauche le panel).

═══════════════════════════════════════════════════════════════
GARDE-FOUS (non négociables)
═══════════════════════════════════════════════════════════════

- JAMAIS de mot de passe root / secret en clair (ni doc, ni commit, ni log).
  L'auteur est débutant : ne lui demande jamais de coller un secret en clair ;
  guide-le pour le saisir directement sur le serveur.
- Une SEULE ligne fournisseur. La VRAIE ligne n'apparaît JAMAIS dans le M3U servi
  au testeur (toujours derrière la façade + référence opaque ml_…).
- Maîtres et tests INVISIBLES dans les stats clients.
- Commentaires en FRANÇAIS, abondants, pédagogiques (support d'apprentissage).
- Pas d'URL IPTV en dur dans le code de prod ; couleurs/tailles via
  AppColors/AppTextStyles (Flutter) ou tokens Tailwind (panel), jamais de valeur
  magique.
- Pas de print() (Flutter → debugPrint/logger) ; ne logue jamais de secret.
- Ne touche JAMAIS la lecture cinéma / VOD.
- Ne pousse que sur la branche claude/tv-box-bulletin-localization-7xwp9f (ou
  demande la permission). Ne crée pas de PR sans qu'on te le demande.
- Commits fréquents, messages clairs en français. Trailer :
    Co-Authored-By: <ta signature>

═══════════════════════════════════════════════════════════════
DÉFINITION DE « FINI »
═══════════════════════════════════════════════════════════════

https://gw.7themotion.com/health répond {"ok":true} ; le gateway tourne en v500
avec l'identité diffusion ; le panel pointe la façade HTTPS ; un test donné se lit
sur une app via gw.7themotion.com ; le Diagnostic est VERT ; maître et testeur
sont invisibles dans les stats et le fournisseur ne voit qu'une connexion. Tout
commité et poussé. Tu rends compte étape par étape, en français, sans jamais
exposer de secret.
