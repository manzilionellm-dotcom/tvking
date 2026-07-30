# SEVEN — Vision produit « Top 2 mondial » (TV box, les 4 templates)

> **Mandat** : concevoir l'application de streaming/IPTV la plus professionnelle
> et la plus engageante possible, avec l'ambition d'en faire le n°1 ou n°2 de sa
> catégorie mondiale. Périmètre : **l'app TV box uniquement** (les 4 templates
> A/B/C/D). Le mobile n'est pas touché.
>
> **Méthode** : ce document est issu d'une recherche réelle (3 rapports web
> sourcés, juillet 2026 : mécaniques d'engagement des géants ; marché des
> lecteurs IPTV & UX TV ; monétisation/rétention/tendances 2026-2028) croisée
> avec un audit ligne-à-ligne du code des 4 templates. Chaque choix est justifié
> par un fait sourcé ou une ligne de code. Il complète — sans les remplacer —
> `docs/ENGAGEMENT-PLAYBOOK.md` et `ROADMAP-VAGUES.md`.

---

## Phase 1 — Ce qui rend les géants impossibles à quitter (synthèse de recherche)

### 1.1 Les sept lois validées par les données

1. **La loi des 90 secondes.** Un utilisateur Netflix examine 10-20 titres en
   60-90 s ; au-delà, le risque d'abandon de session « augmente
   substantiellement » (Gomez-Uribe & Hunt, ACM 2016). **80 % des heures vues
   viennent des recommandations de l'accueil**, 20 % de la recherche. Tout
   l'écran d'accueil doit converger vers UNE lecture en moins de 90 s.
2. **Les signaux implicites battent les signaux explicites.** TikTok pondère
   d'abord le temps de visionnage, les re-visionnages et les pauses (doc interne
   « Algo 101 », NYT 2021) ; YouTube optimise le watch-time attendu, pas le clic
   (RecSys 2016, 70 % du visionnage vient des recos) ; Spotify pèse le save et
   la ré-écoute ~3× plus que le volume brut. On n'a pas besoin de demander :
   regarder, c'est voter.
3. **La friction supprimée vaut des années humaines.** « Skip Intro » est pressé
   136 M de fois/jour (Netflix 2022). Désactiver l'autoplay réduit la session de
   ~18 min (étude causale ACM CSCW 2025). La reprise inter-appareils Netflix
   synchronise ~150 000 événements/s. Chaque seconde de friction retirée entre
   l'intention et l'image est le levier n°1.
4. **L'artwork et l'aperçu décident du clic.** Artwork personnalisé par bandits
   contextuels : +20-30 % de CTR mesurés (Netflix TechBlog 2017). Preview vidéo
   au focus après 1-2 s de dwell (TV, 2016). C'est exactement ce que nos
   4 templates viennent de gagner (aperçu `TvLivePreview` partout).
5. **La preuve sociale retire le risque d'essayer.** Top 10 (2020), callouts
   « #1 in TV Shows » injectés dans la carte-titre (refonte TV Netflix,
   mai 2025). Peu coûteux, très efficace.
6. **La récompense variable crée le rendez-vous.** Discover Weekly chaque lundi ;
   « curve-balls » TikTok (exploration hors profil) ; Wrapped (200 M+
   d'utilisateurs en 24 h, 2025). L'accueil doit offrir du neuf À CHAQUE
   ouverture — c'est le badge « MA SOIRÉE » du template B, généralisé.
7. **Tout se tranche par l'expérimentation.** Netflix : des milliers de tests
   A/B par an, interleaving ~100× plus sensible qu'un A/B classique. À notre
   échelle : mesurer (north star = minutes/utilisateur/semaine, J7, TTFF) avant
   de trancher les débats d'opinion.

### 1.2 La refonte TV Netflix de mai 2025 (la direction du marché)

Première refonte majeure de la home TV depuis 2013 : **menu recentré EN HAUT**
(fini le panneau latéral), **recommandations recalculées en continu pendant la
session** (heure, trailers regardés, recherches), fiches compactes avec
callouts, recherche conversationnelle GenAI. Notre template A (menu compact en
haut + contenu plein écran) est déjà sur ce pattern — c'est une validation, pas
un hasard.

### 1.3 La ligne éthique (et pourquoi elle est rentable)

La littérature (ACM DIS 2022, CSCW 2025) sépare nettement : l'engagement est
**sain** quand il sert l'intention (Skip Intro, reprise, récaps — friction
supprimée vers un but choisi) ; il devient dark pattern quand il exploite
l'inertie (countdown non annulable, previews non désactivables, temps restant
masqué). Netflix lui-même a dû ajouter les opt-outs (2020). Les procès TikTok
(Kentucky 2024) montrent le coût du franchissement. **Règle SEVEN : tout
automatisme (autoplay, preview, rappel) est annulable ET désactivable dans les
Réglages.** C'est cohérent avec le garde-fou déjà écrit dans
`ENGAGEMENT-PLAYBOOK.md` §6 — et c'est une condition de survie sur les stores.

