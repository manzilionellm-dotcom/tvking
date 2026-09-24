# Publier The Few sur l'App Store (iOS)

> ✅ **État** : l'app **compile déjà pour iOS** (workflow `build-ios.yml`, dernier
> run vert). Le code est iOS-safe (les canaux natifs Android — Cast, PiP,
> device-id — dégradent proprement). Reste le travail **côté Apple** (compte +
> Mac + signature), qui ne peut pas se faire depuis le CI Linux.
>
> 🔴 **Privé (18+) est interdit sur l'App Store** → iOS = **The Few** uniquement.

## 1. Coût & pré-requis
- **Apple Developer Program : 99 $/an** (récurrent).
- **Un Mac avec Xcode** (ou un Mac cloud : Codemagic, Bitrise, MacStadium).
- Identité (compte individuel) ou **D-U-N-S** (compte société).

## 2. Ce qui est déjà géré par le CI `build-ios.yml`
- Génération du dossier `ios/` (le projet est Android-first).
- Libs **media_kit iOS** (le lecteur mobile marche sur iPhone).
- **Info.plist** : `NSAllowsArbitraryLoads` (flux IPTV en http://) + `NSBonjourServices`
  / `NSLocalNetworkUsageDescription` (réseau local).
- **Podfile** : cible **iOS 13** (requise par media_kit).
- Build `--no-codesign` = vérification de compilation (vert ✅).

## 3. Procédure sur Mac (pour un .ipa publiable)
1. **S'inscrire** au Apple Developer Program (99 $/an), attendre la validation.
2. Sur le Mac : `git clone` le repo, `flutter pub get`, puis ouvrir
   `ios/Runner.xcworkspace` dans Xcode (le dossier `ios/` est généré par
   `flutter create --platforms=ios .` si absent — cf. le workflow).
3. Dans Xcode → cible **Runner** → onglet *Signing & Capabilities* :
   - **Team** : ton compte Apple.
   - **Bundle Identifier** : ex. `com.manzilionellm.thefew` (doit être unique,
     distinct de l'app Privé).
   - Laisser *Automatically manage signing*.
4. **App Store Connect** (appstoreconnect.apple.com) → *Mes apps* → **＋** →
   créer l'app (même Bundle ID), plateforme iOS.
5. **Archiver & envoyer** : dans Xcode, *Product → Archive* → *Distribute App →
   App Store Connect → Upload*. (ou `flutter build ipa` puis Transporter.)
6. **TestFlight** : teste l'IPA, puis **Soumets pour examen**.

## 4. Fiche App Store (anti-rejet)
- Reprends la fiche neutre du Play Store (cf. `docs/play-store-publication.md`) :
  « lecteur multimédia, tu apportes ta source, aucun contenu fourni ».
- **Accès de revue** : même playlist M3U de démo légale :
  `https://raw.githubusercontent.com/manzilionellm-dotcom/tvking/<branche>/demo/demo-playlist.m3u`
- **INTERDIT** : « gratuit », noms/logos de chaînes, promesses de contenu.
- Apple est **plus strict** que Google sur l'IPTV → insiste sur le caractère
  **lecteur générique** ; fournis des identifiants de démo qui marchent.

## 5. ⚠️ Limite iOS importante (à NE PAS sur-vendre)
- Le **Cast (Chromecast)** et le **PiP** sont **natifs Android uniquement**.
  Sur iPhone, ces boutons **ne font rien** (dégradation propre, pas de crash).
- Donc, pour la **fiche iOS, n'annonce PAS le Cast/Chromecast** (pub mensongère
  = rejet). Mets en avant : lecture HLS/TS/HEVC, EPG, favoris, enregistrement,
  mode audio, reprise, Top 10.
- *Évolution possible plus tard* : implémenter **AirPlay** (équivalent Cast
  natif iOS) et/ou le **SDK Google Cast iOS** pour réactiver la diffusion.

## 6. Différences clés avec Android (récap)
| | Android | iOS |
|---|---|---|
| Coût | 25 $ une fois | **99 $/an** |
| Machine | n'importe laquelle | **Mac obligatoire** |
| Sideload de secours | oui | **non** (App Store only) |
| Cast/PiP | ✅ natif | ❌ pas encore (à implémenter) |
| Privé (18+) | sideload | ❌ interdit |
