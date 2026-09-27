# Carrousel 3D Zuno — structure et réglages

> État : **étape 1 / 7 (squelette)**. Le composant n'est branché à aucun
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
    ├── carousel_controller.dart # ≈ useCarousel : index, position, boucle, snap
    └── carousel_sound.dart      # ≈ useSound : tick + sélection
test/features/carousel/
└── carousel_controller_test.dart
```

## Feuille de route

1. ✅ Squelette + structure des fichiers
2. ⏳ Anneau 3D (transforms)
3. ⏳ Navigation clavier / télécommande / tactile + snap
4. ⏳ Zoom intelligent + respiration au repos
5. ⏳ Sons synthétisés (tick + sélection)
6. ⏳ Données de démo + rendu final
7. ⏳ Ce README complété avec les captures et les réglages validés

## Réglages (`CarouselConfig`)

| Réglage              | Défaut   | Effet                                                   |
|----------------------|----------|---------------------------------------------------------|
| `cardAngleDeg`       | 24°      | Angle entre deux cartes ; + grand = anneau plus ouvert  |
| `ringRadius`         | 560 px   | Profondeur de l'anneau (`translateZ`)                   |
| `perspectivePx`      | 1100 px  | Distance caméra ; + petit = 3D plus marquée             |
| `cardWidth`          | 220 px   | Largeur de la carte centrale (hauteur = largeur × 3/2)  |
| `visibleSide`        | 4        | Cartes dessinées de chaque côté (économie GPU)          |
| `sideScaleStep`      | 0.09     | Réduction de taille par carte d'écart                   |
| `sideOpacityStep`    | 0.20     | Estompage par carte d'écart (plancher `sideMinOpacity`) |
| `selectedScale`      | 1.10     | Zoom de la carte sélectionnée                           |
| `glowBlur` / `glowOpacity` | 36 / 0.55 | Halo autour de la carte sélectionnée             |
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
