# TV King — Référentiel de conception (recherche sourcée)

> Document de référence pour l'application **TV uniquement** (expérience « 10-foot UI »).
> Toutes les valeurs proviennent de recherches en ligne sur des sources officielles ou
> reconnues. Les points incertains ou issus de sources secondaires sont **signalés**.
> Date de compilation : 2026-06-01.

---

## 1. Normes officielles des plateformes TV

| Plateforme | Safe-area / overscan | Modèle de focus | Navigation |
|---|---|---|---|
| **Apple tvOS** | 60 pt haut/bas ; **80 pt** côtés (HIG) / **90 pt** côtés (WWDC19) | jusqu'à **5 états** de focus, parallaxe + agrandissement, **jamais de curseur** | moteur de focus à la télécommande ; bouton Menu = retour |
| **Android TV / Google TV** | **5 % par bord = 48dp côtés / 27dp haut-bas** (base 960×540dp) ; grille 12 colonnes | focus sur l'élément **le plus proche** dans la direction | **D-pad 4 directions** ; pas de bouton retour à l'écran |
| **Roku** | **≥ 5 %** (~90px / ~60px en 1080p) | surbrillance de focus claire | flux haut→bas, gauche→droite |
| **Amazon Fire TV** | éviter les **5 % extérieurs**, garder dans les **90 % intérieurs** | doit clairement montrer le focus | D-pad directionnel ; menu global à gauche |
| **Samsung Tizen** | grille recommandée | « moving focus » / « fixed focus » | 4 directions + OK + retour + exit |
| **LG webOS** | garder les éléments sélectionnables dans la Safe Area | **effet de sélection obligatoire** | Magic Remote (pointeur) **ou** 4 directions (pas les deux en même temps) |

**Sources :** developer.apple.com/design/human-interface-guidelines (Focus and selection, Layout, Dark Mode) ; developer.apple.com/videos/play/wwdc2019/211 ; developer.android.com/design/ui/tv/guides/styles/layouts ; developer.android.com/design/ui/tv/guides/foundations/navigation-on-tv ; developer.roku.com/docs/developer-program/design/key-design-principles.md ; developer.amazon.com/docs/fire-tv/design-and-user-experience-guidelines.html ; developer.samsung.com/smarttv/design/design-principles.html ; webostv.developer.lge.com/develop/guides/design-principles.

**Convergence inter-plateformes :** rail de navigation vertical à gauche + rangées (« rows/rails ») horizontales personnalisées (Netflix, Hulu, Disney+, ESPN). *(P)*

**⚠️ Conflits signalés :** tvOS côté 80pt (HIG) vs 90pt (WWDC) ; Android 48/27dp vs 58/28dp selon contexte (marge simple vs grille 12 colonnes). Plusieurs pages (Apple/Roku/Amazon/Samsung/LG) bloquent le fetch automatique (403) → valeurs confirmées via extraits de recherche.

---

## 2. Calculs exacts d'adaptation à toute télévision

### Résolutions & ratio
- **Toutes les TV modernes sont en 16:9.** (Android TV docs)
- **tvOS rend en 1920×1080** ; l'Apple TV 4K fait un **pixel-doubling ×2 propre** (3840×2160) → le texte/vectoriel scale sans changement de layout. (9to5mac, appleinsider)
- **Samsung Tizen / LG webOS web apps : concevoir pour un canvas logique 1920×1080**, la TV redimensionne vers 1280×720 (FHD). (developer.samsung.com, webostv.developer.lge.com)

### Overscan / Safe areas
- **Android TV (officiel) :** marge **5 % par bord = 48dp côtés / 27dp haut-bas** sur base 960×540dp (→ ~96px / ~54px en 1920×1080). Ne **pas** doubler si on utilise Leanback.
- **tvOS (WWDC19) :** safe area = **90pt côtés / 60pt haut-bas** (= 90px/60px en 1920×1080).
- **Broadcast SMPTE ST 2046-1 (moderne) :** Safe Action = **93 %**, Safe Title = **90 %**. Legacy SMPTE : 90 % action / 80 % titre.

→ **Décision projet :** padding de sécurité **horizontal 5vw (~96px@1920)**, **vertical 5vh (~54px@1920)**, plancher `max(48px, …)`.

### Distance de visionnage & tailles de police
- Hypothèse standard : **~10 pieds / 3 m**. (Android TV, Apple HIG)
- **Plancher de lisibilité ~24px** ; texte < 22px illisible à distance TV. *(D — Smashing/Protopie, résumé)*
- Android TV : Roboto, éviter les graisses fines ; legacy ~12sp min / ~18sp body *(⚠️ ancienne doc)*.
- tvOS : body ~29pt, titres ≥48pt *(⚠️ sources secondaires, HIG en JS non lisible)*.
- Règle AV (Extron) : **min 10 arc-minutes** (15–20 plus sûr) ; ~**1 pouce de hauteur de texte / 15 pieds** *(⚠️ page 403)*.

