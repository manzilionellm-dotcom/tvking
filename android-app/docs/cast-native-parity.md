# Provenance native Cast de 7 MOTION dans Zuno

Le constructeur téléphone `.github/workflows/build-7motion-sport-test.yml`
repart du commit `37fdf3305c5de9d35e20fd6567df38008fc7a7ee`, puis applique
les correctifs mobiles. Les fichiers natifs ci-dessous ne sont modifiés par
aucun de ces correctifs. Zuno compile leurs copies depuis
`android-app/android_overlay/google_cast/` via son plugin `zuno_cast`.

| Fichier source dans le commit téléphone | Objet Git source | SHA-256 source |
| --- | --- | --- |
| `android_overlay/google_cast/GoogleCastApi.kt` | `65246dad0608563a1560d87daa9750b08029fcc4` | `195dcdf389a6e56aad1d54ee7d92340a22b3d19085005c28f27a20bb846ea27a` |
| `android_overlay/google_cast/PlaybackForegroundService.kt` | `0587672d3055520225aafb124fd1e4ca4bab7bbc` | `8ac400b9c17693d6503818004ca5ce89b19fe273754f573ed38886211bca600f` |

`PlaybackForegroundService.kt` est identique octet pour octet au fichier
source : notification, verrous CPU/Wi-Fi et extras localisés sont conservés.

`GoogleCastApi.kt` reprend les commandes, callbacks et bascules de récepteur
de 7 MOTION. Sa seule adaptation est `dispose()`, nécessaire au cycle de vie
du plugin Zuno : retrait des listeners, du handler Flutter et des callbacks
différés, sans commande Stop ni déconnexion du récepteur. Cette méthode
existait déjà dans le plugin Zuno ; elle annule aussi les rappels de bascule
introduits par le bridge téléphone afin de ne pas réutiliser une activité
détachée.

Cette reprise n'implique aucune modification du bouton Cast, des écrans ou
de l'activité principale Zuno. L'égalité des sources ne remplace pas une
recette sur un récepteur physique, notamment le passage en arrière-plan,
l'écran éteint et le repli du proxy distant vers le relais HLS local.

## Intégration au cycle de vie Zuno

- Le plugin compile aussi `PlaybackForegroundService.kt`, déclare son service
  et ses permissions, et expose `startBackgroundAudio` / `stopBackgroundAudio`
  sur le canal PiP existant. Le service reste attaché au moteur pendant une
  rotation ; son arrêt libère les verrous.
- `PipService` reprend le contrat 7 MOTION : résultat booléen réel, corps de
  notification Cast et libellés localisés. Un bridge absent ne vaut pas succès.
- Une suspension SDK conserve la passation au récepteur. `resumed` rétablit
  l'état actif ; `resume_failed` termine le relais et libère le lecteur local.
- Quitter le lecteur ne déconnecte plus une session établie. Une nouvelle vue
  reçoit le verrou Cast avant sa première URL, sans créer une deuxième
  connexion au fournisseur ni changer la chaîne sur la TV.
- Les messages facultatifs du sélecteur ne relisent plus un contexte retiré
  et ne font pas échouer le Cast lorsque le shell n'a pas de `Scaffold`.

Le corps de `DesktopCastControls.build()` est strictement identique à celui
du commit `31bfa72d6a90c7614c2712d1b8921fa47446dec6`. Les adaptations ci-dessus
concernent la technique et le cycle de vie ; elles ne remplacent pas le bouton.

## Vérifications

Les tests de régression couvrent la passation locale, les interruptions et
échecs de reprise SDK, la fermeture du sélecteur, le changement de route,
l'ordre des commandes natives et le contrat du service en arrière-plan.
Ils utilisent des canaux et transports simulés, sans flux fournisseur.

Contrôles locaux exécutés : cohérence des 16 catalogues de traduction,
syntaxe XML du manifeste, absence d'erreurs d'espacement dans le diff,
comparaison du bouton et empreintes des sources natives.

Flutter, Dart, Gradle et Kotlin ne sont pas installés dans cet environnement.
Les tests ajoutés, l'analyse Flutter et la compilation Android restent donc
à exécuter. Aucun essai physique téléphone / Cast n'a été effectué. Une
validation réelle doit inclure lecture prolongée, Home, écran éteint,
retour au lecteur, perte / reprise Wi-Fi et arrêt explicite.
