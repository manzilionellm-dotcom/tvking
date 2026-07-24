# Décisions — USINE APP v2 (périmètre mobile)

## Run 001 — 2026-07-24

### D-2026-07-24-01 — Base de la branche de travail
`main` ne contient PAS l'app Flutter (histoire git séparée : prototype web
Next.js « TV King »). La branche de référence téléphone la plus récente est
`claude/maison-mere-phone` (43f751d, 2026-07-22, CI Quality verte).
→ `claude/usine-app-v2-mobile-e3ungl` repart de ce commit.

### D-2026-07-24-02 — Périmètre STRICT mobile (consigne client)
Tout `lib/features/tv/`, `lib/main_tv.dart` et les workflows/tags TV sont
intouchés. Les 5 warnings d'analyse restants y résident : ils sont
volontairement laissés en l'état. Le code PARTAGÉ (player, playlists, epg,
channels, settings…) sert aussi la TV : chaque modification partagée de ce
run est neutre en comportement pour la TV (nettoyages + caches).

### D-2026-07-24-03 — `Channel.invalidate` mort → `clearComputedCaches` câblé
Le nettoyage anti-fuite des caches calculés (genre/pays/qualité/nom curé)
existait mais n'était JAMAIS appelé (fuite douce à chaque remplacement de
playlist). Plutôt que supprimer l'intention, on l'a réalisée : vidage complet
(recalcul paresseux, coût nul) appelé dans `_deletePlaylist` et
`deleteAllPlaylists`. Vider tout plutôt que par id évite une requête SQL
supplémentaire sur un chemin déjà lent (delete cascade 10-30 s sur 20k).

### D-2026-07-24-04 — Garde anti multi-open du zap bouton (lecteur mobile)
`_zapAnimating` était posé mais jamais lu : la garde documentée n'existait
pas. Cas réel : ⏮ sur la 1re chaîne → `animateToPage` vers la dernière
traverse TOUTES les pages, chaque `onPageChanged` déclenchait un
`_player.open`. Implémenté tel que documenté : pages traversées ignorées,
zap appliqué UNE fois en fin d'animation. Pas de test automatisé possible
sans harnais media_kit (dette D5) — vérification manuelle à prévoir dans le
plan de test de release (zap bouton aux bornes de la liste, puis swipe).

### D-2026-07-24-05 — `_ThemeModePicker` supprimé (jamais branché)
Sélecteur Cinema/Daylight/Système complet mais jamais référencé depuis le
commit de naissance ; `main.dart` force `themeMode: ThemeMode.dark`. Ce
n'est PAS une fonctionnalité vivante → suppression du code mort ; la
décision produit « brancher le mode Daylight ou retirer AppTheme.daylight »
est consignée en dette D3.

### D-2026-07-24-06 — Legacy `HomeScreen` conservé
`home_screen.dart` (accueil v1.4) n'est instancié nulle part — l'accueil
actif est `SimpleHomeScreen`. On n'a retiré QUE la méthode morte
`_openAdultGuarded` (et l'import biométrie orphelin). Le retrait du fichier
entier est en dette D2 (à confirmer qu'aucune reprise n'est prévue).
NOTE sécurité vérifiée : la section Adulte de l'UI ACTIVE passe par le
rayon Adulte de `category_browser_view` + garde d'âge/PIN (features/security),
la garde biométrique supprimée n'était pas le chemin actif.
