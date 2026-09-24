# 7 MOTION TV — APK rebrandée (base 4K Player)

Ce dossier contient l'APK **7 MOTION TV**, découpée en 2 morceaux parce que
GitHub refuse tout fichier de plus de 100 Mo dans le dépôt.

- Base : l'APK de la release `apk-reference` (4K Player, `com.manthefew`).
- Modifié : nom affiché « 7 MOTION », icône, bannière Android TV et logo
  intérieur remplacés par le logo 7 MOTION. Rien d'autre n'est touché
  (lecteurs, écrans, disposition identiques).
- Signée avec la clé **7 MOTION** du propriétaire (alias `sevenmotion`,
  SHA-256 du certificat `7d6d74d1…93372`). La clé n'est PAS dans le dépôt
  (dépôt public) : elle est gardée hors ligne par le propriétaire.

Le workflow `.github/workflows/publish-7motion-tv.yml` recolle les morceaux,
vérifie l'empreinte et publie l'APK dans la release `7motion-tv` :
`https://github.com/manzilionellm-dotcom/tvking/releases/download/7motion-tv/7motion-tv.apk`

Recoller à la main : `cat 7motion-tv.apk.part0 7motion-tv.apk.part1 > 7motion-tv.apk`
(Windows : `copy /b 7motion-tv.apk.part0+7motion-tv.apk.part1 7motion-tv.apk`).

SHA-256 attendu de l'APK :
`2005629560625644b4fe1f333a8283d5cb37ab42feb7d560cacd7a55c5f40be4`
