# L'application Android TV officielle — 7 MOTION TV

> Décision du 2026-08-08 : **une seule application TV vendable**.
> Tout le reste (canaux DeFew TV, Seven Cinéma test) est hérité ou de test.

## L'application

| | |
|---|---|
| **Nom** | 7 MOTION TV (Seven Motion TV) |
| **applicationId** | `com.sevenmotion.tv.seven_tv` |
| **Version en ligne** | 0.3.3 (versionCode 1786128274, build du 2026-08-07) |
| **Taille** | 23 Mo (APK universel ARM 32 + 64 bits) |
| **Compatibilité** | Android 5.0+ (minSdk 21), targetSdk 35 — toutes box, Fire TV, sticks 32 bits inclus |
| **Rendu** | Skia (Impeller OFF), Flutter épinglé 3.32.x — anti écran noir/blanc des box |
| **Signature** | Clé maîtresse release (« The Few », RSA 2048, SHA384withRSA, valide → 2053), schémas v1/v2/v3 |
| **SHA-256 certificat** | `51:45:B8:E0:19:F6:D5:FB:96:A2:07:F2:E7:36:73:FD:95:4F:79:99:66:FD:59:88:89:21:15:56:CB:DF:9E:61` |

## LE lien direct (permanent — à donner aux clients)

```
https://github.com/manzilionellm-dotcom/tvking/releases/download/seventv-latest/seven-tv.apk
```

Ce lien pointe **toujours** vers le dernier build publié : le tag
`seventv-latest` est réécrit à chaque publication, l'URL ne change jamais.
Utilisable directement dans l'app Downloader d'une box, sans compte GitHub.

Le manifeste de mise à jour (`version.json` sur la même release) est lu par
l'updater intégré de l'app : les box installées se mettent à jour toutes
seules, par-dessus (même clé de signature), sans harcèlement (garde
anti-retour-arrière, versionCode croissant).

## Comment publier une nouvelle version

1. Actions → **Build 7 MOTION TV (Seven Motion TV)** (`build-seventv.yml`,
   branche `claude/7motion-android-tv-compat-e0rtyp`) → Run workflow avec
   `publish = true`.
2. Le workflow enchaîne : barrière qualité (analyze + tests) → build release
   signé clé maîtresse → publication `seventv-latest` (APK + version.json).
3. Rien d'autre à faire : le lien direct et l'updater in-app suivent.

⚠️ Ne PAS dépingler Flutter 3.32.x et ne PAS réactiver Impeller sans
revalidation sur box réelle ancienne (voir STATUS.md de la branche).

## Carte des canaux TV (état 2026-08-08)

| Canal (tag) | App | Rôle |
|---|---|---|
| **`seventv-latest`** | **7 MOTION TV** | **✅ LE canal officiel vendable** |
| `cinema-test` | Seven Cinéma (DeFew TV) | Test uniquement (« ne pas diffuser ») |
| `tv-prod` | DeFew TV | Hérité — parc installé existant (autre applicationId, ne peut pas migrer vers 7 MOTION TV sans réinstallation) |
| `tv-latest`, `tv-fix-latest`, `cast-fix-tv-latest` | DeFew TV | Ponts de migration vers le canal courant — à supprimer une fois le parc migré |
| `master-console` | Console maître | Outil privé admin (pas une app cliente) |

Les deux lignées TV (7 MOTION TV et DeFew TV) partagent le même code
(`lib/main_tv.dart`) et la même clé de signature ; seule l'identité
(applicationId) diffère. Les nouvelles ventes passent par 7 MOTION TV ;
la lignée DeFew ne reçoit que le suivi du parc déjà installé.
