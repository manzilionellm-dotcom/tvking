# Centre de contrôle temps réel — Feuille de route

> Objectif : piloter TOUTE l'app (accueil, thèmes, bannières, événements,
> promos, notifications) depuis le panneau admin **sans republier sur le
> Play Store / App Store et sans redémarrer l'app**.

Ce document est la **référence unique** du projet « centre de contrôle ».
Il décrit l'architecture, les 10 modules demandés, le modèle de données et
le **plan par phases** (réaliste, livrable étape par étape).

---

## 1. Le principe technique (déjà prouvé)

Tout repose sur une seule idée, le **Server-Driven UI (SDUI)** :

```
[Panel admin] --écrit--> [Config centrale en base D1] <--lit-- [App au démarrage + périodiquement]
```

L'app ne contient PAS les décisions d'affichage en dur : elle les
**télécharge** depuis le Worker Cloudflare. Modifier la config côté panel
= l'app change, sans mise à jour de store.

**C'est déjà en place et en production** pour deux briques :
- **Annonces** (`/api/announcement`) — bandeau + notification pilotés à distance.
- **Mise à jour forcée** (`kBuildTs` vs dernière version) — gate distant.

Les 10 modules ci-dessous étendent ce même socle.

### Exigences transverses (à respecter partout)
- **Temps réel** : l'app rafraîchit la config au démarrage + toutes les
  N minutes (polling léger) ou au retour de premier plan.
- **Cache intelligent** : dernière config valide stockée localement
  (SharedPreferences/fichier) → l'app marche même hors-ligne, et ne
  « clignote » pas au lancement.
- **Rollback instantané** : chaque config est **versionnée** (numéro +
  horodatage). Revenir à la version précédente = un clic au panel.
- **Sans redéploiement** : tout passe par la base D1 + l'API, jamais par
  le code de l'app.

---

## 2. Architecture cible

```
admin-panel (React, Cloudflare Pages)
        │  REST /api/v1/*  (auth super_admin)
        ▼
Worker Cloudflare (worker.js + api_v1.js)
        │
        ├── D1 (SQLite)      → config, règles, contenus, segments
        ├── KV               → cache config "compilée" (lecture app ultra-rapide)
        └── R2               → images / vidéos des bannières (upload)
        ▲
        │  GET /api/config (public, versionné, mis en cache)
        ▼
App Flutter (lit la config, applique, garde un cache local)
```

**Point clé** : l'app lit **UNE** ressource agrégée `GET /api/config` qui
contient tout (home, thème actif, bannières actives, notifications dues).
Une seule requête, mise en cache → rapide et robuste.

---

## 3. Les 10 modules → mapping architecture

| # | Module | Donnée pilotée | Table D1 | Vu côté app |
|---|--------|----------------|----------|-------------|
| 1 | **Dynamic Home Manager** | ordre / épingle / vedette / rubans des catégories | `home_layout` | accueil réordonné |
| 2 | **Banners Manager** | image/vidéo, dates, bouton, lien | `banners` (+ R2) | carrousel haut d'accueil |
| 3 | **Thèmes dynamiques** | couleurs, fond, logos, icônes | `themes` + `active_theme` | thème appliqué à chaud |
| 4 | **Notifications** | push / popup / bandeau / plein écran + planif + segment | `notifications` | déjà partiel (annonces) |
| 5 | **Analytics avancés** | events de l'app (vues, durées, erreurs, pays) | `events` (ingestion) | tableau de bord SaaS |
| 6 | **Featured Content** | film/série/chaîne/catégorie mis en avant | `featured` | héros / rails « à la une » |
| 7 | **Schedule Automation** | règles « si … alors … » (date, événement) | `rules` | applique modules 1/2/3 auto |
| 8 | **Live Control Center** | activer/masquer/réordonner une catégorie | `home_layout` (flags) | instantané |
| 9 | **A/B Testing** | variantes (home, couleurs, bannières) + mesure | `experiments` + `events` | variante assignée par appareil |
| 10| **Admin Experience** | recherche, filtres, historique, journal | `audit_log` (existe déjà) | UI panel moderne |

**Observation importante** : les « catégories » de l'app proviennent de la
**playlist IPTV du client** (M3U/Xtream), elles ne sont pas un catalogue
fixe. Les modules 1/6/8 fonctionnent donc par **règles de correspondance
par nom de catégorie** (ex. « tout ce qui contient *Sport* → position 1 »)
plutôt que par IDs figés. À cadrer à l'implémentation.

---

## 4. Modèle de données (esquisse D1)

