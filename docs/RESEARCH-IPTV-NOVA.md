# NOVA+ — Référentiel de conception IPTV (recherche sourcée)

> Complément orienté **IPTV (Live TV / VOD / EPG)** au document `RESEARCH-TV-UX.md`
> (qui couvre normes plateformes, scaling, safe-areas). Ici : ce qui est **spécifique
> aux apps IPTV pour télévision** — l'app de référence du marché, le jeu de
> fonctionnalités attendu, l'UX live, et une **palette NOVA+ chiffrée**.
> Couleurs reposantes pour les yeux **+** UX engageante (« addictive ») mais maîtrisée.
> Date de compilation : 2026-06-06. Légende : **(D)** documenté — **(P)** pattern répandu — **⚠️** source secondaire / à confirmer.

---

## 0. Pourquoi la plupart des apps IPTV échouent sur TV
La cause n°1 d'échec sur Android TV n'est **pas** la qualité de lecture mais l'**UI** :
les apps lancent une interface pensée pour téléphone en 1080p sur un écran de 55" →
texte minuscule, listes de chaînes serrées, cibles de focus impossibles à atteindre au
D-pad. **NOVA+ doit être pensée 10-foot dès le départ** (gros éléments, focus net,
navigation télécommande sans curseur, EPG lisible à 3 m). *(P — synthèse multi-sources)*

---

