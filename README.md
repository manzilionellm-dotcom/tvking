# TV King — Lecteur IPTV Premium

App Flutter pour mobile, Android TV et Fire TV. Phase 1 en cours :
écran d'accueil avec design "VIP" et liste de chaînes fictives.

## Pré-requis (à installer sur ta machine)

| Outil | Pourquoi | Comment |
|---|---|---|
| **Flutter SDK 3.24+** | Le framework lui-même | https://docs.flutter.dev/get-started/install |
| **Android Studio** | Émulateurs Android + SDK Android + ADB | https://developer.android.com/studio |
| **VS Code** *(recommandé)* | Éditeur léger avec excellent support Dart/Flutter | https://code.visualstudio.com/ |
| Extension **Flutter** dans VS Code | Hot reload, autocomplete, debug | Cherche "Flutter" dans l'onglet Extensions |
| **Git** | Versionner ton code | https://git-scm.com/ |

Une fois Flutter installé, vérifie que tout va bien :

```bash
flutter doctor
```

Tout doit être au vert. S'il manque la licence Android, lance :

```bash
flutter doctor --android-licenses
```

## Première utilisation

```bash
# 1. Clone le repo
git clone https://github.com/manzilionellm-dotcom/tvking.git
cd tvking

# 2. Génère les dossiers natifs (android/, ios/, ...)
#    qui ne sont PAS versionnés dans ce repo. Ils sont
#    reconstruits à partir de pubspec.yaml + lib/.
flutter create . --platforms=android

# 3. Récupère les dépendances déclarées dans pubspec.yaml
flutter pub get

# 4. Branche un téléphone Android en USB (mode développeur activé)
#    ou démarre un émulateur depuis Android Studio. Puis :
flutter run
```

L'écran d'accueil "TV King" doit s'afficher avec 4 chaînes fictives.

## Structure du projet

```
lib/
├── main.dart                          # Point d'entrée
├── core/                              # Briques transverses (thème, widgets génériques)
│   ├── theme/
│   │   ├── app_colors.dart            # Palette VIP officielle
│   │   ├── app_text_styles.dart       # Typographie Inter
│   │   └── app_theme.dart             # ThemeData global
│   └── widgets/
│       ├── glass_card.dart            # Effet glassmorphism réutilisable
│       └── live_badge.dart            # Badge "EN DIRECT" animé
└── features/                          # Une fonctionnalité = un dossier
    └── channels/
        ├── domain/channel.dart        # Modèle "Chaîne TV"
        ├── data/fake_channels.dart    # Données fictives (Phase 1)
        └── presentation/
            ├── home_screen.dart       # L'écran d'accueil
            └── widgets/channel_card.dart  # Vignette d'une chaîne
```

## Feuille de route

- [x] **Phase 1.0** — Squelette + écran d'accueil avec données fictives
- [ ] **Phase 1.1** — Parser M3U / M3U8
- [ ] **Phase 1.2** — Support Xtream Codes API
- [ ] **Phase 1.3** — Lecteur vidéo (`media_kit`) HLS / TS / MP4
- [ ] **Phase 1.4** — Recherche, favoris, dernières chaînes
- [ ] **Phase 2** — EPG XMLTV + grille TV
- [ ] **Phase 3** — Catch-up, téléchargements, enregistrement
- [ ] **Phase 4** — Chromecast / AirPlay / DLNA
- [ ] **Phase 5** — Firebase Auth + système Premium + panneau admin web

## Légal

Lecteur média générique. Aucune playlist pré-remplie. Aucun lien vers
du contenu protégé. L'utilisateur est responsable des sources qu'il ajoute.