---

## Phase 2 — Les faiblesses du marché et l'espace vide (analyse concurrentielle)

### 2.1 L'état du marché des lecteurs « bring your own subscription »

| Acteur | Force | Faiblesse fatale |
|---|---|---|
| TiviMate (~10 $/an, 34 $ à vie) | Référence EPG/PVR sur Android TV | Android TV uniquement ; buffering v5.2 ; développeur silencieux ; retraits épisodiques du Play Store |
| IPTV Smarters Pro (gratuit, white-label B2B) | Ubiquité (toutes plateformes) | UX datée ; retiré du Play Store (justice espagnole, 2025) |
| IBO Player Pro (licence/appareil par MAC) | Présent sur Samsung/LG en stores officiels | **Activation MAC = friction n°1 du marché** ; fonctionnel pauvre |
| Flix IPTV (7,99 €/appareil) | Stores Smart TV | Même friction MAC/portail ; basique |
| OTT Navigator (~5 $) | Le plus configurable | Courbe d'apprentissage raide |
| Sparkle TV (~4 £ à vie) | Jeune, privacy-first, actif | Notoriété faible |

**Personne ne coche plus de deux cases** parmi : UX 10-foot moderne · profils +
reprise synchronisée · recommandations sur la playlist de l'utilisateur ·
mode sport · multi-plateforme (Android TV + Fire TV + Tizen + webOS) ·
distribution store pérenne · support réactif.

### 2.2 Les plaintes récurrentes des utilisateurs (threads 2024-2026)

1. Buffering / image figée (plainte n°1) ; 2. EPG incomplet, jamais enrichi côté
client ; 3. activation MAC + portail web ; 4. retraits de stores → sideload —
**désormais impossible sur Fire TV Vega OS** ; 5. reprise de lecture
inexistante ou cassée ; 6. pas de profils ; 7. support fantôme ; 8. **zéro
découverte** : des annuaires de 10 000 chaînes sans recommandation.

### 2.3 Ce que le FAST nous apprend

Samsung TV Plus : >100 M MAU (janv. 2026), n°1 en Europe devant Pluto ; heures
FAST US +43 % en 2025 ; streaming = 47,5 % de toute la TV US (Nielsen,
déc. 2025). **Le lean-back « chaînes + guide » n'est pas mort — il migre vers
les expériences sans friction.** L'IPTV a le contenu ; il lui manque
l'expérience. C'est exactement notre espace.

### 2.4 Le contexte juridique (condition de survie)

Jurisprudence Filmspeler (CJUE 2017) + purges de stores (Smarters 2025, 36 apps
en 2026) : la ligne de survie est **zéro contenu, zéro lien, zéro playlist
pré-configurée** — déjà la règle n°2 de notre `AGENTS.md`. Les survivants
(TiviMate) monétisent uniquement les fonctionnalités du lecteur. Toute la
vision ci-dessous respecte strictement cette ligne.

### 2.5 Les opportunités encore vides (confirmées par la recherche)

1. **Recommandation personnalisée sur LA playlist de l'utilisateur** — vendue en
   B2B aux opérateurs (ContentWise), quasi vierge côté lecteurs. Notre
   `affinity_service` + `time_of_day_service` + « MA SOIRÉE » sont déjà des
   embryons en production.
