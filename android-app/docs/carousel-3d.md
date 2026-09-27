# Carrousel 3D Zuno — structure et réglages

> État : **étapes 1 à 4 faites**. L'anneau est branché sur les **Réglages** (v94). Le composant n'est branché à aucun
> écran existant : le design actuel de Zuno n'est pas modifié.

## Pourquoi Flutter et pas React

Le cahier des charges demandait React + TypeScript + CSS 3D. Zuno (Android TV,
mobile, Windows) est une app **Flutter** : du code React ne peut pas y tourner
sans WebView, ce qui pénaliserait les 60 fps sur les box TV. Le cahier des
charges est donc traduit 1:1 en Flutter :

| Web (cahier des charges)            | Zuno (Flutter)                                   |
|-------------------------------------|--------------------------------------------------|
| `perspective`                       | `Matrix4.setEntry(3, 2, 1 / perspectivePx)`      |
| `rotateY` + `translateZ`            | `Matrix4.rotateY` + `Matrix4.translate(0,0,-r)`  |
| `will-change: transform`            | `Transform` + `RepaintBoundary` (couche GPU)     |
| hook `useCarousel`                  | `ZunoCarouselController` (ChangeNotifier)        |
| hook `useSound` + Web Audio API     | `CarouselSound` (sons synthétisés, sans fichier) |
| flèches / molette / swipe           | D-pad télécommande, clavier, molette, glisser    |

## Fichiers

```
lib/features/carousel/
├── domain/
│   ├── carousel_config.dart     # TOUS les réglages (angle, profondeur, vitesse…)
│   └── carousel_item.dart       # une affiche + les 6 catégories
├── data/
│   └── carousel_mock_data.dart  # 12 affiches de démo (étape 6)
└── presentation/
    ├── zuno_ring_carousel.dart  # LE composant principal (unique widget public)
    ├── carousel_poster_card.dart# rendu d'une affiche (réelle ou générée)
    ├── carousel_controller.dart # ≈ useCarousel : index, position, boucle, snap
    └── carousel_sound.dart      # ≈ useSound : tick + sélection
test/features/carousel/
├── carousel_controller_test.dart
└── zuno_ring_carousel_test.dart
```

## Où il est utilisé

- **Réglages (v94)** : 8 cartes (Mon appareil, Mes sources, Mes
  enregistrements, Contrôle parental, Mise à jour, Langue, Boîte noire,
  Mentions légales). ◀ ▶ fait tourner l'anneau, OK ouvre la rubrique. Le
  titre et la description de la carte au centre s'affichent sous l'anneau.
- API : `ZunoRingCarousel(items: …)` pour des affiches,
  `ZunoRingCarousel.builder(itemCount, cardBuilder, …)` pour des cartes
  libres.

## Feuille de route

1. ✅ Squelette + structure des fichiers
2. ✅ Anneau 3D (transforms)
3. ✅ Navigation clavier / télécommande / tactile + snap
4. ✅ Zoom intelligent + respiration au repos
5. ⏳ Sons synthétisés (tick + sélection)
6. ⏳ Données de démo + rendu final
7. ⏳ Ce README complété avec les captures et les réglages validés

## Charte « apaiser la vision »

- **Un seul accent** : l'or champagne de Zuno (filet de 28 × 2 px au-dessus du
  titre). Tout le reste est en neutres chauds.
- **Grille de 4 px** : marges intérieures de 20 px, espacements de 12 et 8 px.
- **Titre** : Oswald en capitales, interlettrage +0,6, interligne 1,12,
  3 lignes au maximum, coupure propre par « … ».
- **Année** : Inter en chiffres tabulaires, donc de largeur fixe. Les années
  ne « dansent » pas d'une carte à l'autre.
- **Voisines** : voile de la couleur du fond plutôt qu'une vraie transparence.
  Le rendu à l'œil est le même, sans passe GPU supplémentaire.
- **Profondeur** : ombre portée uniquement sur la carte centrale, et une ombre
  elliptique au « sol » sous l'anneau.
- **Bord** : un filet blanc à 5 % détache la carte du fond sans cadre visible.

## Réglages (`CarouselConfig`)

| Réglage              | Défaut   | Effet                                                   |
|----------------------|----------|---------------------------------------------------------|
| `cardAngleDeg`       | 20°      | Angle entre deux cartes ; (visibleSide+1) × angle < 90° |
| `ringRadius`         | 640 px   | Profondeur de l'anneau (`translateZ`)                   |
| `perspectivePx`      | 1400 px  | Distance caméra ; + petit = 3D plus marquée             |
| `cardWidth`          | 220 px   | Largeur de la carte centrale (hauteur = largeur × 3/2)  |
| `visibleSide`        | 3        | Cartes dessinées de chaque côté (économie GPU)          |
| `sideScaleStep`      | 0.06     | Réduction de taille par carte d'écart                   |
| `sideOpacityStep`    | 0.22     | Estompage par carte d'écart (plancher `sideMinOpacity` 0.25) |
| `selectedScale`      | 1.06     | Zoom de la carte sélectionnée (règle premium Zuno)      |
| `glowBlur` / `glowOpacity` | 32 / 0.35 | Halo autour de la carte sélectionnée             |
| `snapDuration`       | 380 ms   | Vitesse de l'aimantation                                |
| `wheelStepThreshold` | 60 px    | Molette : défilement pour avancer d'une carte           |
| `swipeCardWidthRatio`| 0.35     | Glisser : fraction de carte pour changer                |
| `swipeFlingVelocity` | 700 px/s | Glisser rapide : saut                                   |
| `idleDelay`          | 4 s      | Inactivité avant la respiration                         |
| `idlePeriod`         | 6 s      | Durée d'une respiration                                 |
| `idleAmplitudeDeg`   | 1.4°     | Balancement de l'anneau au repos                        |
| `tickFrequencyHz`    | 1850 Hz  | Hauteur du tick (durée `tickDuration` 22 ms)            |
| `selectFrequenciesHz`| 660→990  | Accord de sélection (durée 140 ms)                      |
| `volume`             | 0.18     | Volume global des sons                                  |

Ces valeurs sont un point de départ. Elles seront ajustées sur une vraie TV à
l'étape 7.
