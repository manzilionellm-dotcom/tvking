# Rapport de vérification des applications — 2026-07-31

## Ce qui a été découvert

Le dépôt `tvking` contient en réalité **plusieurs applications sur des branches
différentes** — c'est la source de la confusion :

| Application | Où elle vit | Technologie | État |
|---|---|---|---|
| **7 MOTION** (téléphone + TV + Fire TV) | branche `claude/maison-mere-phone` (747 fichiers) | Flutter/Dart, lecteur libmpv | **L'app principale.** Builds APK via `build-android.yml`, iOS, Windows, Tizen. Serveur, gateway, admin-panel inclus. |
| **TV King** (web/PWA) | branche `main` | Next.js 16 / React | Prototype web avec **données fictives** (mock). Déployé sur `tvking.vercel.app` + GitHub Pages. |
| **De Few TV** (box/cinéma) | branche « Seven Cinéma » (APK publié par `publish-cinema-test.yml`) | Android | Variante TV signée avec la clé maîtresse. |

Le dépôt `7themotion` ne contient **que de la documentation** (audits casting,
rapports) — aucun code d'application.

## La capture d'écran (Champions League)

La page vue sur `tvking.vercel.app` est bien l'app **TV King web** de la branche
`main`. Le contenu « Champions League — Finale en direct » est une **donnée de
démonstration codée en dur** (`app/lib/data.ts`, ligne 72). Ce n'est pas un vrai
flux : rien n'est actif, c'est une maquette.

## Les bons côtés de TV King vs ce que 7 MOTION a déjà

| Idée forte de TV King (web) | Déjà dans 7 MOTION (Flutter) ? |
|---|---|
| Playlists M3U de l'utilisateur | ✅ Oui (`features/playlists`, 28+ fichiers, parsing M3U) |
| Reprise de lecture (« La lecture vous suit ») | ✅ Oui (resume présent) |
| Téléchargements / lecture locale | ✅ Partiel (4 fichiers download, VOD, recordings) |
| Lecteur + EPG + Sport + VOD | ✅ Oui, plus complet que TV King |
| Navigation D-pad / focus TV | ✅ Oui (`tv_focusable`, `tv_palette`, routes TV) |
| **Consentement CGU bloquant au premier lancement** (`ConsentGate`) | ⚠️ Partiel — `legal_disclaimer` existe mais pas de porte bloquante dédiée |
| **Vérification de chaque lien AVANT lecture** (raison d'échec affichée, jamais d'attente infinie) | ❓ À vérifier dans le code du lecteur |
| **Mini-lecteur flottant façon YouTube** (contrôles intégrés) | ⚠️ PiP système seulement, pas de mini-lecteur in-app |
| **« Zéro spinner »** : progression déterminée en % partout | ❓ À auditer (`shimmer_box` suggère des placeholders, pas des spinners) |
| Charte TV (fond #121212, blanc 87 %, safe-area 5 %, scaling vw) | ✅ Théming avancé déjà présent (`lumiere_tokens`, `tv_palette`) |

**Conclusion : l'essentiel de TV King existe déjà dans 7 MOTION.** Les 3 apports
réellement portables sont : (1) la porte de consentement CGU bloquante,
(2) la vérification systématique des liens avant lecture avec raison d'échec,
(3) le mini-lecteur flottant in-app.

## ⚠️ AVERTISSEMENT avant toute suppression de TV King

**Ne pas supprimer le dépôt `tvking` : c'est le même dépôt qui contient le code
source de 7 MOTION** (branche `claude/maison-mere-phone`) et tous les workflows
de build APK. Supprimer le dépôt « sans trace » détruirait 7 MOTION aussi.

Supprimer TV King en sécurité = uniquement :
1. le déploiement Vercel `tvking.vercel.app` (ou le protéger par mot de passe) ;
2. le déploiement GitHub Pages (branche `gh-pages` + workflow `deploy-pages.yml`) ;
3. le code web Next.js de la branche `main` — **après** avoir porté les 3 apports
   ci-dessus dans l'app Flutter.