## 1. App de référence du marché : TiViMate (le mètre-étalon)
TiViMate est quasi unanimement « le roi » des lecteurs IPTV sur Android TV : interface
qui paraît **native Android TV**, et surtout l'un des **meilleurs EPG** (grille claire,
navigation fluide). C'est le niveau de qualité d'expérience à **égaler** (sans copier ses
assets). Autres références citées : **IPTV One** (91/100 sur 5 critères : design UI,
formats, sync multi-appareils, qualité EPG, expérience VOD), **Perfect Player** (simple,
thèmes + scaling d'UI), **IPTV Smarters Pro**, **XCIPTV**. *(P)*

**Les 5 critères de jugement d'une app IPTV TV** (à reprendre comme grille de recette) :
1. Design UI 10-foot ; 2. Support des formats/playlists ; 3. Sync multi-appareils ;
4. **Qualité de l'EPG** ; 5. **Expérience VOD**. *(P — IPTV One / GridStreamr)*

---

## 2. Jeu de fonctionnalités IPTV attendu (TiViMate comme baseline)
À trier en **must-have / nice-to-have** avec le client, mais voici la baseline du marché :

| Fonction | Détail | Priorité type |
|---|---|---|
| **Multi-playlist** | Xtream Codes API **et** M3U + URL XMLTV pour l'EPG | must |
| **EPG (guide grille)** | XMLTV ; programme courant + à venir par chaîne ; détails programme ; **now/next** | must |
| **Groupes de chaînes** | catégories du playlist = « groups » dans le rail gauche ; masquables/réordonnables | must |
| **Favoris** | marquer des chaînes, **groupes personnalisés** | must |
| **Catch-up / Replay** | si le provider le supporte : revoir les X derniers jours depuis l'EPG | nice→must |
| **Enregistrement (nDVR)** | enregistrer le live (stockage local/externe), **planifié depuis l'EPG** | nice (premium) |
| **Multi-view** | jusqu'à **9 chaînes** simultanées (fans de sport) | nice (premium) |
| **Picture-in-Picture** | mini-lecteur flottant pendant qu'on parcourt l'EPG/réglages | nice |
| **Recherche** | recherche avancée chaînes/programmes ; **voix** de préférence (saisie D-pad pénible) | must |
| **Contrôle parental** | verrouillage de chaînes/catégories par code | nice |
| **VOD / Séries** | rangées type Netflix, reprise de lecture, artwork | must (si périmètre VOD) |

**Sources :** [tivimateiptvplayer.net](https://tivimateiptvplayer.net/mastering-tivimate/) · [litiptv.com](https://litiptv.com/blog/tivimate-review-guide) · [tivimate.co.com/features](https://tivimate.co.com/app/features/) · [troypoint.com](https://troypoint.com/tivimate-iptv-player/) · [gridstreamr.com](https://www.gridstreamr.com/blog/best-iptv-app-android-tv-2026) · [iptv-one.app](https://www.iptv-one.app/en/blog/best-iptv-player-android-tv) · [smarter8k.app](https://smarter8k.app/blog/best-iptv-players)

---

## 3. UX live spécifique IPTV (au-delà des rangées VOD)
- **Zapping rapide** : changement de chaîne quasi instantané = critère perçu n°1 de qualité ;
  garder un buffer court, préchauffer la chaîne suivante. ⚠️ à mesurer (objectif <1,5 s).
- **Mini-EPG overlay** : un appui OK/Haut en plein écran affiche un bandeau **now/next**
  + numéro + logo chaîne, sans quitter la vidéo. *(P — TiViMate)*
- **Liste de chaînes en surimpression** (channel list overlay) navigable au D-pad pendant
  que la vidéo continue ; PiP pour parcourir l'EPG sans couper. *(P)*
- **Grille EPG** : axe X = temps (lignes de demi-heures), axe Y = chaînes ; programme en
  cours mis en évidence ; OK = détails + (replay si dispo) + planifier enregistrement. *(D)*
- **Logos de chaînes** en **ratio 1:1** (cartes Android TV : 16:9 vidéo, **1:1 logos**, 2:3 affiches). *(D)*
- **Browse-first / saisie minimale** : pas de grosse barre de recherche en accueil ;
  navigation haut-bas (catégories) × gauche-droite (items) ; voix > clavier. *(D)*
- **Dernières chaînes / Reprendre** : accès rapide aux chaînes récentes et reprise VOD. *(P)*

---

## 4. Palette NOVA+ — reposante pour les yeux **et** engageante
Principes confirmés (cf. aussi `RESEARCH-TV-UX.md` §3) : **jamais de noir pur ni de blanc
pur** ; sur TV les couleurs paraissent **plus saturées/vives** → préférer des teintes
**sourdes et froides**, réserver les couleurs vives à de **petits accents focaux**.
*(D — Material dark theme ; Android TV color system M3 ; bsgroup.eu)*

### Proposition de palette (dark-first, à valider avec l'identité NOVA+)
| Rôle | Hex | Note |
|---|---|---|
| Fond base (surface 0dp) | `#101418` | gris très foncé, légère teinte bleue (repos) — jamais `#000` |
| Surface élevée (cartes) | `#171C22` → `#1E242B` | élévation par overlay clair translucide croissant |
| Texte haute emphase | `#E8EAED` (~87 %) | off-white, anti-halation — jamais `#FFF` |
| Texte moyenne emphase | `rgba(232,234,237,.60)` | sous-titres, métadonnées |
| Texte désactivé | `rgba(232,234,237,.38)` | |
| **Accent primaire NOVA+** | `#3DA9FC` (bleu désaturé clair) | focus ring, sélection, boutons clés — **placeholder** à caler sur la marque |
| Accent secondaire | `#7C5CFC` (violet doux) | catégories, chips |
| **LIVE / direct** | `#FF4D4F` | badge LIVE uniquement (rouge, petit, focal) |
| Succès / progression | `#3DDC97` | barres de progression, « enregistré » |
| Outline / dividers | `rgba(232,234,237,.12)` | bordures discrètes |

- **Focus = signal le plus fort** : anneau accent + **scale ~1.06–1.1** + ombre/élévation
  (jamais juste un changement de couleur). *(D — toutes plateformes)*
- **Contraste** : viser **WCAG AA 4.5:1** mini (texte), 3:1 UI ; body sur `#101418` ≈ 14:1.
- **Luminance** confortable en pièce sombre (~120–180 nits) ; point blanc plutôt chaud. ⚠️
- ⚠️ Android TV (M3) recommande de **générer les tons via Material Theme Builder** à partir
  d'**une couleur de marque racine** → dès que le client donne le logo/couleur NOVA+, on
  génère la palette complète (13 tons/clé) et on remplace les placeholders ci-dessus.

**Sources :** [developer.android.com — TV color system](https://developer.android.com/design/ui/tv/guides/styles/color-system) · [m2.material.io — dark theme](https://m2.material.io/design/color/dark-theme.html) · [bsgroup.eu](https://www.bsgroup.eu/blog/tips-for-ui-ux-design-on-smart-tv/) · [designstudiouiux.com](https://www.designstudiouiux.com/blog/dark-mode-ui-design-best-practices/) · [netguru.com](https://www.netguru.com/blog/tips-dark-mode-ui) · [sashikiran.com — Netflix color](https://sashikiran.com/netflix-strategy/)

---

## 5. UX « addictive » mais maîtrisée (adaptée au live + VOD)
- **Boucle Hooked** (Déclencheur → Action → **Récompense variable** → Investissement) :
  favoris, historique et reprise = investissement qui personnalise et fait revenir. *(D)*
- **Reprendre / Continue Watching** en première rangée (VOD) ; **dernières chaînes** (live).
- **Artwork personnalisé** = ~82 % de l'attention au survol → soigner posters/logos. *(D)*
- **Fenêtre des 60–90 s** : l'utilisateur abandonne s'il ne trouve rien vite → mettre le bon
  contenu **en haut à gauche**, limiter les choix primaires (Hick's law ~5–7). *(D)*
- **Autoplay « à suivre »** : compte à rebours **annulable** (NN/g : la vidéo n'engage que si
  l'utilisateur garde le contrôle) — éviter le dark-pattern des 5 s trop courtes. *(D / ⚠️)*
- **Notifications à fort impact uniquement** (début d'un direct suivi, but) — opt-in. *(D)*

---

## 6. Navigation D-pad — comportements IPTV à spécifier
- 4 directions + OK + **Retour** (remonte d'un niveau ; ne quitte pas l'app sur Android TV).
- **Plein écran live** : OK = mini-EPG/now-next ; Haut/Bas = chaîne ±1 (zapping) ;
  Gauche/Droite = liste chaînes / EPG overlay ; **canaux numériques** (taper le n° de chaîne).
- **Touches média** : Play/Pause, ±10 s (replay/VOD), Stop.
- **Appui long OK** : menu contextuel (favori, PiP, infos, enregistrer).
- Focus toujours visible et prévisible (élément le plus proche dans la direction). *(D)*

---

## 7. Grille de recette (« c'est validé quand… ») — proposition
- [ ] Zapping live < ~1,5 s perçu ; démarrage lecteur < ~3 s. ⚠️ à fixer avec le client
- [ ] EPG grille lisible à 3 m, navigation fluide 50+ chaînes sans lag.
- [ ] Tout atteignable au **D-pad seul** (aucune zone piège au focus).
- [ ] Texte ≥ 24px effectif ; contraste AA ; aucun `#000`/`#FFF` pur.
- [ ] Favoris + reprise + dernières chaînes fonctionnels et persistés.
- [ ] Identité **NOVA+ propre** (zéro asset/logo/marque copié de l'app de référence).

---

## À compléter dès réception des infos client
1. **Nom + lien de l'app de référence** → audit écran par écran, reproduction des parcours.
2. **Logo / couleur de marque NOVA+** → génération palette M3 (remplace les placeholders §4).
3. Périmètre exact (Live / VOD / Séries / EPG / Replay / Enregistrement / Multi-view / Cast).
4. Source de données (Xtream / M3U / API) + gestion par MAC + backend à réutiliser ou créer.
5. Cible technique (WebView wrapper vs natif Android), minSdk, distribution.