### Techniques CSS de scaling (sans zoom excessif)
- **Pattern dominant TV :** concevoir sur canvas **1920×1080 fixe** et laisser la plateforme scaler tout l'app (Samsung/LG). → on reproduit ça en faisant **`font-size` racine = fonction de `100vw`** pour que tout (en `rem`) scale proportionnellement sur n'importe quelle largeur en conservant le 16:9.
- `1vw` = 1 % largeur viewport ; `10vw` = 192px @1920.
- **`clamp(min, fluide-vw, max)`** pour un type fluide borné, ex. `clamp(1.5rem, 2.5vw, 3rem)`.
- Préférer **`transform: scale()`** aux animations de vw/vh ; débouncer `resize`.
- `devicePixelRatio` : compenser sur WebView Android TV (`zoom = 1/dpr`) *(⚠️ communautaire)*.

### Densité (Android)
- **Formule : `px = dp × (dpi / 160)`**. Baseline mdpi 160dpi = ×1.0. tvdpi 213dpi = ×1.33 ; xhdpi 320 = ×2.0 ; xxhdpi 480 = ×3.0. (developer.android.com/training/multiscreen/screendensities)

---

## 3. Palette de couleurs reposante pour grand écran

- **Jamais de noir pur `#000000`** : utiliser un gris très foncé. Material : surface de base **`#121212`** ; le texte clair sur gris foncé a moins de contraste que sur noir → **moins de fatigue**. (m2.material.io/design/color/dark-theme.html)
- **Élévation par overlay blanc translucide** sur `#121212` : 0 % (0dp) → 16 % (24dp). *(table par niveau = convention reproduite, ⚠️ non re-vérifiée ligne à ligne)*
- **Jamais de blanc pur `#FFFFFF`** pour le texte : effet de **halation** (halo qui « bave »), aggravé par l'astigmatisme (~50 % de la population). (levelaccess.com ; Material text-legibility)
- **Opacités de texte Material (blanc sur sombre) :** haute **87 %**, moyenne **60 %**, désactivé **38 %**. Équivalent off-white ~`#E0E0E0`–`#F0F0F0` *(⚠️ secondaire)*.
- **Contrastes WCAG :** AA = **4.5:1** texte normal / **3:1** grand texte (≥18pt, ou 14pt gras) ; AAA = **7:1** / 4.5:1. UI/non-texte = **3:1**. (w3.org/WAI/WCAG21). Material vise **≥15.8:1** pour le body sur `#121212`.
- **Accents :** en thème sombre, utiliser des **tons clairs/désaturés (échelle 50–200)**, **pas** les tons saturés 500–900 qui « vibrent ». Réserver les couleurs de marque vives à de **petits accents focaux**. (m2.material.io ; design.google)
- **Luminance / fatigue :** adapter la luminosité à l'ambiance ; **~120–180 nits** en pièce sombre ; point blanc plus chaud (6500K→5000K) réduit la lumière bleue ~19 % *(⚠️ blogs optométrie/vendeurs)*. Règle 20-20-20.
- Exemples réels : Spotify base `#191414`/`#121212` ; iOS system background `#1C1C1E` *(secondaire)* ; accents vifs utilisés avec parcimonie (Spotify `#1ED760`, Netflix `#E50914`).

---

## 4. UX engageante (« addictive ») mais simple

- **Modèle Hooked (Nir Eyal) :** Déclencheur → Action → **Récompense variable** → Investissement. La variabilité soutient l'engagement ; l'investissement (likes, historique) personnalise et recharge le déclencheur. (nirandfar.com ; amplitude.com)
- **Rangées Netflix à 3 couches de personnalisation :** quelles rangées + leur ordre ; quels titres dans chaque rangée ; l'ordre des titres (meilleurs à gauche). (help.netflix.com/en/node/100639 ; research.netflix.com)
- **« Continue Watching » :** algorithme dédié (Continue Watching Ranker) classant par probabilité de reprise. (research.netflix.com)
- **Vignettes/artwork = ~82 % de l'attention** au survol ; Netflix est passé de l'A/B testing aux **contextual bandits** pour personnaliser l'artwork. (netflixtechblog.com/artwork-personalization-c589f074ad76)
- **Fenêtre d'attention 60–90 s :** si l'utilisateur ne trouve rien en ~60-90 s, risque d'abandon ↑ ; il parcourt ~10-20 titres, ~3 en détail. (NBC News, Quartz). Engagement concentré en **haut-gauche** (paper recsys Netflix).
- **Autoplay épisode suivant :** balayage de couleur (~5 s) avant lecture auto ; « la plus grosse hausse d'heures vues jamais testée » selon un ingénieur Netflix. (arxiv 2412.16040 ; help.netflix.com ; HN). ⚠️ **Critique dark-pattern** : 5 s trop court. → on l'implémente **avec contrôle utilisateur** (NN/g : la vidéo n'est utile que si l'utilisateur garde le contrôle).
- **Hick's law / surcharge de choix :** trop d'options = paralysie/abandon ; limiter les options primaires (~5-7), divulgation progressive, mettre en avant un « Recommandé ». (lawsofux.com ; NN/g progressive disclosure).
- **10-foot UX :** tout en grille avec un élément de focus clair ; **minimiser la saisie texte** (préférer voix) ; faible densité, grands éléments ; objectif « donne-moi quoi regarder maintenant » en un minimum d'étapes. (developer.android.com/training/tv ; developer.amazon.com ; Microsoft « Designing for Xbox and TV »).

