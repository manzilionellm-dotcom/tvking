# ROLLBACK-PLAN — Stratégie de retour arrière

## Principes

1. **Aucun canal de production n'est modifié par cet audit.** Les canaux
   clients (`prod`, `tv-prod`, `prive-latest`, `tizen-latest`,
   `windows-latest`) restent pointés sur le build #1260
   (commit `a8a428e`, branche `claude/maison-mere-phone`). Les livrables
   de cet audit partent sur les canaux de TEST (`phone-test`,
   `cinema-test`), invisibles de l'updater in-app (pas de version.json).
2. **Chaque groupe de corrections = un commit dédié** sur
   `claude/audit-mobile-tv-delivery-ghn12o`, avec tests. Un `git revert`
   du commit fautif suffit à annuler un groupe sans toucher au reste.

## Points de restauration

| Quoi | Référence | Usage |
|---|---|---|
| Ancien contenu de la branche d'audit (app web TV Next.js) | `dd7e468` (= `origin/main`) | `git checkout -B claude/audit-mobile-tv-delivery-ghn12o dd7e468 && git push -f` |
| Canonique mobile avant audit | `origin/claude/usine-app-v3-iptv-mjbjts` (`37220df`) | base de re-départ mobile |
| Canonique TV avant audit | `origin/claude/integration-tv-quality-merge-on11p3` (`87d9ef2`) | base de re-départ TV |
| Fusion de départ de l'audit (avant toute correction) | `25d7cb3` | annule TOUTES les corrections de l'audit |

## Rollback des applications installées

- **Téléphone (test)** : réinstaller l'APK du canal souhaité — le
  `phone-test` précédent a été écrasé, mais l'APK de prod reste :
  https://github.com/manzilionellm-dotcom/tvking/releases/download/prod/7motion.apk
  Même clé de signature (clé maîtresse) → installation PAR-DESSUS sans
  désinstallation, données locales conservées.
- **Box TV (test)** : idem avec le canal prod TV :
  https://github.com/manzilionellm-dotcom/tvking/releases/download/tv-prod/defew-tv.apk
- Aucune migration de base locale introduite par cet audit ne casse le
  retour arrière (pas de changement de schéma SQLite dans ces correctifs).

## Rollback CI/livraison

- Les workflows modifiés dans cet audit sont versionnés dans le même
  commit que leur justification ; `git revert` du commit restaure le
  comportement antérieur.
- En cas de release de test corrompue : relancer
  `publish-phone-test.yml` / `publish-cinema-test.yml` avec le `run_id`
  d'un build antérieur vert (le tag est écrasé à chaque publication).

## Vérification après rollback

1. `flutter analyze --no-fatal-infos --no-fatal-warnings` → 0 erreur.
2. `flutter test` → suite verte (CI `Quality`).
3. Dispatch `build-android.yml` + `build-tv.yml` sur la réf restaurée →
   artefacts produits.
4. Installer l'APK sur appareil : démarrage, navigation, lecture.
