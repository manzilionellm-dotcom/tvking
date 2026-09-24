# country_home — Accueil pays « Maison Noir » (7 MOTION)

Refonte de l'écran d'une catégorie/pays (mobile), pensée **seniors +
découverte** : on cure le contenu à la place de l'utilisateur (gros HERO
à taper, chaînes populaires mises en avant, texte large, grandes cibles).

## Structure
```
data/
  channel_curation.dart      cleanName(), logoInitials(), logoFallbackColor()  (fonctions pures)
  popularity_repository.dart getPopularChannels()  (score local persistant)
  text_scale_repository.dart réglage "Texte plus grand" ×1.15
presentation/
  country_home_view.dart     le corps de l'écran (HERO, Populaires, Reprendre, sections)
  widgets/                   channel_logo, hero_card, popular_card, resume_card, channel_list_row
```
La barre du haut (retour + pays) et la nav du bas (Accueil / Favoris / IA /
Ajouter) restent fournies par `SimpleHomeScreen`. La zone **Cinéma & Séries
verrouillée** est passée en `trailing` (le verrou adulte/biométrie reste
géré dans `SimpleHomeScreen`).

## Où brancher la VRAIE playlist
Rien à faire : `CountryHomeView(channels: …)` reçoit déjà les `Channel`
issus de `PlaylistRepository` (M3U / Xtream déjà parsés). L'EPG « en ce
moment » vient de `Channel.currentProgram` (masqué si vide).

## Où brancher un VRAI compteur serveur (popularité)
Tout passe par `PopularityRepository.getPopularChannels(channels)`.
Aujourd'hui : score local = `ouvertures×3 + favori×5 + récence`
(persisté en SharedPreferences). Pour basculer sur des stats serveur,
réécrire **uniquement** `getPopularChannels()` (et/ou `scoreFor`) — l'UI
ne change pas. Le hook d'usage est `recordOpen(channelId)`, appelé avant
chaque lecture.

## Notes
- La barre de progression "Reprendre" est **cosmétique** (position de
  reprise réelle non encore stockée) — à brancher plus tard.
- Le compteur « X regardent » est déterministe (effet vivant), à
  remplacer par la vraie présence quand dispo.
- Couleurs/typo : tokens **Maison Noir** dans `AppColors` / `AppTextStyles`
  (jamais de `Color(0xFF…)` dans l'UI).
- Aucune dépendance au module **cast**.
```
