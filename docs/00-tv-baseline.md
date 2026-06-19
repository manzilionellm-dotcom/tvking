# 00 — Baseline & audit du client TV (Phase 0)

> Livrable de la **Phase 0** du chantier « Finition TV Haut de Gamme ».
> Portée : **audit de code** (lecture du dépôt). Les mesures qui exigent un
> appareil réel (TTFF, frame rate) sont **listées mais non remplies** ici —
> elles doivent être prises sur la box de test la plus faible.
>
> App : `tv_king`, édition TV (`lib/main_tv.dart`), cible Android TV / Fire TV /
> Google TV. Lecteur TV : plugin local `packages/native_video_player`
> (Media3 / ExoPlayer, SurfaceView). Lecteur mobile : `media_kit` (libmpv).

---

## A. Confirmation des points ❓ (par le code)

| # | Point | Verdict | Preuve / détail |
|---|-------|---------|-----------------|
| 1 | **DRM / Widevine** | ❌ **Absent** | Aucune occurrence `drm`/`widevine`/`MediaDrm`/`license` dans `lib/` ni `packages/native_video_player`. `NativeVideoView.kt` utilise une `DefaultMediaSourceFactory` sans `DrmSessionManager`. → flux **en clair uniquement** (HLS/DASH/TS). |
| 2 | **Grille EPG** | ✅ **Vraie grille** | `lib/features/epg/presentation/tv_guide_screen.dart` : chaînes en lignes (ListView, 50/page) × timeline 24 h horizontale, ligne « now » rafraîchie 30 s, cellule → live / catch-up / rappel. Données : `xmltv_parser.dart` (streaming) → SQLite `epg_programs` index `(channel_id, start_time)`. |
| 3 | **Écran Détail VOD (TV)** | ❌ **Absent sur TV** | VOD existe **seulement sur mobile** (`lib/features/vod/presentation/movies_screen.dart`, modèle `vod_movie.dart` avec `posterUrl`/`rating`/`year`). Aucun `tv_vod_screen`/`tv_detail_screen`. **La TV = Live + Enregistrements + Recherche live.** |
| 4 | **Reprise au timecode** | 🟡 **Partiel** | `recently_watched_repository.dart` = « dernière **chaîne** » (channel_id + timestamp, max 50), avec `seedIfEmpty()` cross-device si cache vide. **Aucune** table `watch_progress`/`resume_position` → pas de reprise d'un **film au timecode**, ni de synchro de position cross-device. La position live (`NativeVideoView.kt`, toutes les 500 ms) sert **uniquement à l'affichage**, non sauvegardée. |
| 5 | **Sous-titres / pistes (TV)** | ❌ **Absent sur TV** | Le lecteur natif TV n'expose **aucune** piste : `onTracksChanged()` ne lit que le MIME vidéo (diagnostic) ; `NativeVideoController` ne publie ni `audioTracks` ni `subtitleTracks`. Le sélecteur de pistes (`player_tracks_sheet.dart`, 13 langues) existe **seulement** côté **mobile/media_kit**. |
| 6 | **Accessibilité (Semantics)** | ❌ **Absent** | Zéro `Semantics(` dans `lib/features/tv/`. Pas de labels TalkBack sur les éléments focusables ni les commandes lecteur. |
| 8 | **Préchargement / zapping** | ❌ **Absent** | `tv_player_screen.dart` : `_zap(delta)` → `_open()` → `setUrl(...)` **au moment du zap**. Aucun prefetch du manifest/segments des chaînes adjacentes. ExoPlayer en `DefaultLoadControl` standard. |
| 9 | **Multi-profils** | ❌ **Absent** | `parental_controls.dart` = singleton `kidsMode: ValueNotifier<bool>` **global** (clé `security.kids_mode.v1`). Pas de table `profiles`, pas d'historique/favoris par profil. → **Mode Enfants global**, pas multi-profils famille. |
| 10 | **Instrumentation perf** | 🟡 **Partiel** | Seul garde-fou : `_loadTimeout = 12 s` (anti-spinner infini, annulé dès `firstFrame`). **Aucun** `Stopwatch`/`Timeline`/`addTimingsCallback` → **pas de mesure TTFF ni de frame timing**. |

---

## B. Audit du focus (mémoire & autofocus), écran par écran

État : un moteur de focus maison solide (`TvFocusable`/`TvFocusBuilder`), mais
la **mémoire de focus** repose surtout sur la restauration implicite de Flutter.
Un seul mécanisme **explicite** robuste existe (le rail de navigation).

| Écran | Mécanisme | État |
|-------|-----------|------|
| `tv_app.dart` (rail nav) | `FocusNode _railFocus` posé sur l'item sélectionné + `requestFocus()` au RETOUR depuis le contenu (`tv_app.dart:399, 498, 544, 674`) | ✅ **Robuste** (seul vrai pattern de mémoire) |
| `tv_live_screen.dart` | Catégorie item 0 `autofocus: i==0 && !_heroShown` (`:504`) ; bandeau « Continuer » **sans** autofocus (corrigé récemment → laisse la restauration ramener sur la chaîne) ; `autofocus:true` du bouton « Réessayer » est sur l'**état vide** seulement (`:447`) | 🟡 OK après correctif, à re-vérifier sur grille |
| `tv_search_screen.dart` | `autofocus: i==0` 1re touche clavier ; instance `_keyboard` réutilisée (`:233`) | ✅ Stable |
| `tv_sports_screen.dart` | `autofocus: i==0` (`:101`) + `autofocus:true` bouton Ajouter (`:133`) ; refait le focus au retour du picker | 🟡 Risque de saut |
| `tv_recordings_screen.dart` | `autofocus: i==0` (`:58`) | ✅ OK |
| `tv_parental_screen.dart` | `autofocus:true` champ PIN (`:122`), `autofocus: k=='5'` (`:411`) | 🟡 Fragile (clé en dur) |
| `tv_settings_screen.dart` | `autofocus:true` bouton Rafraîchir (`:143`) | 🟡 Focus perdu si reconstruction |
| `tv_player_screen.dart` | `FocusNode _focus` captif + `autofocus:true` (`:74, 664`), D-pad bridé (`_onKey`) | ✅ OK (captif pendant lecture) |
| `tv_add_source` / `tv_sources` / `tv_add_m3u` | `autofocus:true` divers (champs/1er item) | 🟡 À harmoniser |

