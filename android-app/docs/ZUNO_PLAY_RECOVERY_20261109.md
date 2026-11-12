# ZUNO : reprise de publication Google Play

État vérifié le 9 novembre 2026. Paquet concerné : `com.sevenmotion.tv.seven_tv`.
Ce document prépare les corrections ; il ne constate ni une approbation Google,
ni la publication d'un nouveau bundle.

## Déclaration du service au premier plan

Dans Play Console, **Contenu de l'application → Autorisations pour le service de
premier plan**, une déclaration est signalée en retard. La liste des bundles
concernés inclut bien **1793630235 (113)**, importé le 7 novembre et en examen.
La permission détectée est `android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK`.

Le manifeste du plugin `packages/zuno_cast/android/src/main/AndroidManifest.xml`
déclare `PlaybackForegroundService`, de type `mediaPlayback`. Le plugin ne
démarre ce service que sur téléphone. `CastManager._updateRelayKeepAlive()` le
demande lorsqu'un relais local alimente la TV et le coupe lorsque ce relais
n'est plus utilisé. Un Cast direct ou via le proxy distant ne suffit donc pas
à démontrer ce service.

Texte de travail, à confirmer avec le bundle réellement soumis et la vidéo :

> ZUNO est un lecteur multimédia. Lorsque l'utilisateur lance une lecture sur
> un téléviseur et que le téléphone relaie le flux, le service maintient cette
> lecture pendant que l'utilisateur passe à une autre application ou éteint
> l'écran du téléphone. Une notification indique la lecture en cours. Retarder
> ou interrompre le service peut interrompre le flux et la lecture demandée.
> Le service est lié à la session de lecture et s'arrête à la fin du relais.

Choisir l'usage correspondant au comportement réellement filmé. Ne pas cocher
« Picture-in-picture » sur la seule présence de l'attribut PiP du manifeste :
il faut montrer que cet usage utilise effectivement le service déclaré.
Le mode Écouteurs du lecteur historique n'est pas une preuve de disponibilité
dans l'entrée `main_tv.dart` utilisée par ce bundle.

Google demande un lien vers une **vraie vidéo** montrant le déclenchement de
chaque fonction déclarée. Aucun lien de démonstration n'a été fourni ni validé.
Pour la session Cast en relais :

1. Installer la version soumise sur un téléphone et ouvrir un contenu de test
   dont on possède les droits ; masquer les identifiants et les données privées.
2. Filmer le lancement manuel de la lecture et la sélection du téléviseur.
3. Vérifier que le téléphone relaie effectivement le flux et que la notification
   du service apparaît, puis montrer que la TV continue pendant que ZUNO passe
   en arrière-plan sur le téléphone.
4. Arrêter la session depuis ZUNO ; montrer la fin du relais et la disparition
   de sa notification. Vérifier le comportement réel, sans le simuler.
5. Fournir une URL de vidéo accessible au réviseur sans demande d'accès, puis
   compléter la déclaration et vérifier son état dans l'aperçu de publication.

Source : [exigences officielles Google Play](https://support.google.com/googleplay/android-developer/answer/13392821).
La déclaration manquante est un point à corriger ; elle ne prouve pas à elle
seule la cause de tout le délai d'examen. Ne pas annuler la soumission en cours
pour simplement refaire le même import.

## Compteurs de la prochaine livraison

| Référence vérifiée | Nom | versionCode |
| --- | --- | --- |
| Production Play | 109 | 1791125397 |
| Bundle Play importé, en examen | 113 | 1793630235 |
| APK public `zuno-tv` | 116 | 1793725266 |
| APK de test `zuno-tv-test` | 117-test.539 | 1793858522 |
| Prochain bundle préparé par ce correctif | 117 | 1793858523 |

Le nom 113 ne signifie pas que son code source est plus ancien : le build Play
113 et l'APK de test 117 ont été construits à partir de
`4e8d977481bc15813431ff673753d11a7425d9a6`. Le compteur Android, lui, doit
dépasser celui déjà installé. Le correctif conserve la référence de production
109, consigne l'import 113 et dépasse le dernier APK signé connu.

Avant de construire, vérifier de nouveau les imports Play et les deux manifestes
de release : si un autre APK du même paquet a été signé depuis, reporter son
compteur avant de choisir le prochain code. Une signature de mise à jour
compatible reste nécessaire ; un compteur supérieur ne la remplace pas.

- [Build Play 113](https://github.com/manzilionellm-dotcom/tvking/actions/runs/41975564072)
- [Validation du build de test 117](https://github.com/manzilionellm-dotcom/tvking/actions/runs/41975568911)
- [Manifest APK public](https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-tv/version.json)
- [Manifest APK de test](https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-tv-test/version.json)

La configuration de gel et les contrôles de signature restent applicables.
La fusion de cette préparation ne vaut ni recette sur appareil, ni autorisation
de promouvoir un APK de test vers le lien des clients, ni soumission Play.

## Lien de téléchargement

`zuno.7themotion.com` répondait NXDOMAIN lors du contrôle. Vercel reconnaît le
domaine dans le projet `tvking` mais le déclare mal configuré. Le compte
Cloudflare connecté ne contient pas la zone `7themotion.com`.

Dans le compte qui gère réellement cette zone, ajouter le CNAME `zuno` vers la
cible affichée par Vercel pour ce projet (cible relevée :
`e9b5b9b2efaf1d5c.vercel-dns-017.com`), en DNS seul pour la vérification initiale.
Vérifier ensuite la résolution, le certificat HTTPS et la redirection `/apk`.
Ne pas recréer la zone ni changer les serveurs de noms du domaine.

Le lien temporaire vérifié `https://tvking.vercel.app/apk` redirige vers l'APK
public **116**. Il ne distribue pas le test 117. Ce défaut DNS affecte le
téléchargement direct ; aucune preuve ne le relie au délai d'examen Play.

## Confidentialité

La page publique `https://api.zuno8k.com/privacy` utilise encore le nom The Few.
Le correctif de marque doit partir de la branche du backend actuellement en
production, `release/atlas-console-20261029`, et préserver les fonctions Atlas.
Une correction du nom n'est pas une validation du contenu complet de la
politique ou du questionnaire Sécurité des données.
