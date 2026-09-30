# Conventions de code — 7 MOTION

<!-- Codename interne / dépôt : `tv_king`. -->


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

## Fonctions en plus (branche `claude/zuno-tout`)

Chacune a un interrupteur (`BoxFlag`, SharedPreferences). Coupée, elle ne démarre pas. Aucune n'ouvre un flux toute seule.

- **Téléphone (QR).** Vient de `claude/zuno-telecommande`, sans changement de son modèle : jeton de 20 minutes, un seul téléphone, réseau local uniquement. Réglages → Télécommande.
- **Voix et « ce soir ».** Viennent de `claude/zuno-voix` (paquet local `zuno_voice`, micro du système). L'aide vocale distante reste désactivée par défaut (`VoiceRemoteAssist`, clé `zuno.voice.remote_ai.v1`). Aucune clé d'API dans le code : si on l'allume, l'appel passe par le service déjà en place. « Ce soir » ne lit que le guide de la box.
- **Profils.** Viennent de `claude/zuno-profils` (pas une fonction recodée ici). Un seul profil : l'accueil s'ouvre comme avant, sans écran de choix. Favoris, historique, reprise, rappels et code parental sont le tiroir du profil en cours. Le profil 1 garde les clés d'avant.
- **En retard.** Uniquement les heures du guide déjà sur la box. Le retour au début n'existe que si la chaîne déclare un catch-up. Sinon on affiche le texte et le direct ne bouge pas. Interrupteur `zuno.flag.missed_show`. Pas de nouvelle dépendance.
- **À cette heure.** Compteurs locaux (semaine / week-end × matin, après-midi, soir, nuit), un carnet par profil (`zuno.time_picks.v1.<id>`). Un créneau vide n'affiche rien : pas de repli sur tout l'historique. La rangée ne lance rien toute seule. Interrupteur `zuno.flag.time_picks`. Pas de nouvelle dépendance. L'historique des chaînes n'est pas modifié.
- **Sous-titres.** Uniquement les pistes déjà dans le flux, dans la langue de l'application (`fre` / `fra` = français). Une piste sans langue n'est pas prise pour la tienne. On ne passe pas `preferredText` au `setUrl` du direct : `selectTrack` ou couper, et une erreur ne rouvre pas la chaîne. Le choix « off » du cinéma est respecté. Interrupteur `zuno.flag.subtitles`. Pas de nouvelle dépendance, pas de traduction.
