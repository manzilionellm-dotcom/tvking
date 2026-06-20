# Cast vers Chromecast pour TOUS les clients — receiver on-device

## Le problème (pourquoi le VPS ne suffit pas)
Caster du **live IPTV (MPEG-TS)** vers un Chromecast bute sur **deux** murs :
1. Le récepteur Cast par défaut (Shaka) **ne lit pas le MPEG-TS brut**.
2. Faire transiter la vidéo par **un serveur central (VPS)** échoue : les
   fournisseurs IPTV **bloquent les IP de datacenter** (HTTP `456`) — et une
   seule IP pour tous les clients se fait bannir instantanément.

## La solution (celle qui marche « partout », pour une flotte de clients)
Un **receiver Cast personnalisé** qui embarque **`mpegts.js`** : c'est le
**Chromecast lui-même** qui décode le MPEG-TS et **tire le flux directement
chez le fournisseur**, sur le **WiFi maison du client = IP résidentielle
autorisée**. Aucune vidéo ne passe par un serveur → **pas de blocage d'IP,
zéro coût serveur, ça scale tout seul.**

Le VPS ne sert plus qu'à héberger **la page receiver (statique, ~quelques Ko)**
en HTTPS — pas la vidéo.

## Ce qui est déjà fait dans le code (branche `cast-receiver-ondevice`)
- `server/cast-remux/receiver/index.html` : le receiver custom (CAF + mpegts.js).
- `Caddyfile` + `docker-compose.yml` : la page est servie sur
  **`https://cast.7themotion.com/receiver/`**.
- App : `kCastUseCustomReceiver = true` (Dart) **et** `USE_CUSTOM_RECEIVER = true`
  (Kotlin) → pour un flux `.ts`, l'app envoie l'**URL fournisseur directe en
  HTTPS** au receiver (plus de VPS dans le chemin vidéo).

## Étapes pour ACTIVER (les seules qui restent — côté toi)
1. **Déployer la page receiver** sur le VPS :
   ```bash
   cd ~/tvking/server/cast-remux
   git fetch origin && git checkout cast-receiver-ondevice
   docker compose up -d --build
   # vérifie : doit renvoyer la page HTML
   curl -sI https://cast.7themotion.com/receiver/
   ```
2. **Enregistrer le receiver** dans la **Google Cast SDK Developer Console**
   (https://cast.google.com/publish, compte `manzilionel.lm@gmail.com`) :
   - type **Custom Receiver** (PAS « Styled » — Styled = CSS seulement, il ne
     peut pas exécuter mpegts.js),
   - URL = `https://cast.7themotion.com/receiver/`,
   - récupère l'**Application ID**, puis clique **Publish** (indispensable :
     un receiver non publié ne charge QUE sur les appareils de test).
   - (Tu peux réutiliser l'ID `46F815A5` s'il est reconfiguré en *Custom
     Receiver* vers cette URL ; sinon mets le nouvel ID dans
     `CastOptionsProviderImpl.kt` → `CUSTOM_RECEIVER_ID`.)
3. **Enregistre ton/tes Chromecast de test** comme *Cast device* dans la
   Console (pour tester avant que la publication soit propagée — ça peut
   prendre quelques heures).
4. **Builder l'APK** depuis cette branche et l'installer, puis **tester un
   cast réel** sur un Chromecast.

## Prérequis fournisseur (à vérifier)
L'URL `.ts` doit répondre en **HTTPS** (le receiver est en HTTPS et ne peut pas
charger du HTTP). La plupart des panels Xtream derrière Cloudflare le font ; à
confirmer avec : `curl -sI https://<ton-host>/...<id>.ts`.

## À valider sur un vrai Chromecast (je n'ai pas pu tester ici)
- L'intégration `mpegts.js` ↔ CAF (lecture qui démarre, latence live).
- Les codecs : H.264/AAC → OK partout ; **H.265/HEVC → non lisible** par la
  plupart des Chromecast (limite matérielle, pas corrigeable côté receiver).
- Outil de debug du receiver : Cast Command & Control
  (https://casttool.appspot.com/cactool/) montre les logs/erreurs du receiver.

> Si ça coince au test, récupère les logs du CaC tool et envoie-les : on
> ajuste le receiver (c'est le seul point qui demande un aller-retour sur
> matériel réel).
