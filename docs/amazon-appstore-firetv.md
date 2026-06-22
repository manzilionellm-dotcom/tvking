# Publier « The Few TV » sur l'Amazon Appstore (Fire TV / Fire Stick)

But : permettre l'installation **directe depuis le Fire Stick** (recherche →
Installer), sans Downloader ni sideload — pour les utilisateurs peu technophiles.

> Rappel positionnement (bouclier juridique, déjà en place dans l'app) :
> **The Few TV est un LECTEUR. Il ne vend, ne fournit, n'héberge aucune chaîne
> ni lien M3U. Le contenu est apporté par l'utilisateur.** Pages en ligne :
> `https://app.7themotion.com/terms` et `https://app.7themotion.com/privacy`.

---

## Étape 0 — Compte développeur (à faire UNE fois)
1. Va sur **developer.amazon.com** → connecte-toi (compte Amazon) → crée un
   compte **Amazon Developer** (gratuit, pas de frais annuels).
2. Console → **Apps & Services → Add New App → Android**.

## Étape 1 — L'APK
- Source : **`https://app.7themotion.com/777`** (= release `tv-latest`, signée
  avec la clé fixe). Télécharge le fichier `DeFewTV.apk` sur ton PC.
- Exigences Amazon couvertes par le build actuel :
  - APK **64 bits** inclus (arm64-v8a) — l'APK release Flutter universel le contient.
  - Manifest Fire-ready (touchscreen/leanback non requis, bannière) — déjà patché.
- ⚠️ **Garde toujours la même clé de signature** pour les mises à jour
  (c'est déjà le cas : clé fixe CI) → MAJ par-dessus sans réinstaller.

## Étape 2 — Fiche produit (copier-coller)

**Nom de l'app :** `The Few TV`

**Titre court / sous-titre :** `Lecteur IPTV premium — ta propre playlist`

**Catégorie :** Entertainment → *Video Players & Editors* (Lecteurs vidéo)

**Description (FR) :**
```
The Few TV est un LECTEUR multimédia pour Android TV et Fire TV.

Ajoutez VOTRE propre liste de lecture (M3U) ou vos identifiants de portail
(Xtream) et profitez d'une interface premium pensée pour la télécommande :
grille de chaînes fluide, favoris, reprise des dernières chaînes regardées,
recommandations personnalisées, guide des programmes (EPG) et enregistrement
local.

IMPORTANT : The Few TV NE FOURNIT, NE VEND et N'HÉBERGE aucune chaîne, aucun
flux ni aucune liste de lecture. Aucun contenu n'est inclus dans l'application.
Le contenu est fourni par l'utilisateur, qui doit disposer des droits et
abonnements nécessaires auprès de son propre fournisseur. C'est un lecteur,
rien d'autre.

Fonctionnalités :
• Lecture fluide (moteur natif ExoPlayer/Media3), navigation 100 % télécommande
• Grille de chaînes premium, favoris, reprise « Continuer à regarder »
• Recommandations « Pour vous » basées sur vos habitudes (en local)
• EPG (guide des programmes) quand votre source le fournit
• Enregistrement local, contrôle parental (Mode Enfants + code PIN)

Conditions d'utilisation : https://app.7themotion.com/terms
Confidentialité : https://app.7themotion.com/privacy
```

**Mots-clés :** `lecteur, player, media player, m3u, xtream, iptv player, lecteur vidéo, playlist`

**URL Politique de confidentialité :** `https://app.7themotion.com/privacy`
**URL Conditions / EULA :** `https://app.7themotion.com/terms`

## Étape 3 — Visuels (tailles Amazon)
- **Icône** : 512 × 512 PNG.
- **Bannière / Key art Fire TV** : 1280 × 720 PNG (utilise
  `assets/branding/thefew_tv_banner*.png` comme base).
- **Captures d'écran Fire TV** : 1280 × 720 (3 minimum). Suggestion :
  1) l'écran « Ajoute ta propre liste » (montre qu'il n'y a AUCUN contenu inclus),
  2) la grille avec une playlist de démo (flux libres de droit),
  3) le lecteur plein écran.

## Étape 4 — Compatibilité appareils
- Coche **Amazon Fire TV** (tous les modèles compatibles) + télécommande.
- Laisse l'écran tactile **non requis**.

## Étape 5 — Classification du contenu
- Remplis le questionnaire honnêtement. Précise dans les notes :
  « Application = lecteur multimédia. Le contenu est fourni par l'utilisateur via
  sa propre source (M3U/Xtream). Aucune chaîne n'est incluse ou fournie par
  l'app. »

## Étape 6 — Notes au testeur (CRUCIAL pour passer la revue)
- À l'installation, sur un appareil neuf, l'app ouvre sur **« Aucune chaîne —
  ajoute ta propre liste »** : le testeur ne voit **aucun contenu préchargé**.
- Fournis-lui une **playlist M3U de démonstration libre de droit** (flux gratuits
  / FAST publics) dans le champ « instructions de test », pour qu'il vérifie que
  la lecture fonctionne — SANS pousser une vraie source IPTV sur l'appareil de test.
- **Ne jamais** activer/pousser une source commerciale sur une MAC utilisée pour
  la revue Amazon.

## Après publication
Les utilisateurs cherchent **« The Few TV »** dans la recherche du Fire Stick
(ou l'Appstore Fire TV) → **Obtenir / Installer** — sans Downloader.

## Notes
- Le **sideload** (Downloader → `app.7themotion.com/777`) reste valable en
  parallèle pour ceux qui préfèrent.
- Délai de revue Amazon : généralement quelques jours.
- Les mises à jour : ré-upload de l'APK (même clé) ; l'Appstore propose la MAJ
  automatiquement aux installés.
