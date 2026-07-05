# Audit des 20 fonctionnalités demandées — état & décisions

> Principe suivi (demande Lionel) : *« Tu vois ce qu'on a, tu ajustes bien.
> Ce qu'on n'a pas besoin, tu laisses. »* Chaque ligne dit ce qui existe,
> ce qui a été ajusté, ou pourquoi c'est écarté. Règle absolue : ne jamais
> fragiliser le lecteur vidéo ni l'import de source (stabilité d'abord).

| # | Fonctionnalité | Verdict | Détail |
|---|---|---|---|
| 1 | Zapping ultra-rapide | ✅ **Existe** | D-pad Haut/Bas (Ch+/Ch-) + saisie du numéro de chaîne dans le lecteur (`tv_player_screen`). ExoPlayer démarre déjà au plus vite. On ne touche pas au lecteur. |
| 2 | MultiView | ✅ **Existe** | `tv_multiview_screen.dart` (mosaïque multi-flux). |
| 3 | Retour en arrière sur le direct (timeshift / catch-up) | ✅ **Fait (via l'archive fournisseur)** | Réalisé SANS enregistrement local ni changement de lecteur : on rejoue depuis l'**archive du fournisseur** (`tv_archive` Xtream / `catchup-days` M3U). `CatchupUrlBuilder` fabrique l'URL timeshift ; le lecteur reçoit une URL comme une autre → qualité/stabilité intactes. **Mobile** : déjà branché (émissions passées). **TV** : AJOUTÉ — bouton « ⟲ Revoir » sur une émission passée OU en cours (revoir depuis le début, ex. le match commencé il y a 1 h). Si la chaîne n'a pas d'archive → le bouton n'apparaît pas. |
| 4 | Synchronisation de lecture entre appareils | ✅ **Existe (partiel)** | L'historique suit le client de box en box via `/api/history/:mac` (restauré sur box neuve). La position de lecture fine multi-appareils exigerait des endpoints worker dédiés — à planifier côté serveur d'abord. |
| 5 | Assistant IA | ✅ **Existe** | `ai_search_service.dart` → `/api/ai/search` du worker. |
| 6 | Recherche intelligente | ✅ **Existe** | Écran recherche TV + service IA ci-dessus + historique de recherche par profil. |
| 7 | EPG enrichi | ✅ **Existe** | XMLTV (`xmltv_parser`), guide grille horaire style câble US (`tv_guide_grid_screen`), timeline (`tv_timeline_guide_screen`), programmes par chaîne, mini EPG now/next. |
| 8 | Détection des temps forts | ⛔ **Écarté** | Analyse vidéo temps réel sur box Android TV : irréaliste (CPU/RAM) et contraire à la règle anti-OOM. Piste future : temps forts fournis par le serveur (métadonnées), pas par la box. |
| 9 | Streaming adaptatif optimisé | ✅ **Déjà natif** | ExoPlayer fait l'ABR (HLS/DASH) nativement. Rien à ajouter côté app sans risque. |
| 10 | Amélioration vidéo par IA | ⛔ **Écarté** | Upscaling IA = silicium dédié (Shield/Tensor) que l'OS applique déjà tout seul quand il existe. Le simuler en soft tuerait les petites box. |
| 11 | Amélioration intelligente du son | ⛔ **Écarté** | Exige des processeurs audio custom dans le pipeline ExoPlayer → contact direct lecteur, interdit par notre règle de stabilité. |
| 12 | Profils utilisateurs avancés | ✅ **Existe (renforcé récemment)** | « Qui regarde ? » façon Netflix au lancement, pastille de profil, données par profil (récents, recherches, collections, Ma Liste, **stats**). |
| 13 | Contrôle parental | ✅ **Existe** | PIN + Mode Enfants (`parental_controls`, `tv_parental_screen`), filtrage Adulte au premier rendu. |
| 14 | Favoris intelligents | ✅ **Existe** | `affinity_service.dart` + `time_of_day_service.dart` (recommandations selon habitudes et heure) + favoris SQLite + collections. |
| 15 | Statistiques personnelles | 🆕 **AJOUTÉ (ce commit)** | Module indépendant `features/stats/` : temps d'écran + top chaînes par profil, 100 % local (vie privée), échantillonnage 1 min de `NowPlaying` (zéro contact lecteur, zéro réseau). Écran « Mes statistiques » dans Réglages. |
| 16 | Synchronisation second écran | ✅ **Existe** | Cast DLNA/SSDP complet (`cast_manager`, warmup, progression, diagnostics). |
| 17 | Télécommande mobile avancée | ⛔ **Écarté (hors périmètre TV)** | C'est un chantier de l'app mobile sœur (même repo, flavor mobile) + un canal de commande à concevoir côté worker. À traiter comme projet dédié. |
| 18 | Téléchargement hors ligne | ✅ **Existe** | Enregistrements (REC) + téléchargeur HTTP + reprise des enregistrements orphelins au boot. |
| 19 | Interface hautement personnalisable | ✅ **Existe (enrichi récemment)** | Overscan, grand texte, **Nuit Royale** (confort nocturne), thème distant piloté par le panel, layout d'accueil piloté par le panel (`home_layout_repository`), **ambiances intelligentes** par univers. |
| 20 | Tableau de bord admin & supervision | ✅ **Existe** | `admin-panel/` (React) : clients en ligne, « qui regarde quoi » (NowPlaying via heartbeat), versions installées, sources par appareil, activation/gel/ban, annonces, thème. |

## Architecture du module ajouté (n°15 — Statistiques)

```
lib/features/stats/
  data/watch_stats_service.dart   Échantillonneur 1 min + stockage JSON
                                  (SharedPreferences, clé par profil,
                                  30 jours glissants, purge auto)
lib/features/tv/presentation/
  tv_stats_screen.dart            Écran « Mes statistiques » (10-foot)
```

- **Indépendance** : aucun autre module ne dépend de lui ; il ne lit que
  `NowPlaying` (déjà public) et `ProfilesRepository.keySuffix`.
- **Performances** : 1 tick/minute, écriture d'un petit JSON uniquement
  quand on regarde ; l'écran est du pur widget (barres = `Container`).
- **Sécurité/vie privée** : tout est local à la box ; rien n'est envoyé.
- **Intégration progressive** : le service démarre au boot mais n'affecte
  rien d'existant ; en cas de préférence corrompue, il repart de zéro
  sans jamais jeter (try/catch systématique).