**Constat clé :** pas de **sauvegarde explicite du chemin de focus** (écran +
index) hors du rail. Au retour d'un écran (autre que le lecteur, déjà corrigé),
le focus peut se reposer sur le 1er élément plutôt que sur le dernier utilisé.

---

## C. Baselines de performance — À MESURER (sur appareil réel)

> ⚠️ Non remplies ici : impossibles sans la box de test. À chiffrer **avant**
> toute optimisation, puis re-mesurer **après** (règle « mesure, ne devine pas »).

Box de test cible : `[À RENSEIGNER — ex. Fire TV Stick Lite / Chromecast Google TV HD]`

| Métrique | Méthode suggérée | Avant | Cible | Après |
|----------|------------------|-------|-------|-------|
| **TTFF — lancement chaîne** | `Stopwatch` de `setUrl()` → `firstFrame` | _à mesurer_ | < 2 s | — |
| **TTFF — zapping** | idem sur `_zap()` | _à mesurer_ | < 2 s | — |
| **Jank scroll grille chaînes** | `SchedulerBinding.addTimingsCallback` / DevTools | _à mesurer_ | 60 fps | — |
| **Jank scroll EPG** | idem | _à mesurer_ | 60 fps | — |
| **Mémoire (grosse liste)** | DevTools memory | _à mesurer_ | stable | — |
| **Taux crash-free** | Crashlytics (à activer) | _n/a_ | > 99,5 % | — |

**Pré-requis bloquant :** activer **Crashlytics** (secret CI `GOOGLE_SERVICES_JSON`
+ projet Firebase). Le code est déjà câblé en *fail-open*
(`lib/core/crash/crash_reporting_firebase.dart`) ; il ne s'active qu'avec le secret.

---

## D. Liste priorisée des défauts (→ phases du chantier)

**P1 — Vitesse perçue**
- ❌ Pas de préchargement zapping (charge à la demande) → cible : prefetch chaînes adjacentes.
- ❌ TTFF non mesuré, pas de surface lecteur « tiède »/prebuffer.
- 🟡 Jank scroll non mesuré (vérifier `const`/`RepaintBoundary`/rebuilds).

**P2 — Focus durci**
- 🟡 Mémoire de focus non explicite hors rail (sauver écran+index).
- 🟡 Autofocus fragiles sur boutons éphémères (Rafraîchir, Ajouter, PIN).
- ❓ Stresser la navigation spatiale sur la **grille EPG** dense.

**P3 — Complétude haut de gamme**
- ❌ Multi-profils famille (aujourd'hui : Mode Enfants global).
- ❌ Écran Détail VOD sur TV **+ tout le parcours VOD TV** (VOD = mobile only) → **décision produit requise** (cf. §E).
- 🟡 Reprise VOD au timecode + synchro cross-device.
- ❌ Screensaver / mode ambient (anti burn-in OLED).

**P4 — Robustesse & conformité**
- ❌ Tests automatisés (focus, smoke lecteur, golden tokens).
- ❌ DRM Widevine — **seulement si** du contenu licencié l'exige (cf. §E).
- ❌ Accessibilité / Semantics + sous-titres côté lecteur TV.

---

## E. Décisions produit à trancher (avant P3/P4)

1. **VOD sur TV** : le prompt prévoit un écran Détail VOD « si le catalogue VOD est
   significatif ». Or **il n'y a aujourd'hui aucun parcours VOD sur TV** — ce n'est
   pas « un écran à ajouter », c'est **toute une section** (liste films/séries +
   détail + lecture media_kit/Media3). → Confirmer s'il y a un vrai catalogue VOD à
   exposer sur TV, sinon **différer**.
2. **DRM** : à n'implémenter que si des fournisseurs imposent Widevine. Sinon, coût
   inutile. → Confirmer la nature des flux (clair vs protégé).
3. **Sous-titres sur TV** : nécessite d'exposer les pistes dans le plugin natif
   (`native_video_player`) — travail Kotlin réel, pas juste du Dart.

---

## F. Conclusion

Base **solide et stable** : EPG complète, anti-OOM, anti-crash, focus de qualité,
design premium. Les écarts vers le haut de gamme sont **bien cernés** et **non
bloquants** : surtout la **vitesse perçue (mesure + prefetch zapping)**, la
**mémoire de focus explicite**, et des **manques fonctionnels** (multi-profils,
VOD TV, screensaver, tests, accessibilité).

**Prochaine étape :** renseigner la box de test + activer Crashlytics, puis
remplir les baselines du §C avant d'attaquer la Phase 1.
