# Amazon Appstore — 7 MOTION

Canal **prioritaire** : les Fire TV Stick sont l'appareil le plus vendu
pour ce type d'application, et l'Amazon Appstore y est la seule boutique
préinstallée. C'est aussi un examen historiquement plus rapide et plus
prévisible que Google Play.

## Le binaire — le point qui se rate en silence

Amazon accepte des **APK** (jamais d'AAB). Le CI en produit deux, et il
faut envoyer **les deux** :

| Fichier | Architecture | Appareils |
|---|---|---|
| `7motion.apk` | arm64-v8a | Fire TV Stick 4K / Max, Fire HD récentes, téléphones modernes |
| `app-armeabi-v7a-release.apk` | armeabi-v7a | **Fire TV Stick 2ᵉ et 3ᵉ génération**, vieilles Fire HD |

Beaucoup de Fire TV Stick encore en service sont en **32 bits**. Avec le
seul arm64, l'Appstore ne propose pas l'application sur ces appareils —
sans erreur, sans message : elle n'apparaît simplement pas dans leur
boutique. Le genre de panne qu'on ne découvre que par un client qui
écrit « je ne la trouve pas ».

Amazon accepte plusieurs APK par fiche et sert le bon selon l'appareil.

Récupération : Actions → dernier run `build-android` réussi → artefacts
`tvking-release-apk-<sha>` et `7motion-armeabi-v7a-<sha>`.

## Ce qu'Amazon vérifie et que Google ne regarde pas

1. **Pas de Google Play Services.** Fire OS n'en a pas. L'app utilise
   Google Cast : sur Fire TV, le bouton Cast ne trouvera aucun appareil.
   Ce n'est pas bloquant tant que **l'app ne plante pas** — à vérifier
   sur un vrai Fire TV avant de répondre au questionnaire.
2. **Pas de facturation Google Play**, et aucun lien vers une autre
   boutique. Le bouton de mise à jour intégré est déjà retiré des builds
   magasin (`kIsPlayBuild`) : appliquer la même règle ici.
3. **Télécommande obligatoire** sur une fiche Fire TV : tout doit être
   atteignable au D-pad, sans écran tactile.
4. **Captures d'écran en paysage** pour Fire TV (1280×720 minimum). Les
   captures téléphone en 9:16 de la fiche Play ne conviennent pas : il
   faut celles de l'application TV.

## Textes de la fiche

Ils sont déjà rédigés dans `../store-listing.md`, section 3 (titre,
description courte, mots-clés, catégorie) et section 4 (description
longue, réutilisable telle quelle).

Règle inchangée, et elle vaut ici aussi : **aucun nom de chaîne réelle,
aucun logo de diffuseur, aucun nom de bouquet de fournisseur**, ni dans
les textes, ni dans les captures. Le mode démo existe pour ça.

## Ce qu'il reste à produire

- [ ] Captures **Fire TV en paysage** (1280×720 ou plus) — à prendre sur
      l'app TV en mode démo
- [ ] Icône 512×512 (celle de Play convient)
- [ ] Image de présentation 1280×720
- [ ] Réponse au questionnaire d'export et à la classification de contenu
