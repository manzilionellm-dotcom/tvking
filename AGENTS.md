# Conventions de code — TV King

Projet **Flutter** (Dart). Cible : Android mobile + Android TV / Fire TV + Google TV.
À terme : iOS / iPadOS / Apple TV / Web (panneau admin).

## Règles non négociables

1. **Pédagogie d'abord.** Commentaires en français, abondants, explicatifs.
   Le projet sert aussi de support d'apprentissage à son auteur.
2. **Aucune playlist pré-remplie**, aucune URL de flux IPTV en dur dans
   le code de production. Les fichiers `fake_*` peuvent contenir des
   placeholders à des fins de dev uniquement.
3. **Pas de magie noire.** Toute dépendance ajoutée à `pubspec.yaml`
   doit être documentée (que fait-elle, pourquoi on la choisit).
4. **Pas de `print()`** — utiliser `debugPrint()` ou un logger.
5. **Couleurs et tailles** : uniquement via `AppColors` / `AppTextStyles`.
   Jamais de `Color(0xFF…)` ni de `fontSize:` magique en dur dans l'UI.

## Architecture

```
lib/
├── core/        # transverse (thème, widgets génériques, utils)
├── features/    # une fonctionnalité = un dossier
│   └── <feature>/
│       ├── domain/         # modèles purs (pas de Flutter)
│       ├── data/           # sources (M3U parser, Xtream client, SQLite...)
│       └── presentation/   # widgets + écrans + (plus tard) providers Riverpod
└── shared/      # ce qui est partagé entre features (peu)
```

## Workflow git

- Une branche par fonctionnalité (`claude/<sujet>` ou `feature/<sujet>`).
- Commits fréquents, messages clairs.
- On commit dès qu'une étape compile et tourne.