2. **Recherche sémantique/conversationnelle** (« un polar pas trop long ») —
   inexistante chez les lecteurs ; Netflix/Amazon l'ont généralisée en 2025-2026.
   Notre `ai_search_service` + le worker (clé serveur, jamais dans l'app) sont
   la base (vague D27/D30).
3. **Mode sport augmenté** — Prime Vision a montré la voie ; aucun lecteur IPTV
   n'a même une vue sport dédiée. Nous avons DÉJÀ `_MatchChip`, équipes
   favorites, écran Sports — uniquement sur le template A aujourd'hui.
4. **Multiview fluide** — nous l'avons (`tv_multiview_screen.dart`) ; le marché
   le fait mal (4 décodages côté client).
5. **Onboarding sans MAC ni portail** — notre système de codes d'invitation
   (panel + worker) est déjà supérieur au standard du marché.
6. **Profils + reprise à la Netflix** — vides chez tous les concurrents ;
   partiellement en place chez nous (profils, `watch_history`, rangée
   Reprendre en A/B).

---

## Phase 3 — La vision produit

### 3.1 Le positionnement (honnête et gagnable)

On ne bat pas Netflix sur le contenu : Netflix EST un catalogue. On le bat sur
**l'expérience appliquée au contenu que l'utilisateur possède déjà**. La
promesse :

> **« L'expérience Netflix, sur TON abonnement. »**
> SEVEN est la couche d'expérience du salon : n'importe quelle source IPTV
> légitime devient une expérience premium — personnalisée, instantanée, belle —
> sur n'importe quelle TV.

- **Catégorie visée** : lecteur/expérience TV neutre multi-plateforme. Le n°1
  actuel (TiviMate) est mono-plateforme et sans découverte ; le n°1 de la
  distribution Smart TV (IBO) a l'UX la plus détestée. **Top 2 mondial de la
  catégorie = objectif atteignable en 24-36 mois** ; la barre d'expérience,
  elle, se mesure à Netflix.
- **Double moteur économique déjà en place** (unique sur ce marché) :
  1. **B2B2C opérateur** : panel Cloudflare + gateway + codes de test + gestion
     de parc par MAC (déjà en prod — `MASTER_CAPABILITIES.md`). Les opérateurs
     paient pour offrir une app premium à LEURS clients.
  2. **B2C utilitaire** : freemium + licence (norme du marché : ~10 $/an ou
     20-35 $ à vie ; RevenueCat 2025 : 35 % des apps mixent abonnement +
     lifetime).
- **Les 4 templates sont un différenciateur, pas une dette.** Aucun concurrent
  n'offre le choix de la disposition (« comme à la maison ») : A pour les
  habitués du zapping classique, B pour le salon familial, C pour les
  ex-utilisateurs IBO, D pour les power users TiviMate. Le sélecteur devient un
  argument de migration : *« ton ancienne app est un de nos templates »*.

### 3.2 Les cinq piliers de l'expérience

1. **Instantané** : TTFF < 2 s perçu, zap sans écran noir, reprise en 1 OK.
2. **Personnel** : l'accueil de CHAQUE template apprend (affinité, heure,
   habitudes) — 100 % local d'abord, opt-in pour le reste.
3. **Beau et lisible à 3 mètres** : focus visibles, ambiance `TvAmbience`,
   8 langues, zéro texte technique.
4. **Fiable** : boîte noire, diagnostics à distance, budget mémoire petite-box,
   simulateur TV en CI — déjà nos forces, à maintenir comme un contrat.
5. **Neutre et conforme** : zéro contenu fourni, opt-out sur tout automatisme,
   transparence des données (`B18/B19` opt-in).

---

## Phase 4 — Architecture produit (appliquée aux 4 templates)

### 4.0 Socle commun « TvHomeCore » (le chantier structurant)

L'audit de parité montre que B, C et D réimplémentent chacun leur coque
(`Material` + safe area + gradient) et perdent `TvAmbience`, pendant que des
briques identiques (héro, Reprendre, horloge, dialog Quitter, restauration de
focus) sont dupliquées ou absentes selon le template. **Décision
d'architecture : un socle partagé, des dispositions par-dessus.**

- `TvShell` (Material + safe area + ambiance + vignettage) devient la coque des
  4 templates — B/C/D gardent leur identité visuelle via leur palette, pas via
  leur plomberie.
- Briques communes extraites et branchées partout : `TvHeroPreview` (héro +
  cascade dernière-regardée/favori/1re chaîne + garde petite-box — fait en
  B/C/D, à offrir en option à A), `TvResumeRail` (fait en B, manque en C/D),
  `TvExitDialog` (3 options, localisé, autofocus — fait en A, à réutiliser en
  B/C/D), `TvClock` feuille (fait en A/B/C, manque en D), restauration de focus
  au BACK (fait en B, partiel en C, absent en D).
- **Une seule expérience « Direct »** : B ouvre `TvChannelsScreen` quand A et C
  ouvrent `TvLiveScreen` — on tranche pour une seule, paramétrable
  (pré-sélection « ★ Favoris » pour corriger le bouton trompeur de C).
- **Localisation totale** : B et C ont ~30 chaînes de texte en dur (audit §3.1,
  clés existantes pour la plupart) ; les descriptions des templates aussi.
  8 langues, zéro exception — c'est le prix de l'international.

