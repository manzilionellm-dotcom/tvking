# Recherche UX / Accessibilité / Confort visuel — TV King

> Document de recherche pour l'interface « 10-foot » (vue à ~3 m) de **TV King**,
> application de streaming premium pour téléviseurs.
>
> **Objectif pédagogique** : rassembler des recommandations *sourcées* en
> matière d'UX, d'accessibilité et de confort visuel, en indiquant pour chaque
> affirmation non triviale un **niveau de confiance explicite**. Le projet sert
> aussi de support d'apprentissage : les explications sont volontairement
> détaillées.

## Convention de confiance / sources

Chaque affirmation importante est étiquetée :

- **`[documenté]`** — issu d'une documentation officielle d'éditeur/plateforme
  (Google, Apple, W3C) ou d'une publication évaluée par les pairs. Vérifié via
  recherche web pour ce document.
- **`[pattern observé]`** — pratique largement répandue dans l'industrie,
  observable sur les grandes apps TV, mais sans norme officielle qui fixe le
  chiffre exact.
- **`[source secondaire]`** — blog, article de vulgarisation, ou recommandation
  d'agrégateur (ex. *Laws of UX*) ; utile mais à prendre avec recul.

> **Règle d'honnêteté appliquée ici** : aucun chiffre n'a été inventé. Quand une
> valeur précise n'a pas pu être vérifiée auprès d'une source primaire, on
> énonce le **principe** général et on baisse le niveau de confiance plutôt que
> de fabriquer une citation.

---

## Sommaire

