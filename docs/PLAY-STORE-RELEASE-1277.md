# Publication Play Store — 7 MOTION build 1277

Checklist de mise en ligne du build **1277** (canal Tests fermés – Alpha), puis passage en Production.

## Artefact vérifié

| Élément | Valeur | Statut |
|---|---|---|
| Fichier | [`7motion.aab`](https://github.com/manzilionellm-dotcom/tvking/releases/download/phone-test/7motion.aab) (≈ 126 Mo) | ✅ en ligne |
| Package | `com.manzilionellm.tvking` | ✅ vérifié dans le manifest du bundle |
| versionCode | **1277** | ✅ vérifié dans le manifest du bundle |
| versionName | 0.3.3 | ✅ |
| CI | Run [30526026836](https://github.com/manzilionellm-dotcom/tvking/actions/runs/30526026836), run_number 1277, commit `47856f4` | ✅ success |
| Signature | Alias `sevenmotion` (`SEVENMOT.RSA`), CN=The Few, SHA-256 `51:45:B8:E0:19:F6:D5:FB:96:A2:07:F2:E7:36:73:FD:95:4F:79:99:66:FD:59:88:89:21:15:56:CB:DF:9E:61` | ✅ même clé que le build 1260 accepté |

Aucune signature manuelle à faire : Play App Signing re-signe automatiquement à l'import.

## Étapes — canal Alpha (Tests fermés)

1. Ouvrir [Google Play Console](https://play.google.com/console) → appli **7 MOTION**.
2. Menu gauche → **Tests** → **Tests fermés** → ouvrir la piste **Alpha**.
3. Cliquer **Créer une version**.
   - Si la console bloque parce que la 1260 est encore en brouillon/examen : ouvrir la version 1260 → **Supprimer les modifications**, puis recommencer « Créer une version ».
4. Section **App bundles** → **Importer** → sélectionner `7motion.aab` téléchargé depuis le lien ci-dessus.
5. **Vérifier que le code de version affiché est 1277** (surtout pas 1260).
6. Notes de version (si demandé) : « Corrections de stabilité et d'affichage ».
7. **Enregistrer** → **Vérifier la version** → **Envoyer pour examen** (bouton parfois dans « Aperçu de la publication »).

## Étapes — Production

- Compte développeur personnel récent : Google exige **14 jours consécutifs** de test fermé avec **≥ 12 testeurs** avant d'ouvrir la Production.
- Le compteur suit le **canal Alpha**, pas le build : importer la 1277 ne remet pas le compteur à zéro.
- Une fois les 14 jours atteints : **Tableau de bord** → **Demander un accès en production** → répondre au questionnaire → soumettre.
- Puis créer une version **Production** avec le même `7motion.aab` (1277).

## Regénérer un build si besoin

1. Lancer le workflow **Build Android APK** sur la branche `claude/salut-4nby1y` (produit l'artefact `7motion-playstore-aab-*`, .aab signé).
2. Lancer le workflow **Publish Phone test APK** (dispatch avec le `run_id` du build) pour republier le lien direct `.../phone-test/7motion.aab`.
3. Re-vérifier le versionCode avant tout envoi.
