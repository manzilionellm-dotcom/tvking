# Template TiviMate — spécification de reproduction (Android TV, D-pad)

Source : 6 captures officielles tivimate.com (1920×1080) + descriptions. HEX =
correspondances visuelles (composites marketing avec halos) à calibrer in-app,
pas des tokens pixel-certifiés. « NON VISIBLE » = non révélé par la source.

But : reproduire l'expérience TiviMate comme **template d'accueil SEVEN**, en
réutilisant la donnée existante (`PlaylistRepository`, `EpgRepository`,
`mini_epg_now_next`, `Channel`, `TvPlayerScreen`). Couleurs identiques, seul le
logo change.

## 1. Design tokens

| Rôle | HEX approx. |
|------|-------------|
| Fond app / vidéo | `#000000` |
| Surface panneau (sidebar/dialog) | `#12171C`–`#16191F` |
| Surface rail d'icônes | `#0C0F12` |
| Carte / item repos | `#1E2126`–`#232329` |
| Cellule EPG passée | `#20242B` (~55 % opacité) |
| Cellule EPG à venir | `#2A2E35` |
| ACCENT (bleu marque) | `#0A84FF` (≈ `#1E90FF`) |
| Focus liste (pill) | `#FFFFFF` plein, texte noir |
| Sélection douce (groupe non-focus) | `#3A3E45` |
| Texte principal | `#FFFFFF` |
| Texte secondaire | `#B8BDC4`–`#9AA0A8` |
| Texte tertiaire / dimmé | `#6B7178` |
| Badge HD/STEREO fond | `#3A3E45` (~50 %) ; texte `#E6E8EB` MAJ |
| Barre progression remplie | ACCENT `#0A84FF` ; piste `#4A4E55` |

Accent color (réglage) = Material 500 : Pink `#E91E63` · Purple `#9C27B0` ·
Indigo `#3F51B5` · **Blue `#2196F3` (défaut)** · Cyan `#00BCD4` · Teal `#009688`
· Green `#4CAF50` · Lime `#CDDC39` · Yellow `#FFEB3B` · Amber `#FFC107`.

Rayons : cartes/logos ~8–10 ; boutons ~10 ; **pills focus ~28** (capsule) ;
badges ~4 ; dialog ~14–16.

Typo (relatif, Roboto/système) : titre programme 1.6× SemiBold ; horaire 1.0× ;
durée 0.95× ; nom chaîne 1.05× Medium ; n° chaîne 1.05× ; badge 0.7× MAJ.

Focus : **pas d'anneau**. (A) pill blanc plein (texte noir) pour l'item de liste
sélectionné ; (B) fond accent bleu pour l'onglet actif ; (C) n°+nom en bleu +
chevron ► pour la chaîne active dans la grille.

Barre progression : 3–4 px ; remplissage bleu, piste grise translucide ; poignée
blanche ~14 px seulement sur la seek bar de lecture.

## 2. Écran LECTURE + BARRE CHAÎNE (cœur)

Vidéo plein écran ; OK → overlay bas (tiers inférieur, dégradé noir 0→85 %).
- Marges latérales ~5 %.
- **Barre d'info** (~90–100 px) : `[logo 110×80] [Titre] / [horaire début—fin]
  [mini-barre ~90px] [durée « 35 min »] [Nom+n° chaîne] [HD][STEREO]`.
- **Seek bar** pleine largeur, 3–4 px, poignée blanche.
- **Bandeau chaînes** (~150–170 px) : cartes ~150×120, espacement ~12–16 ;
  2 premières = actions « TV guide » (▦) et « History » (↻) icône+label ;
  suivantes = logo centré + mini-barre bleue en pied (pas de n°/nom ici).
  Item focus `#2E3238`. Chevron ⌄ centré dessous = ouvrir liste complète.