### 4.1 L'accueil qui gagne les 90 secondes (par template)

Ordre de priorité du contenu (loi n°1), décliné selon la disposition :

- **Rang 0 — Reprendre / En ce moment pour toi** : la meilleure prédiction en
  haut à gauche (habitude horaire « MA SOIRÉE » généralisée aux 4 templates,
  badge compris).
- **Rang 1 — Tes favoris en direct** (avec programme EPG en cours + barre de
  progression — le rail de C est la référence, à porter en B).
- **Rang 2 — Nouveautés pour toi** (croiser `vod_novelty` × `vod_taste`,
  vague B15) avec badges « NOUVEAU » et callouts sobres (« N°1 chez toi »).
- **Rang 3 — Sport** : pastille match (aujourd'hui exclusive à A) sur les
  4 templates ; à terme, vue sport dédiée (cf. 4.4).
- Preview vidéo au focus partout (fait) ; **opt-out global « aperçus vidéo » et
  « autoplay » dans les Réglages** (ligne éthique).

### 4.2 Le moteur de personnalisation (local d'abord)

Étage 1 (fait) : affinité de genre + heure + récence. Étage 2 : score simple
par chaîne/contenu = f(minutes vues, récence, créneau horaire, jour de semaine)
— les signaux implicites de la loi n°2, calculés sur l'appareil, zéro cloud.
Étage 3 (opt-in, vague B19) : agrégats anonymes par MAC vers le panel → le
panel apprend les tendances du parc (« Top 10 du parc » = notre preuve
sociale, sans données individuelles). Étage 4 (vague D27/D30) : recherche
conversationnelle via le worker (clé serveur), à la Netflix mai 2025.

### 4.3 Live + VOD + catch-up : la boucle de rétention

- **Live** : zap prébufferisé (chaîne voisine), retour au direct après coupure
  (fait côté natif), rappels EPG posables (cloche) — **le déclencheur externe
  n°1 du Hook model, toujours absent, priorité inchangée** (playbook Tier 1).
- **VOD** : reprise à la position (étendre `watch_history` en ms), autoplay
  épisode suivant avec compte à rebours annulable (loi n°3 : +18 min/session),
  « récap » texte avant reprise d'une série abandonnée (le X-Ray Recaps
  d'Amazon est devenu LA feature la plus utilisée de Fire TV).
- **Catch-up** : « l'émission que tu rates en ce moment » sur l'accueil (EPG ×
  habitudes) — unique sur le marché.

### 4.4 Le mode Sport (différenciateur n°1 à 12 mois)

Aucun lecteur IPTV n'en a. Nous avons déjà les équipes favorites, `_MatchChip`,
l'écran Sports, le multiview. Assemblage : vue « Match center » (affiche du
match, chaîne(s) qui le diffusent dans TA playlist, rappel en 1 OK, multiview
2×2 des matchs simultanés), notifications « ton équipe joue dans 30 min »
(vague B17). Latence : suivre LL-HLS/DASH (~3 s atteignables, standard sport
2026) côté gateway/relais.

### 4.5 Monétisation

- **B2B2C (déjà en prod)** : le panel + la façade gateway + les codes de test
  sont notre vrai moat — un opérateur qui a déployé SEVEN sur son parc ne part
  plus (bundle = churn 70 %→29 % dans les études opérateurs). Pricing par parc
  d'appareils actifs (heartbeats déjà comptés, C21).
- **B2C** : gratuit = lecteur complet 1 source ; Premium ~9,99 €/an ou
  29,99 € à vie (5 appareils, norme TiviMate) = multi-sources, PVR avancé,
  multiview, mode sport augmenté, thèmes/templates additionnels. **Jamais de
  paywall sur la lecture de base** (réputation + conformité). Essai long
  (les essais longs convertissent à 45,7 % vs 26,8 %, RevenueCat 2025).
- **Pas de pub insérée dans les flux** : le tier pub des géants (60 %+ des
  inscriptions Netflix) ne se transpose pas à un lecteur neutre sans droits sur
  le contenu — risque juridique et de réputation. La « gratuité financée »
  reste côté opérateur (B2B2C).

### 4.6 Les boucles de rétention (Hook, assemblées)

