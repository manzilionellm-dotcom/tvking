# Publication sur les stores — 7 MOTION

> Objectif : publier l'app mobile sur **Google Play**, **Aptoide** et
> **Huawei AppGallery**. L'app est positionnée comme un **lecteur multimédia
> générique « apporte ta propre source »** (aucune chaîne/contenu fourni) —
> c'est CE positionnement qui maximise les chances de passer la review.

---

## 0. Artefacts prêts (produits par le CI)

| Store | Fichier à uploader | Où le récupérer |
|-------|--------------------|-----------------|
| **Google Play** | `7motion.aab` (App Bundle signé) | Actions → dernier build → Artifacts → `7motion-playstore-aab-…` |
| **Aptoide** | `7motion.apk` | https://github.com/manzilionellm-dotcom/tvking/releases/download/latest/7motion.apk |
| **Huawei AppGallery** | `7motion.apk` (ou `.aab`) | idem APK ci-dessus |

**Politique de confidentialité (URL à coller dans les 3) :**
`https://seven-motion-backend.manzilionel-lm.workers.dev/privacy`

---

## 1. Fiche store (textes à coller)

**Nom de l'app**
```
7 MOTION — Lecteur M3U
```

**Description courte (≤ 80 caractères)**
```
Lecteur multimédia pour TES playlists M3U / Xtream. Aucun contenu fourni.
```

**Description complète**
```
7 MOTION est un lecteur multimédia simple et rapide pour lire VOS propres
playlists.

• Ajoutez votre source : lien M3U ou identifiants Xtream Codes que VOUS
  fournissez.
• Navigation claire par catégories.
• Lecteur fluide (media_kit), plein écran, Picture-in-Picture.
• Diffusion vers votre TV (DLNA / Chromecast) sur votre réseau.
• Favoris, reprise de lecture, recherche.

IMPORTANT : 7 MOTION NE fournit AUCUN contenu, chaîne, flux ni abonnement.
L'application est un simple lecteur : vous apportez votre propre source et
restez seul responsable de son contenu et de sa légalité.

Politique de confidentialité : https://seven-motion-backend.manzilionel-lm.workers.dev/privacy
```

**Catégorie** : Outils / Lecteurs et éditeurs vidéo (PAS « Divertissement TV »).
**Mots-clés à ÉVITER** : « IPTV », « chaînes gratuites », « TV en direct »,
« sport/films gratuits », « premium ». **À privilégier** : « lecteur »,
« player », « M3U », « playlist », « média ».

---

## 2. Google Play — étapes

1. Compte développeur Google Play (25 $ une fois) : play.google.com/console.
2. Créer l'app → uploader `7motion.aab` (Play App Signing activé par défaut).
3. Fiche : nom, descriptions ci-dessus, icône, 2–8 captures, bannière 1024×500.
4. **Politique de confidentialité** : `https://seven-motion-backend.manzilionel-lm.workers.dev/privacy`.
5. **Data safety** : déclarer — identifiant d'appareil + IP/pays (sécurité/
   fonctionnement), pas de vente de données. (Cf. la page /privacy.)
6. **Content rating** : remplir le questionnaire (PEGI 3 / Tout public si pas
   de contenu adulte embarqué).
7. Test fermé (quelques testeurs) → puis Production.

⚠️ Risque : catégorie sensible. Si refus, rester ferme sur « lecteur générique,
aucune source fournie », et retirer tout mot évoquant l'IPTV/streaming gratuit.

---

## 3. Aptoide — étapes (le plus simple)

1. Compte sur aptoide.com (Aptoide Uploader / Dev console).
2. Uploader directement `7motion.apk`.
3. Coller nom + descriptions + URL privacy. Publier (review légère).

---

## 4. Huawei AppGallery — étapes

1. Compte Huawei Developer (connect-api.cloud.huawei.com), vérification
   d'identité requise.
2. Créer l'app → uploader `7motion.apk` (ou `.aab`).
3. Fiche + **Privacy Policy URL** (`/privacy`) obligatoire.
4. Questionnaire de contenu + tranche d'âge.

ℹ️ Sur les téléphones Huawei récents (sans services Google) : le **Google Cast**
ne fonctionnera pas (il dépend des Google Play Services), mais la lecture locale
et le **cast DLNA** fonctionnent. L'app se dégrade proprement.

---

## 5. Clé de signature (rappel technique)

Le CI signe l'APK ET l'AAB avec la clé stable (alias `sevenmotion`), via les
secrets GitHub `ANDROID_KEYSTORE_BASE64` + `ANDROID_KEYSTORE_PASSWORD`.
**Ne perds JAMAIS ce keystore** : c'est lui qui permet de publier des MISES À
JOUR de la même app. Sauvegarde-le hors du repo.