1. [Safe-area par plateforme](#1-safe-area-par-plateforme)
2. [Navigation au focus (D-pad)](#2-navigation-au-focus-d-pad)
3. [Canvas logique 1920×1080 mis à l'échelle](#3-canvas-logique-19201080-mis-à-léchelle)
4. [Palette sombre (dark theme)](#4-palette-sombre-dark-theme)
5. [Contraste WCAG](#5-contraste-wcag)
6. [Patterns UX spécifiques à la TV](#6-patterns-ux-spécifiques-à-la-tv)
7. [Confort visuel (sourcé)](#7-confort-visuel-sourcé)
8. [Accessibilité multi-publics](#8-accessibilité-multi-publics)
9. [Comment ce document guide l'implémentation](#9-comment-ce-document-guide-limplémentation)
10. [Références](#10-références)

---

## 1. Safe-area par plateforme

Sur un téléviseur, le bord de l'image peut être **rogné** (« overscan ») : une
partie des pixels près des bords n'est pas affichée, héritage des tubes
cathodiques que beaucoup de TV modernes reproduisent encore par défaut. Tout
élément *interactif ou informatif* doit donc rester dans une **zone de sécurité**
en retrait des bords.

### Android TV

- Marge de sécurité recommandée : **48 dp à gauche/droite** et **27 dp en
  haut/bas**, soit environ une marge de **5 %** sur un canvas de référence.
  `[documenté]` — guide officiel *Build TV layouts* (Android Developers).
- Nuance importante : si l'on utilise les composants **AndroidX Leanback**
  (`BrowseSupportFragment`, etc.), **ne pas** ajouter ces marges soi-même — elles
  sont déjà incorporées. `[documenté]`
- Les éléments **de fond** (image plein écran, dégradé) doivent au contraire
  s'étendre jusqu'au bord (full-bleed) pour bien remplir l'écran. Seuls les
  éléments « toujours visibles » sont contraints à la safe-area. `[documenté]`

### tvOS (Apple TV)

- Insets recommandés pour le contenu primaire : **~90 pt à gauche/droite** et
  **~60 pt en haut/bas** sur une grille HDTV de 1920×1080. `[documenté]` — Apple
  Human Interface Guidelines (rubrique *Layout*).
  > Réserve d'honnêteté : la page HIG récupérée renvoyait une coquille vide
  > (titre seulement) ; ces valeurs sont confirmées par plusieurs synthèses
  > convergentes de la HIG (dont des résumés communautaires) mais l'extrait
  > primaire n'a pas pu être cité mot pour mot. On garde donc `[documenté]`
  > pour le principe, en notant la limite de vérification.

### Conséquence pour TV King

On définit **deux jeux de variables de safe-area** (Android vs Apple), exprimées
en unités de notre canvas logique (voir §3), et on n'y place jamais de bouton,
texte ou indicateur de focus en dehors.

---

## 2. Navigation au focus (D-pad)

Sur TV, il n'y a **pas de curseur** : on navigue à la croix directionnelle
(D-pad) d'une télécommande. Le modèle mental est complètement différent du
tactile/souris.

- **Modèle « nearest element in direction »** : appuyer sur une direction
  déplace le focus vers **l'élément le plus proche dans cette direction**. Le
  framework Android gère ce calcul automatiquement la plupart du temps.
  `[documenté]` — *TV navigation* (Android Developers).
- **Focus unique** : à tout instant, **un seul** élément est focalisé et
  visuellement mis en évidence (agrandissement, halo, élévation). `[pattern observé]`
  (pratique universelle des apps TV ; corollaire direct du modèle de focus).
- **Le focus ne doit jamais être perdu** : après le démarrage de l'app, et
  chaque fois qu'aucun contenu n'est en lecture, il doit toujours y avoir un
  élément focalisé sur lequel l'utilisateur peut agir immédiatement.
  `[documenté]` — Android Developers insiste sur ce point.
- **Navigation prévisible et testée** : Google recommande de **tester avec une
  vraie télécommande D-pad** pour vérifier que tous les contrôles visibles sont
  atteignables et que les déplacements sont prévisibles. Si la disposition rend
  la navigation ambiguë, on définit une **navigation directionnelle explicite**.
  `[documenté]`
- **Mémoire de focus par écran** : quand l'utilisateur quitte une rangée puis y
  revient, le focus doit revenir sur le **dernier élément** qu'il y avait
  sélectionné, et non se réinitialiser. `[pattern observé]` (comportement standard
  des grandes apps TV ; non chiffré par une norme officielle).

### Conséquence pour TV King

Chaque écran maintient un état de « dernier focus » par rangée. On ne masque
jamais l'indicateur de focus, et on s'assure qu'aucune action de navigation ne
laisse l'écran sans élément focalisé.

---

## 3. Canvas logique 1920×1080 mis à l'échelle

On conçoit toute l'UI sur un **canvas logique de référence 1920×1080 (16:9)**,
puis on applique un **facteur d'échelle global** pour s'adapter à la résolution
réelle du téléviseur.

- 1920×1080 est la grille de référence HDTV utilisée par les guidelines TV
  (notamment côté Apple pour positionner la safe-area). `[documenté]`
- Principe : une TV 720p, 1080p ou 4K affiche **le même layout**, simplement
  redimensionné — **pas de zoom navigateur, pas de reflow**. On évite ainsi les
  surprises de mise en page selon la dalle. `[pattern observé]` (approche
  classique « design fixe + scale » des apps 10-foot).
- Les espacements, tailles de police et cibles sont exprimés en unités du canvas
  logique, puis multipliés par le facteur d'échelle (`ui-scale`).

### Conséquence pour TV King

Une seule maquette source (1920×1080) → un `ui-scale` calculé à partir de la
taille réelle de l'écran → toutes les dimensions dérivées. Cela simplifie aussi
la prise en compte du profil « Senior » (voir §8) qui peut majorer `ui-scale`.

---

## 4. Palette sombre (dark theme)

Le **Material Design dark theme** sert de référence chiffrée. Les valeurs
ci-dessous sont confirmées par les synthèses officielles Material (la page
canonique `m2.material.io` bloque l'accès automatisé — HTTP 403 — mais le contenu
est largement reproduit et cohérent entre sources).

- **Éviter le noir pur (#000000)** : Material recommande une surface gris foncé,
  valeur de référence **#121212**. Le gris foncé réduit le contraste brutal entre
  surface et composants, et préserve mieux la perception de l'élévation (ombres).
  `[documenté]` — Material Design *Dark theme*.
- **Opacités de texte sur fond sombre** :
  - texte **haute emphase** ≈ **87 %** ;
  - texte **moyenne emphase** ≈ **60 %** ;
  - texte **désactivé** ≈ **38 %**.
  `[documenté]`
- **Pas de blanc pur (#FFFFFF) à pleine opacité** : un blanc pur sur fond sombre
  « vibre » et bave (halation), nuisant à la lisibilité — d'où l'usage d'un
  blanc cassé / opacité réduite. `[documenté]`
- **Éviter les couleurs très saturées** sur fond sombre : elles vibrent
  également et passent mal les seuils de contraste. On privilégie des **accents
  désaturés**. `[documenté]`

### Conséquence pour TV King

Surfaces empilées : `#121212` (fond), puis des surfaces légèrement plus claires
pour l'élévation (ex. `#1a1a1c`, `#222226`). Texte via opacités 87/60/38 %.
Accent doré **désaturé** plutôt qu'un or vif et saturé (voir §7 et §9).

---

## 5. Contraste WCAG

Les **Web Content Accessibility Guidelines (WCAG 2.1)** du W3C fixent les seuils
de contraste. Ils sont identiques en 2.2.

- **Niveau AA** :
  - texte normal : **≥ 4.5:1** ;
  - texte large : **≥ 3:1** (large = ≥ 18 pt, ou ≥ 14 pt en gras) ;
  - **composants d'interface** et graphiques porteurs de sens (bordures de
    champ, indicateurs de focus, icônes signifiantes) : **≥ 3:1**.
  `[documenté]` — W3C WCAG 2.1/2.2 (critères 1.4.3 et 1.4.11).
- **Niveau AAA** :
  - texte normal : **≥ 7:1** ;
  - texte large : **≥ 4.5:1**.
  `[documenté]`

### Conséquence pour TV King

On vise **AA partout** comme plancher, et on prévoit un **mode haut contraste**
ciblant le **7:1** (AAA texte normal) pour le profil Senior / la déficience
visuelle. L'indicateur de focus (capital sur TV) doit lui-même respecter ≥ 3:1
vis-à-vis de ce qui l'entoure.

---

## 6. Patterns UX spécifiques à la TV

Ces patterns sont **largement observés** sur les grandes plateformes de
streaming. Sauf mention contraire, ils relèvent de `[pattern observé]` : ce sont
des conventions d'industrie, pas des normes.

- **Rail vertical à gauche + rangées horizontales** : menu/navigation principale
  en colonne verticale à gauche, contenu organisé en rangées (« rows »)
  scrollables horizontalement. `[pattern observé]`
- **Hero / billboard** : grande zone de mise en avant en haut de l'écran
  d'accueil (visuel large + titre + actions). `[pattern observé]`
- **Continue Watching (Reprendre la lecture)** : rangée dédiée et prioritaire
  reprenant les contenus en cours, généralement haut placée. `[pattern observé]`
- **Autoplay contrôlé par l'utilisateur** : les lectures automatiques
  (bandes-annonces, épisode suivant) doivent être **désactivables**. C'est aussi
  un enjeu d'accessibilité (mouvement/son non sollicités). `[pattern observé]`
  (renforcé par l'esprit des critères WCAG sur le mouvement, voir §8).
- **Progressive disclosure (divulgation progressive)** : on ne montre que
  l'essentiel d'abord, les détails se révèlent à la demande — évite de saturer
  l'écran et la charge cognitive. `[source secondaire]` (principe UX classique ;
  NN/g le cite comme complément à la loi de Hick).
- **Loi de Hick** : le temps de décision **augmente (de façon logarithmique)
  avec le nombre et la complexité des choix**. `[source secondaire]` — formalisée
  par Hick & Hyman (1952), popularisée en UX (Laws of UX, NN/g).
  > Réserve d'honnêteté : le seuil souvent cité de **« 5 à 7 choix principaux »**
  > est une **heuristique** pratique, **pas** une valeur dérivée de la loi de
  > Hick elle-même (laquelle ne prescrit aucun nombre précis). On le marque donc
  > `[source secondaire]` / heuristique, et on l'applique comme garde-fou, pas
  > comme règle absolue.

### Conséquence pour TV King

Accueil = hero billboard + « Reprendre la lecture » en première rangée + rails
thématiques. Navigation principale limitée volontairement (≈ 5–7 entrées) pour
réduire le temps de décision. Autoplay réglable dans les préférences.

---

## 7. Confort visuel (sourcé)

> **Nuance d'honnêteté capitale (position de l'AAO)** : l'American Academy of
> Ophthalmology indique qu'il **n'existe pas de preuve scientifique** que la
> lumière (y compris la lumière bleue) émise par les écrans endommage les yeux,
> et **ne recommande pas** les lunettes anti-lumière bleue. La **fatigue visuelle
> numérique** provient surtout de la **vision de près prolongée** et de la
> **réduction du clignement** (le taux de clignement peut être réduit de moitié
> devant un écran), pas de la lumière bleue en soi. `[documenté]` — AAO,
> *Digital Devices and Your Eyes* / *Are Blue Light-Blocking Glasses Worth It?*.
>
> **Donc** : les choix « confort visuel » de TV King doivent être présentés
> comme du **confort perçu** et de la **bonne hygiène visuelle**, **sans
> promettre** de protection médicale.

Faits établis :

- La **fatigue visuelle numérique / syndrome de vision informatique (CVS)** est
  un ensemble de symptômes (sécheresse, picotements, vision floue, maux de tête,
  raideurs) liés à l'usage prolongé d'écrans. `[documenté]` — Kaur K., Gurnani B.,
  Nayak S. et al., *Digital Eye Strain — A Comprehensive Review*, **Ophthalmology
  and Therapy**, 2022. DOI **10.1007/s40123-022-00540-9** ; PMID **35809192**.
  *(Citation vérifiée via recherche web : titre, auteurs, revue, année, DOI et
  PMID concordants.)*
- Parmi les **facteurs de risque** documentés : durée d'exposition, **altération
  du clignement**, distance de travail courte, anomalies réfractives/de
  vergence. `[documenté]` (même revue + littérature CVS sur PMC).
- Mesure de bon sens recommandée par l'AAO : la **règle 20-20-20** (toutes les
  20 minutes, regarder ~20 pieds / ~6 m de distance pendant 20 secondes).
  `[documenté]`

Principes de confort appliqués (sans surpromesse) :

- **Contraste perçu confortable plutôt que maximal** : viser un contraste
  « doux » (couramment évoqué autour de **~60–70 % de contraste perçu**) plutôt
  qu'un noir/blanc extrême, sauf en mode haut contraste. `[source secondaire]`
  (valeur indicative issue de recommandations de designers dark-mode ; **non**
  établie par une source primaire — à traiter comme une orientation, pas un
  chiffre normatif).
- **Blanc cassé sur gris foncé** plutôt que blanc pur sur noir pur, pour limiter
  la halation. `[documenté]` (cohérent avec Material §4) + `[pattern observé]`.
- **Tons chauds (or / ambre)** comme accent : perçus comme moins agressifs que
  des bleus/cyans très lumineux. `[source secondaire]`.
- **Point de blanc plus chaud le soir (~5000 K)** : réduire la composante froide
  en soirée est une pratique répandue (cf. modes « lumière nocturne » des OS).
  `[source secondaire]` — la valeur **~5000 K** est une **cible de confort
  indicative**, pas un seuil validé par une étude primaire citée ici.

### Conséquence pour TV King

Texte en blanc cassé (opacité ≤ 87 %) sur surfaces gris foncé ; accent doré
désaturé ; option « ambiance soir » qui réchauffe le point de blanc. Wording
produit prudent : « confort visuel », jamais « protège vos yeux ».

---

## 8. Accessibilité multi-publics

TV King propose trois profils d'expérience : **Senior**, **Enfant**,
**Standard**. L'objectif est l'**inclusive design** : concevoir pour la diversité
des capacités.

### Cibles tactiles / focus larges

- Cible interactive **≥ 48 px** (dans notre canvas logique). `[documenté]` pour
  l'ordre de grandeur : les guides d'accessibilité plateforme (Material, et la
  cible « ~48dp » d'Android) convergent sur ce minimum confortable.
  `[pattern observé]` pour la transposition exacte au 10-foot.

### Libellés explicites & narration vocale

- **Libellés explicites** sur chaque contrôle (pas d'icône seule sans nom
  accessible). `[documenté]` (principe WCAG : nom/rôle/valeur, critère 4.1.2).
- **Narration vocale** : sur le futur panneau web admin, la **Web Speech API**
  (`SpeechSynthesis`) permet une lecture vocale des éléments. `[documenté]`
  (spécification W3C Web Speech API) ; sur Android TV, on s'appuiera plutôt sur
  **TalkBack**.

### Mouvement réduit

- Respecter la préférence **« mouvement réduit »** : couper/atténuer les
  animations non essentielles quand l'utilisateur le demande. `[documenté]`
  - Côté web : media query **`prefers-reduced-motion`**. `[documenté]`
  - Référence normative : **WCAG 2.3.3 *Animation from Interactions*** — niveau
    **AAA** (les animations déclenchées par interaction doivent pouvoir être
    désactivées). `[documenté]` — W3C.
- Justification : pour les personnes ayant des troubles vestibulaires ou une
  sensibilité au mouvement, les animations peuvent provoquer nausées/vertiges.
  `[documenté]` (compréhension du critère W3C).

### Inclusive design (cadre général)

- **Microsoft Inclusive Design** et des organisations comme **Perkins School for
  the Blind** publient des principes d'inclusive design / d'accessibilité TV et
  écran. `[source secondaire]` — cités ici comme **cadres de référence
  généraux** ; les pages exactes n'ont pas été récupérées mot pour mot pour ce
  document, donc on n'attribue aucun chiffre précis à ces sources.

### Conséquence pour TV King

Trois profils → variations de `ui-scale`, de taille de cible et de densité
d'information. Profil **Senior** : `ui-scale` majoré, mode haut contraste (§5),
animations réduites par défaut, narration activable. Profil **Enfant** : cibles
larges, libellés simples, autoplay encadré.

---

## 9. Comment ce document guide l'implémentation

Traduction des constats en **tokens de design** concrets pour TV King :

### Surfaces (dark theme — §4)
- `--surface-0: #121212` (fond principal). `[documenté]`
- `--surface-1: #1a1a1c` (élévation faible, cartes).
- `--surface-2: #222226` (élévation moyenne, menus/modals).
  *(les niveaux 1–2 sont des dérivés cohérents avec le principe « plus on
  s'élève, plus la surface s'éclaircit » de Material — `[pattern observé]`.)*

### Texte (§4)
- `--text-high: rgba(255,255,255,0.87)` (blanc cassé, jamais #FFF plein).
- `--text-medium: rgba(255,255,255,0.60)`.
- `--text-disabled: rgba(255,255,255,0.38)`.
  `[documenté]`

### Accents chauds (§7)
- `--accent-gold`: or **désaturé** (ambre/champagne) plutôt qu'un jaune-or
  saturé, pour éviter la vibration sur fond sombre. `[documenté]` (désaturation)
  + `[source secondaire]` (choix du ton chaud).
- Vérifier que `--accent-gold` sur `--surface-0` atteint au moins **3:1** pour
  les composants UI, **4.5:1** dès qu'il porte du texte (§5). `[documenté]`

### Safe-area (§1)
- `--safe-x-android: 48` / `--safe-y-android: 27` (unités canvas). `[documenté]`
- `--safe-x-tvos: 90` / `--safe-y-tvos: 60`. `[documenté]`

### Échelle & accessibilité (§3, §8)
- `--ui-scale`: dérivé de la résolution réelle (canvas logique 1920×1080).
- `--ui-scale` majoré pour le profil **Senior** ; cibles `≥ 48` px.
- Mode **haut contraste** visant **7:1** (AAA texte normal). `[documenté]`
- Respect de `prefers-reduced-motion` / animations désactivables (WCAG 2.3.3).
  `[documenté]`

### Confort soir (§7)
- `--evening-warmth`: réchauffe le point de blanc (~5000 K cible indicative).
  `[source secondaire]` — présenté comme confort, **sans** promesse médicale
  (nuance AAO).

---

## 10. Références

Sources consultées et vérifiées via recherche web pour ce document
(juin 2026). Les pages marquées (403/coquille) n'ont pas pu être lues
intégralement par l'outil ; le principe est alors corroboré par des sources
convergentes et le niveau de confiance ajusté en conséquence.

- **Android Developers — Build TV layouts** (safe-area 48dp/27dp, overscan,
  Leanback) : <https://developer.android.com/training/tv/start/layouts>
- **Android Developers — TV navigation** (focus « nearest in direction », focus
  toujours présent) : <https://developer.android.com/training/tv/get-started/navigation>
- **Android Developers — Focus system (TV)** :
  <https://developer.android.com/design/ui/tv/guides/styles/focus-system>
- **Apple — Human Interface Guidelines, Layout** (insets ~90/60 pt sur grille
  1920×1080) : <https://developer.apple.com/design/human-interface-guidelines/layout>
  *(page récupérée vide par l'outil ; valeurs corroborées par synthèses HIG)*
- **Material Design — Dark theme** (#121212, opacités 87/60/38 %, désaturation,
  pas de noir/blanc purs) : <https://m2.material.io/design/color/dark-theme.html>
  *(403 sur la page canonique ; contenu corroboré par sources convergentes)*
- **W3C — WCAG 2.2** (contraste 4.5:1 / 3:1 / 7:1 ; 2.3.3 Animation from
  Interactions, AAA) : <https://www.w3.org/TR/WCAG22/>
- **W3C WAI — Understanding 2.3.3 Animation from Interactions** :
  <https://www.w3.org/WAI/WCAG21/Understanding/animation-from-interactions.html>
- **Kaur K., Gurnani B., Nayak S. et al. — Digital Eye Strain: A Comprehensive
  Review**, *Ophthalmology and Therapy*, 2022. DOI 10.1007/s40123-022-00540-9 ;
  PMID 35809192 : <https://link.springer.com/article/10.1007/s40123-022-00540-9>
- **American Academy of Ophthalmology — Digital Devices and Your Eyes** :
  <https://www.aao.org/eye-health/tips-prevention/digital-devices-your-eyes>
- **American Academy of Ophthalmology — Are Blue Light-Blocking Glasses Worth
  It?** : <https://www.aao.org/eye-health/tips-prevention/are-computer-glasses-worth-it>
- **Laws of UX — Hick's Law** (loi de Hick, Hick & Hyman 1952) :
  <https://lawsofux.com/hicks-law/>
- **Nielsen Norman Group — Hick's Law / long menus** :
  <https://www.nngroup.com/videos/hicks-law-long-menus/>

> **Limites assumées** : certaines valeurs « confort » (contraste perçu
> ~60–70 %, point de blanc ~5000 K, seuil de 5–7 choix) sont des **orientations**
> de conception, pas des seuils normatifs ; elles sont marquées `[source
> secondaire]` ou heuristique. Aucune citation, URL, DOI ou chiffre n'a été
> inventé : le doute a systématiquement conduit à abaisser le niveau de
> confiance plutôt qu'à affirmer.