---

## 5. Organisation des catégories — Sport & Formation

### Architecture générale
- **Shell universel :** nav verticale gauche + rangées horizontales personnalisées + **navigation à facettes** pour la profondeur. La nav à facettes peut réduire le temps de recherche de **20-50 %** (attribué NN/g).
- **Tagging fin** (humeur, rythme, ton…) au-delà du genre de surface ; ontologie/knowledge-graph.
- **Cartes Android TV (spec officielle)** : 5 types (Standard, Classic, Compact avec scrim, Wide Standard, Wide Classic) ; **3 ratios : 16:9** (vidéo), **1:1** (logos équipe/chaîne/intervenant), **2:3** (affiche) ; espacement « peek » 20dp ; métadonnées révélées **au focus** ; focus = scale + ombre. (developer.android.com/design/ui/tv/guides/components/cards)

### SPORT
- **Couche live distincte :** badge **« LIVE »** (souvent rouge) + **horloge/minute du match** + score ; état **tri-state : Live / À venir (Rappel) / Replay**. (zegocloud/DAZN ; espn.com/watch/schedule ; sportmonks)
- **EPG (grille de programme)** pour les chaînes live.
- **Modèle by-team / by-league / by-sport** (Apple « My Sports » : suivre des équipes → leurs matchs remontent dans Continue Watching + notifications à l'approche). (support.apple.com)
- **Notifications à fort impact uniquement** (but, carton rouge, début) — opt-in par équipe/ligue. (sportmonks)
- **« Where to Watch »**, Multiview, stats live, replays (ESPN 2024-2025).

### FORMATION / ÉDUCATION
- **Hiérarchie graduée** (Coursera) : Projet guidé → Cours → Spécialisation (~4-10 cours) → Certificat pro → Diplôme. (coursera.org)
- **Facettes : sujet, intervenant, compétence, type, NIVEAU (débutant/intermédiaire/avancé), langue, durée.** (coursera.org/browse ; 360learning)
- **Suivi de progression visuel** (% complété, tableaux de bord) jugé (très) important par ~90 % ; **parcours d'apprentissage personnalisés**.
- **MasterClass :** 13 catégories, organisé par **intervenant** ; cours = 10-20 leçons de ~10-15 min ; autoplay-next ; présentation cinématographique type Netflix. (masterclass.com/categories)
- **Fitness (Peloton/Apple Fitness+) :** facettes durée, type, **intervenant**, **niveau de difficulté**, musique ; tri new/trending/popular/top-rated/easiest/hardest ; détail = playlist, note, niveau, métriques. (pelobuddy.com ; Apple Fitness+).

### Métadonnées par carte
- **Sport/live :** badge LIVE (rouge), horloge/minute, score, heure de début / compte à rebours, état « Rappel activé ».
- **Formation :** durée, **niveau**, intervenant, **% de progression**, note.

### Recherche & découverte TV
- **Browse-first** (les rangées + facettes portent la découverte) ; la recherche texte est secondaire (saisie télécommande pénible) ; **voix** (Google Assistant : bouton micro) ; téléphone-compagnon pour la saisie.

---

## Ancres chiffrées les plus fiables (à implémenter)
- Canvas **1920×1080, 16:9** ; scale global via `font-size` racine ∝ `100vw`.
- Safe area **5vw / 5vh** (≈96px / 54px @1920), plancher `max(48px,…)`.
- Plancher texte **≥24px** ; type fluide via `clamp()`.
- Fond **`#121212`** (jamais `#000`) ; texte **87/60/38 %** (jamais `#FFF`) ; accents **désaturés tons 50–200**.
- Contraste **AA 4.5:1** (3:1 grand texte/UI), viser plus haut.
- Cartes **16:9 / 1:1 / 2:3**, peek ~20dp, métadonnées au focus, focus = scale + ombre + ring.
- Sport : tri-state **Live / À venir / Replay** + badge LIVE rouge + minute/score.
- Formation : facette **niveau** + **progression** + intervenant + durée.

## Légende des niveaux de confiance
- **(D)** bonne pratique documentée — **(P)** pattern observé répandu — **⚠️** source secondaire / non vérifiée en primaire / conflit.
