# Passation — Panel ↔ Worker ↔ App box Zuno (état au 4 octobre 2026)

Tout ce qui suit a été vérifié dans le code ou en production (lecture seule)
le 4 octobre 2026. « NON VÉRIFIÉ » est écrit quand ce n'est pas le cas.

## 1. Où sont les choses

Un seul dépôt GitHub : `manzilionellm-dotcom/tvking`.

| Pièce | Dossier | Techno | En ligne |
| --- | --- | --- | --- |
| App box Android TV / Fire TV « Zuno » | `android-app/` (point d'entrée `lib/main_tv.dart`) | Flutter 3.47, Dart, lecteur natif Media3 dans `packages/native_video_player/` | APK sur la release GitHub `zuno-tv` (clients) |
| Panel revendeur | `android-app/admin-panel/` | React + Vite + TypeScript | `https://tvking-admin.pages.dev` (Cloudflare Pages, projet `tvking-admin`) |
| Backend (« Worker ») | `android-app/cloudflare/` (`worker.js` routes publiques, `api_v1.js` routes du panel, `wrangler.toml`) | Cloudflare Worker `seven-motion-backend` + base D1 `tvking_licensing` | `https://app.7themotion.com` |

## 2. Branches : ATTENTION, deux lignes ont divergé

- **Production (panel + Worker)** = branche `claude/panel-mise-en-ligne`
  (dernier commit `0896028c`, panel mis en ligne le 4 octobre).
- **App box (travail récent)** = branche `ccr-1d45eb8b-x46ieg`, issue de
  `claude/zuno-complet`.
- `main` n'est la source d'aucune des deux productions.
- Les deux lignes se sont séparées le 24 septembre (`fde70596`). 25 fichiers
  ont été modifiés des deux côtés, dont `cloudflare/worker.js`,
  `cloudflare/api_v1.js`, l'abonnement de l'app et l'écran d'activation.
  Ne pas fusionner à l'aveugle.
- Le Worker de la ligne app (`ccr-…`) contient des routes absentes de la
  production : `/api/box/wait` (canal instantané), retraits de listes
  (`revoked`, `source_rev`), `source_revoke.js`. **Il n'est pas déployé.**
  Vérifié en production : `/api/box/wait` → 404, `/api/status` sans `revoked`.

## 3. Comment la box parle au Worker

Adresse compilée dans l'APK : `kSubscriptionBaseUrl`
(`lib/features/subscription/data/subscription_backend.dart`), défaut
`https://app.7themotion.com`, surchargeable par `--dart-define=BACKEND_URL`.

Identité de la box : MAC « `MK:XX:XX:XX:XX:XX` » (MK + 5 octets, dérivée
d'ANDROID_ID, `lib/features/device/data/device_identity.dart`). C'est la clé
de tout côté serveur. Depuis le build #152, la box l'**affiche** sans « MK: » ;
le panel complète « MK: » tout seul.

| Appel de la box | Rôle |
| --- | --- |
| `POST /api/heartbeat` | présence (« Dernière vue »), modèle, version, inventaire des listes sur la TV (« Sur la TV du client · inventaire réel ») |
| `GET /api/status/<mac>` | licence : `exists, status, paid, paid_until, days_left, expired, frozen, banned, trial_until` |
| `GET /api/device-source/<mac>` | listes poussées par le panel (`sources[]`, 1 à 3, déchiffrées) |
| `GET /api/announcement`, `/api/featured`, `/api/home-layout`, `/api/theme`, `/api/pricing`, `/api/app-version`, `/api/ad`, `/api/greeting`, `/api/servers`, `/api/feedback-prompt` | réglages publics posés depuis le panel |

Rythme : `RemoteActivationWatch` (`lib/features/subscription/data/remote_activation_watch.dart`)
essaie le canal long `/api/box/wait` ; en production il répond 404, donc la
box retombe sur la relecture régulière du statut, et relit `device-source` à
chaque tour (sauf si une chaîne joue et que la box a déjà des chaînes).

Règle d'effacement des listes sur la box
(`lib/features/playlists/domain/source_fingerprint.dart`, `fingerprintsToDrop`) :
une liste vue un jour depuis le serveur et qui n'est plus servie est effacée
(chaînes, favoris, récents compris). Présente aussi dans la v106 clients.

Listes sur la box : table SQLite `playlists`. Sur TV, plusieurs listes sont
visibles en même temps ; chacune a un drapeau `hidden`
(`PlaylistRepository.setPlaylistHidden`, masquer / réafficher instantané,
sans retéléchargement). **Le panel ne sait pas encore piloter ce drapeau.**

## 4. Comment le panel parle au Worker

Routes `/api/v1/*`, authentifiées (session du panel, `admin-panel/src/lib/api.ts`).

| Action panel | Route |
| --- | --- |
| Fiche appareil (licence, présence, listes poussées déchiffrées, inventaire TV) | `GET /api/v1/devices/:id/overview` |
| Pousser 1 à 3 listes | `PUT /api/v1/sources/:mac` `{sources:[…]}` — **remplace l'ensemble** |
| Effacer les listes poussées | `DELETE /api/v1/sources/:mac` |
| Bouton « Supprimer » par liste (en ligne depuis le 4/10) | renvoie les autres listes par `PUT`, ou `DELETE` si c'était la dernière (`admin-panel/src/lib/sources.ts`) |
| Activer / prolonger | `POST /api/v1/activate` ; essai : `POST /api/v1/trial-extend` |
| Annonces | `/api/v1/announcements` |

Le Worker de production ne garde, pour chaque liste, que
`type, label, server_url, username, password, m3u_url, epg_url`
(`normalizeSource` dans `api_v1.js`). **Tout autre champ est supprimé.**
Mots de passe et URL M3U sont chiffrés en base (`SOURCE_ENCRYPTION_KEY`).

## 5. Mises en ligne

- **Panel / Worker** : workflow `.github/workflows/deploy-panel-cloudflare.yml`
  (sur la branche `claude/panel-mise-en-ligne`), lancement manuel, entrée
  `confirme = DEPLOYER`, `cible = worker-puis-panel | worker-seul | panel-seul`,
  `mac_reference` relue avant/après. Secrets `CLOUDFLARE_API_TOKEN`,
  `CLOUDFLARE_ACCOUNT_ID`.
  - Run #3 (4/10, `panel-seul`) : vert.
  - Run #2 (3/10) : **échec à l'étape « DÉPLOYER le Worker »**, cause non
    analysée. À comprendre avant tout nouveau déploiement du Worker.
- **App box** : workflow `.github/workflows/build-zuno-tv.yml`
  (`publish`, `play_aab`, `test_box`, `backend_url`, `variante`).
  - `test_box=true` → release `zuno-tv-test` (box de test, jamais les clients).
  - `publish=true` (sans `test_box`) → release `zuno-tv` = **tous les clients**.
  - Signature obligatoire : certificat SHA-256
    `5145b8e019f6d5fb96a207f2e73673fd954f799966fd598889211556cbdf9e61`.
  - Numéro visible : chaque publication client prend le suivant (106 → 107…),
    un build de test s'appelle `107-test.<run>`.
  - Mise à jour dans l'app : lit `zuno-tv/version.json` (le build de test lit
    aussi `zuno-tv-test`), exige `sha256` et `size`.
- **AAB Google Play** : `play_aab=true` → minSdk 24, permission d'installation
  retirée. Package `com.sevenmotion.tv.seven_tv`, test fermé en cours.

## 6. Règles du propriétaire (non négociables)

- Jamais `publish=true` sans son ordre écrit ; jamais de push sur `main`.
- Ne pas toucher la release `zuno-tv` (clients), `phone-latest`, le 4K Player.
- Ne supprimer aucune branche, PR ou run.
- Chaque changement de comportement garde un interrupteur de repli coupé par
  défaut (`lib/core/app/repair_flags.dart`, `BoxFlag`).
- Commentaires en français, pas de `print()`, aucune URL de flux ni mot de
  passe dans le code, les tests ou les journaux.
- Dire « ça marche » seulement avec la commande exécutée qui le prouve.

## 7. Commandes de vérification

```bash
# App
cd android-app && flutter analyze && flutter test        # 415 verts au 4/10
# Panel
cd android-app/admin-panel && npm ci && npm test && npm run build   # 20/20
# Worker
cd android-app/cloudflare && node --check worker.js && node --check api_v1.js
```

Workflow `e2e-panel-box.yml` (branche du panel) : tests panel ↔ box, vert au 4/10.

## 8. Travail non terminé (à préciser par le propriétaire)

- Bouton « Activer / Désactiver » une liste depuis le panel : demande que le
  Worker garde un champ en plus, que la box applique `hidden`, et un bouton
  panel. Les box v106 ignoreront le champ.
- Retirer depuis le panel une liste ajoutée par le client lui-même : demande
  les « retraits » (`revoked`) du Worker de la ligne app.
- Faire converger le Worker de production et celui de la ligne app (canal
  instantané, retraits, bannières `/api/banners` qui n'existe nulle part).
- Écran noir après environ 1 min et son dégradé sur la box : correctifs
  posés, cause réelle NON VÉRIFIÉE (journaux de la box attendus).
- Essai gratuit de 7 jours alors que le test fermé Google dure 14 jours.

Documents utiles : `docs/AUDIT-ZUNO-TV-2026-10.md`,
`docs/PANEL-BOX-CARTES-ACCUEIL.md`, `docs/patches/`.