```sql
-- Versionnage global (rollback instantané)
config_versions(id, label, payload_json, created_at, created_by, active INTEGER)

-- Module 1 / 8 : accueil
home_layout(id, match_type, match_value, position, pinned, featured,
            ribbon, enabled, updated_at)
  -- ribbon ∈ NOUVEAU|POPULAIRE|EXCLUSIF|EN DIRECT|VIP|COUPE DU MONDE|EURO 2028|UFC|CHAMPIONS LEAGUE

-- Module 2 : bannières
banners(id, kind/*image|video*/, media_url, title, cta_label, cta_url,
        starts_at, ends_at, position, enabled, created_at)

-- Module 3 : thèmes
themes(id, name, primary, secondary, background, logo_url, icon_set, extra_json)
active_theme(theme_id, applied_at)

-- Module 4 : notifications
notifications(id, type/*push|popup|banner|fullscreen*/, title, body, media_url,
              cta_label, cta_url, schedule_at, segment/*all|android|androidtv|samsung|lg|firetv*/,
              status, created_at)

-- Module 5 / 9 : analytics + expériences
events(id, device_id, ts, type, value_json, country, platform)
experiments(id, name, variants_json, metric, status, created_at)

-- Module 7 : automatisation
rules(id, name, condition_json, action_json, enabled, last_fired_at)

-- Module 10 : journal (déjà présent : audit_log)
```

---

## 5. Plan par phases (réaliste)

Chaque phase est **livrable et utile seule**. On ne commence pas la
suivante tant que la précédente n'est pas en prod et stable.

### Phase 1 — SOCLE + Live Control / Dynamic Home  ⭐ (recommandé en premier)
*Modules 1 + 8, + l'ossature commune (config versionnée, cache, rollback).*
- `GET /api/config` agrégé + versionnage + rollback.
- Table `home_layout` + CRUD panel.
- Panel : page « Accueil » avec **glisser-déposer**, épingler, vedette,
  activer/masquer, choix du **ruban**.
- App : l'accueil lit `home_layout` et réordonne / masque / affiche les
  rubans (correspondance par nom de catégorie).
> C'est la clé de voûte : une fois ce socle là, les modules 2/3/6/7
> s'y branchent vite.

### Phase 2 — Bannières (Module 2)
- Upload image/vidéo (R2), dates début/fin, bouton + lien.
- Carrousel en haut de l'accueil, activation instantanée.

### Phase 3 — Thèmes dynamiques (Module 3)
- L'app a déjà un `AccentController` (couleurs centralisées) → on le pilote
  à distance. Presets : Standard, Premium, Gold, Platinum, World Cup,
  Christmas, Black.
- Thème appliqué à chaud (pas de redémarrage).

### Phase 4 — Notifications avancées + Featured (Modules 4 + 6)
- Étendre l'actuel système d'annonces : types (popup, plein écran),
  planification (date/heure), **segmentation** (Android, TV, Samsung, LG,
  Fire TV). Détection de plateforme côté app.
- Featured content (héros / rails « à la une »).

### Phase 5 — Automatisation + Analytics + A/B (Modules 7 + 5 + 9)
- `rules` (si décembre → thème Noël ; si Coupe du Monde → Sport #1…).
- Ingestion d'**events** depuis l'app → dashboard temps réel.
- A/B testing (variantes + mesure clic/temps/conversion).
> Ce sont les plus lourds (pipeline data, scheduler côté Worker via Cron
> Triggers). À faire en dernier, une fois le contenu piloté en place.

### Phase 6 — Admin Experience (Module 10)
- Recherche globale, filtres, historique des modifications (le `audit_log`
  existe déjà), dark mode (déjà le cas), responsive.

---

## 6. Ce qui existe déjà (réutilisable)
- **Auth panel** (super_admin / revendeurs) + `audit_log` → base du Module 10.
- **Annonces** (`app_broadcasts`, catégories, bouton, aperçu) → base du Module 4.
- **Mise à jour forcée** (`kBuildTs`) → preuve du SDUI.
- **AccentController** (couleurs centralisées Flutter) → base du Module 3.
- **Worker + api_v1 + D1 + Pages** déjà déployés en continu sur `claude/**`.

---

## 7. Décisions à acter avant de coder une phase
1. **Correspondance des catégories** : par nom (regex/contains) — confirmer.
2. **Stockage médias bannières** : activer un bucket **R2** (upload) ?
3. **Fréquence de polling** de la config par l'app (ex. 5 min) ?
4. **Analytics** : niveau de détail vs vie privée (anonymisation device_id).

---

*Document vivant — mis à jour à chaque phase livrée.*