| Étape | Implémentation SEVEN |
|---|---|
| Déclencheur externe | Rappels EPG posés + « nouvel épisode de ta série » + « ton équipe joue » (B17) — sobres, désactivables |
| Action | Ouvrir → l'accueil du template choisi → 1 OK = lecture (< 90 s garanti par le rang 0) |
| Récompense variable | « MA SOIRÉE » (habitude), Nouveautés pour toi, Top du parc, curve-ball « Surprends-moi » (D28) |
| Investissement | Favoris, profils, équipes, historique, template choisi — chaque signal améliore demain, donc le coût de départ monte |

North star (inchangée) : **minutes regardées/utilisateur actif/semaine** ;
juges de paix : J7, DAU/WAU > 50 %, TTFF < 2 s, activation < 5 min.

### 4.7 Plateformes & distribution (les faits 2026)

- Android TV/Google TV n°1 mondial (~34-43 %), mais **fragmentation** : Fire TV
  bascule sur Vega OS (sideload bloqué — être en store officiel devient
  vital) ; OS émergents à ~30 % du marché européen d'ici 2030 (Omdia).
- Notre couverture est déjà rare : Android TV/Fire TV (Flutter) + Tizen/webOS
  (web app `tv-tizen-webos/`). Faits à surveiller, sans dogme : Samsung
  supporte Flutter sur Tizen, LG prépare un SDK Flutter webOS (S1 2026) —
  notre pari Flutter TV vieillit bien ; Vega OS (React Native/web) se traite
  via la web app.
- **Conformité stores = production line** : lecteur vide à l'install, aucun
  marketing évoquant des contenus, monétisation 100 % fonctionnelle — ce qui
  nous a protégés des purges de 2025-2026 et a tué des concurrents.

---

## Phase 5 — Roadmap vers le Top 2 (réaliste et datée)

> S'appuie sur `ROADMAP-VAGUES.md` (30 vagues) — les vagues existantes sont
> référencées ; ce plan les ordonne vers l'objectif.

### Jalon 0 — « Parité pro des 4 templates » (cette semaine — chantier en cours)

Fait aujourd'hui : aperçu vidéo fiabilisé en B, ajouté en C et D (+ garde
petite-box réaligné). Reste, par ordre d'impact (audit §2-3) :
1. Restauration du focus au BACK en D (le bug « repart en haut » y est entier) ;
2. `TvExitDialog` commun (localisé, autofocus, option Redémarrer) en B/C/D ;
3. Localisation des textes en dur de B et C (+ descriptions des templates) ;
4. Horloge + logo en D ; autofocus héro de C gardé par `_restoreId` ;
5. Une seule expérience « Direct » ; tuile « Favoris » de C corrigée.

### Jalon 1 — « L'habitude » (mois 1-2) — J7 comme seule cible

Rappels EPG locaux (cloche) → reprise VOD à la position → rangée Reprendre en
C/D → autoplay épisode suivant (annulable) → accueil rang 0/1/2 sur les
4 templates (B12-B15). Squelettes + transitions (V2/V3). Mesure : J7, TTFF.

### Jalon 2 — « Le différenciateur » (mois 3-6)

Mode Sport v1 (match center + rappels équipes, 4 templates) ; enrichissement
EPG/affiches côté client ; « Surprends-moi » (D28) ; récap hebdo sobre ;
push distant opt-in ; Top du parc (B19 → C24, agrégé/anonyme).

### Jalon 3 — « La conquête » (mois 6-12)

Tizen/webOS au niveau Android TV (parité templates) ; recherche
conversationnelle via worker (D30) ; multiview sport 2×2 poli ; programme
opérateurs (panel self-service, white-label léger) — le canal B2B2C devient la
machine d'acquisition : chaque opérateur amène son parc.

### Jalon 4 — « Top 2 » (mois 12-36)

tvOS (le désert concurrentiel identifié) ; Vega OS via web app ; LL-HLS côté
relais pour le sport ; watch-party (vide concurrentiel confirmé) ;
expérimentation systématique (A/B léger par flags panel). Critère de victoire :
**n°2 en installations actives de la catégorie lecteurs neutres multi-OS, n°1
en minutes/utilisateur** — la métrique que Netflix regarde vraiment.

### Ce qu'on refuse (aussi important que le reste)

Pas de contenu fourni ni agrégé « gratuit » (Filmspeler). Pas de dark patterns
(countdown non annulable, opt-out cachés). Pas de télémétrie sans opt-in. Pas
de 5e template avant que les 4 soient irréprochables. Pas de feature qui casse
le budget petite-box (`TvMemoryGuard` est un contrat).

---

*Document vivant. Prochaine révision : après le Jalon 0 (parité), avec les
premières mesures J7/TTFF réelles du parc (panel C21).*