D-pad : OK = overlay ; HAUT = liste/guide ; BAS = plus de contenu/masque ;
GAUCHE/DROITE = zapping ; RETOUR = ferme puis quitte plein écran.
Auto-masquage overlay ~5 s (à confirmer).

## 3. Écran LISTE CHAÎNES (panneau latéral) + grille

Colonnes : **rail icônes ~4 %** (Search ⌕, TV ▭ actif, Movies ▤, Recordings ▣,
My list ▯) · **playlists/groupes ~20–24 %** (dépliables ⌄/⌃, groupes indentés
16 px) · **contenu ~72–74 %** (aperçu vidéo live + détail + grille).
- Ligne chaîne ~48–52 px, ~10–12 visibles.
- Anatomie ligne : `[n°] [logo 64×48 arrondi] [nom] [► si active]` ; en overlay
  compact : + programme en cours + mini-barre + heure.
- États : repos transparent/texte blanc/n° gris ; **active = n°+nom bleu + ►**
  fond éclairci ; **groupe focus = pill blanc/texte noir**.
- D-pad : HAUT/BAS chaîne↕ ou groupe↕ ; GAUCHE liste→groupes→rail ; DROITE entre
  grille/valide ; OK lit ; RETOUR ferme. Focus initial = chaîne en cours.

## 4. Écran GUIDE EPG (grille)

- Colonne chaînes gauche ~28–30 % (`n° + logo + nom`) ; timeline droite ~70 %,
  ~30 min/segment. En-tête heures ; date+heure courante en **bleu** à gauche.
- **Ligne NOW** : trait vertical fin (~1 px, blanc translucide) à l'heure courante.
- Cellule = bloc arrondi 6–8 px, largeur ∝ durée, fond `#2A2E35` ; **passé
  assombri** `#20242B` ~55 % ; courant sur chaîne focus = pill clair ; titre « … ».
- Ligne active = n°/nom bleu + ► ; cellule focus = surbrillance claire.
- D-pad : HAUT/BAS chaîne ; GAUCHE/DROITE temps ; OK détail/lit/catch-up ;
  colonne chaînes **sticky** pendant le scroll temporel.

## 5. Détail programme / catch-up

3 colonnes : liste programmes ~50 % (`heure titre`, séparateurs de jour en bleu)
· dates ~12 % (`Jour N°`, date active = pill blanc) · détail ~35 % (thumbnail
16:9 coins ~10, titre 1.4×, horaire gris). Ligne focus = pill blanc + ► catch-up.

## 6. Réglages (dialog « Accent color »)

Dialog droite ~30 %, fond `#15191F`, coins ~14. Rangée = `[pastille ronde 24]
[libellé]`, ~54 px ; sélection = pill blanc + coche ✓. Scrollable.
Menu principal : Search · TV · Movies · Recordings · My list.

## 7. Multiview (menu contextuel)

Grille de fenêtres ; menu pop-up `#16191F` coins ~14, item focus pill blanc :
Add screen · Search and add · Change channel · Play · Enlarge · Full screen ·
Remove screen (~58 px/item).

## Inconnues (ne pas inventer)

Délai auto-masquage exact ; états chargement/buffering/hors-ligne ; HAUT vs BAS
précis en lecture ; HEX pixel-exacts (calibrer) ; arbo complète Réglages /
Parental / Recording / Multiview setup ; boutons rappel/enregistrer ; liste
latérale compacte pendant lecture ; polices exactes ; courbes d'animation.

## Plan de reproduction SEVEN (réutilisation)

1. **Home TiviMate** = liste chaînes (rail + groupes + liste) + aperçu + EPG
   now/next → réutilise `PlaylistRepository` (chaînes), `mini_epg_now_next`,
   `TvPlayerScreen` (OK = lecture).
2. **Grille EPG** → s'appuyer sur `TvGuideGridScreen` (déjà proche) restylé
   TiviMate dans le template, sans toucher l'écran partagé.
3. Couleurs = tokens §1 ; logo = SEVEN.
