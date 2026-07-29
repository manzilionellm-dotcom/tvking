# DEPENDENCIES-AUDIT

Date : 2026-07-29 · `flutter pub get` OK · `flutter pub outdated` relevé.

## Runtime — dépendances directes notables

| Paquet | Rôle | Verrou / note |
|---|---|---|
| media_kit / media_kit_video / media_kit_libs_* | Lecteur MOBILE (libmpv) | **RETIRÉ du build TV** par build-tv.yml — invariant verrouillé par test (`tv_media_kit_import_guard_test`) |
| native_video_player (packages/) | Lecteur TV (ExoPlayer) | plugin local, chemin TV |
| ffmpeg_kit_flutter_new_min | Conversion .ts→.mp4 (enregistrements) | impose minSdk 24 (téléphone) ; **retiré du build TV** (minSdk 21) |
| sqflite / sqflite_common_ffi | Stockage local | FFI utilisé par les tests |
| http | M3U + Xtream + EPG | client IPTV custom (certs auto-signés confinés, DoH) |
| flutter_localizations / intl | i18n 8 langues | intl **épinglé 0.20.2** (contrainte du SDK stable) |
| firebase_core / firebase_crashlytics | Crash reporting optionnel | l'app tourne SANS Firebase |
| wakelock_plus, connectivity_plus, cached_network_image, xml, archive, local_auth, flutter_local_notifications, timezone | support | — |

## `pub outdated` — synthèse

30 dépendances contraintes en-deçà d'une version résolvable. Les montées
majeures sont **bloquées volontairement** (au backlog B-4) : elles cassent
des API et impactent les DEUX apps (mobile + TV) partageant le même pubspec —
une montée doit être validée par compilation + tests des deux cibles, ce qui
dépasse le périmètre d'un lot de correctifs.

Majeures notables en attente : `media_kit_video` 1.3→2.0 (API lecteur —
risque écran noir, à valider sur appareil), `flutter_local_notifications`
18→22 (déjà source d'un crash R8 corrigé par ProGuard — montée à haut
risque), `firebase_*` 3→4/5, `local_auth` 2→3, `connectivity_plus` 6→7,
`archive` 3→4, `xml` 6→7, `intl` figé par le SDK.

## Décisions de cet audit

- **Aucune montée de version** appliquée : le gain (surface de sécurité déjà
  faible — 3 deps runtime réseau, toutes derrière des clients custom testés)
  ne justifie pas le risque de régression du lecteur sur les deux plateformes
  dans un lot de correctifs. Reporté à un lot dédié (B-4) avec validation
  appareil.
- **Pas de SBOM/osv-scanner** ajouté en CI dans ce lot (B-9 : à poser une
  fois le lockfile commité — cf. ci-dessous).
- **pubspec.lock** : non commité à ce jour (B-8). Recommandation : le
  commiter pour des builds reproductibles (impacte mobile ET TV → validation
  client avant de figer).

## Vérifications faites

- `flutter pub get` : résolution OK, aucun conflit.
- Aucune dépendance discontinue bloquante sur le chemin runtime critique.
- Aucun `package:media_kit` dans la fermeture d'imports TV (194 fichiers).
