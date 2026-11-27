# Passation ZUNO LAB — 28 novembre 2026

## Point de départ
Branche `lab/zuno-119-qualification-20261128`, issue directement de `a096b2f85de082622ec232fa198069bdefbbccab` (branche officielle `ccr-b93e1afd-gwirw0`). Le [run 45710084378](https://github.com/manzilionellm-dotcom/tvking/actions/runs/45710084378) a terminé avec succès. L’AAB signé de l’édition auto a pour SHA-256 `43fcccd171434d18961a2c27aeed8064ab2f08aeffcf7364f0ae439560fa149d`. Version 119, code 1794559152, paquet `com.sevenmotion.tv.seven_tv`, minSdk 24. L’archive Actions a une empreinte différente. Dernier statut Play rapporté le 27 novembre : en cours d’examen. Distribution actuelle INCERTAINE.

| Cible | État initial |
|---|---|
| Play | Version et piste effectivement servies à relever |
| Témoin | AAB authentifié. Aucun APK installé ni chronométré à l’ouverture de la campagne |
| Candidat | Construction sous identité LAB distincte en préparation |
| Diagnostic instrumenté | Aucun binaire soumis à une mesure |
| Matériel | Aucune SHIELD, petite box ou capture de dalle connectée à cet espace |

## Prochaine vérification
Sur la machine Android du banc, exécuter `adb devices -l` puis inventorier les APK installés avec `adb shell pm path com.sevenmotion.tv.seven_tv`. Relire tous les octets avant toute attribution. Pour la preuve visuelle, consigner l’identité de la chaîne et deux compteurs croissants. Aucun classement ni livraison à ce stade.
