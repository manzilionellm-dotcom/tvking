# TV King — Lecteur IPTV Premium

App Flutter pour mobile, Android TV et Fire TV. Style **Apple TV / Netflix** :
logos haute qualité, classification automatique des chaînes (Sports, Films,
Séries, Kids, Info...), grille / liste pour 20 000+ chaînes, lecteur basé sur
**libmpv** (HD / 4K / 8K, multi-pistes audio + sous-titres).

---

## 🚀 Installer sans rien compiler (recommandé)

Chaque push sur la branche déclenche un build APK automatique via
**GitHub Actions**. Pour récupérer le dernier APK :

1. Va sur https://github.com/manzilionellm-dotcom/tvking/actions
2. Clique sur le **dernier run** "Build Android APK" (en haut de la liste)
3. Descends en bas → section **Artifacts** → télécharge **`tvking-debug-apk-XXX`**
4. Décompresse le `.zip` → tu obtiens `app-debug.apk`
5. Transfère sur ton téléphone (USB ou Drive) et installe
6. Pour Fire TV : héberge l'APK quelque part (Drive partagé, etc.) et
   utilise **Downloader** pour le récupérer

✅ Pas besoin de Flutter, Android Studio, Java, ou quoi que ce soit
   localement. Le build se fait dans le cloud à chaque commit.

---

## 🛠 Compiler en local (si tu veux développer)

### Pré-requis

| Outil | Pourquoi |
|---|---|
| **Flutter SDK 3.24+** | Framework — https://docs.flutter.dev/get-started/install |
| **Android Studio** | Émulateurs + SDK Android + ADB |
| **JDK 17** | Microsoft OpenJDK 17 recommandé |
| **Git** | Récupération du code |

⚠️ **Windows + antivirus** : Surfshark / Defender peuvent supprimer
`dart.exe` et `adb.exe`. Ajouter exclusions sur les dossiers :
- `C:\src\flutter`
- `C:\Users\<toi>\AppData\Local\Android`
- `C:\Users\<toi>\.gradle`

### Démarrage

```bash
git clone https://github.com/manzilionellm-dotcom/tvking.git
cd tvking
flutter create . --platforms=android
flutter pub get
flutter run
```

---

## 📂 Structure du projet

```
lib/
├── main.dart                          # Entrée + onboarding
├── core/
│   ├── theme/                         # Palette + typo + theme global
│   └── widgets/                       # Widgets génériques (glass, live badge)
└── features/
    ├── channels/                      # Browsing
    │   ├── domain/                    # Channel, ChannelGenre, Classifier
    │   ├── data/                      # Recently watched repo
    │   └── presentation/              # Home, sections, grilles, recherche
    │       └── widgets/               # ChannelLogo, Cards, Rows
    ├── playlists/                     # Sources IPTV
    │   ├── domain/                    # Playlist model
    │   ├── data/                      # M3U parser, Xtream client, SQLite
    │   └── presentation/              # Add/manage playlists
    ├── player/                        # Lecture vidéo
    │   ├── data/                      # PlayerSettings
    │   └── presentation/              # VideoPlayerScreen + tracks/settings sheets
    ├── settings/                      # Hub réglages
    ├── about/                         # À propos + update checker
    └── onboarding/                    # Premier lancement
```

---

## ✅ Feuille de route

- [x] **Phase 1.0** — Squelette + écran d'accueil + design VIP
- [x] **Phase 1.1** — Parser M3U complet
- [x] **Phase 1.2** — Client Xtream Codes + SQLite
- [x] **Phase 1.3** — Lecteur vidéo libmpv (HD/4K/8K)
- [x] **Phase 1.4** — Refonte UI Apple TV (logos, classification, 20k+ chaînes)
- [x] **Phase 1.5** — Onboarding, Settings, About, Update checker, Zapping
- [ ] **Phase 2** — EPG XMLTV + grille TV
- [ ] **Phase 3** — Catch-up + téléchargements + enregistrement
- [ ] **Phase 4** — Chromecast / AirPlay / DLNA
- [ ] **Phase 5** — Firebase Auth + système Premium + panneau admin web

---

## 📜 Légal

TV King est un **lecteur média générique** comme VLC. Aucune playlist
n'est incluse. Aucun lien vers du contenu protégé. L'utilisateur est
responsable des sources qu'il ajoute et de leur conformité aux lois
en vigueur dans son pays.
