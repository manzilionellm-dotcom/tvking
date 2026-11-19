# Zuno TV — langue de la télévision

Correction préparée dans la PR #113, à partir de la branche app/TV
`ccr-b93e1afd-gwirw0`, commit `7f0903c67b1cb4eda526d192bfbce2a5ee5f9676`.
La production reste gelée. Cette branche ne déploie aucune mise à jour.

## Causes constatées

- Des écrans TV contenaient encore des textes français directement dans le code.
- Le raccourci `boxText` ne distinguait que le français et l'anglais : il
  affichait du français pour les autres langues.
- Le modèle français avait 806 messages ; l'anglais en avait 796, et les
  14 autres langues 761. Les absences entraînaient des replis.
- Certaines erreurs conservaient la phrase déjà traduite dans leur état :
  un changement de langue ne changeait plus ce message.
- Les préférences de langue enregistrées avec une région et les changements
  de langue système devaient aussi être transmis aux services du lecteur.

## Correction

Chaque catalogue contient désormais les mêmes **1 015 messages** : français,
anglais, espagnol, suédois, danois, norvégien bokmål, arabe, swahili, allemand,
italien, portugais, néerlandais, turc, russe, chinois simplifié et hindi.

Les 209 nouvelles clés couvrent notamment les profils, les contrôles parentaux,
les extras, les cartes promotionnelles, les sources et leurs erreurs, les
diagnostics, les enregistrements, les commandes du lecteur et les conditions
d'utilisation. Les catalogues incomplets ont également été complétés.
Le nom du profil automatique est traduit à l'affichage ; les noms personnalisés
restent ceux du client. Les dates, durées et unités utilisent la langue active.
Les boutons du diagnostic audio peuvent revenir à la ligne. Son aide longue
défile avec les rapports à la télécommande, pour rester lisible dans chaque
langue sans réduire la taille du texte.

Le mode **Automatique / Système**, utilisé sans choix manuel enregistré, suit
la langue de la TV au démarrage et après un changement système. Un choix manuel
valide reste respecté. Une préférence ancienne `sv_SE` ou `pt-BR` est reconnue ;
une valeur inconnue revient au mode système. L'arabe active le sens droite-gauche.
Les écrans et erreurs se retraduisent au rendu, sans ouvrir de nouveau le flux.

## MAC déplacée à l'écran en arabe — signalement du 12 octobre

Le QR WhatsApp et les écrans lisaient bien la même chaîne, mais les écrans
héritaient du sens arabe sans préciser celui de la MAC. Une valeur factice
`12:34:AB:CD:56` devient visuellement `AB:CD:56:12:34` dans ce contexte.
Le QR conservait l'ordre stocké : comparer les chaînes seules ne pouvait donc
pas détecter l'erreur. Ce mécanisme reproduit le déplacement observé sur les
captures du propriétaire ; l'hypothèse initiale de deux installations ne
correspond pas à ce signalement.

L'activation, l'accueil, le Direct, les Réglages et la carte d'identifiant
imposent désormais un ordre gauche-droite à la seule MAC. Les libellés arabes
conservent leur sens normal. La génération, le stockage et l'envoi de la MAC
restent inchangés. Aucune association d'appareil n'est migrée automatiquement.

Le message WhatsApp était encore écrit en français dans le code. Il utilise
maintenant les 16 catalogues, avec la MAC sur une ligne ASCII `MAC: …` séparée.
Le sigle latin empêche le déplacement des groupes même dans un message arabe,
sans insérer de caractères invisibles dans le code à copier.

`mac_rtl_test.dart` mesure les positions réelles des caractères : reproduction
du défaut sans correction, écran d'activation arabe, concordance avec les deux
QR et le presse-papiers, conservation de la MAC stockée, changement de langue
du QR et ordre de la ligne MAC dans les deux sens. Les valeurs sont factices. Le rendu utilise la police Ahem du SDK sous les noms
des polices Google pour rester déterministe et sans réseau ; aucune erreur
de chargement de police n’est ignorée. Ce test ne valide pas la typographie
exacte d’une TV physique.

Ce parcours a aussi reproduit un débordement de l’écran d’activation. Les
largeurs des colonnes incluent maintenant les textes, les libellés du QR
peuvent revenir à la ligne et la MAC se réduit seulement si nécessaire.
Les messages de vérification de cet écran utilisent les traductions existantes
au lieu de la fonction française historique.

## Vérification et APK

`python3 android-app/tool/check_l10n.py` contrôle toutes les langues : mêmes clés,
valeurs non vides, absence de doublons, conservation des paramètres. Il refuse
aussi le retour de `boxText`. `flutter gen-l10n` vérifie la grammaire des messages.
Le contrôle fait partie du workflow qualité.

Les tests ciblent les régions et alias, les préférences enregistrées, le mode
automatique et manuel, le changement suédois → arabe d'une erreur ouverte,
les formats allemands, le profil automatique et le rendu des écrans dans
les 16 langues. Les tests existants du dépôt restent dans la même barrière.
Les résultats et le lien du binaire sont consignés dans la PR.

Le workflow `Zuno TV — aperçu langues` fabrique uniquement un APK de test
ARM64, Android 7+, nommé **Zuno Langues — test**, avec le package distinct
`com.sevenmotion.tv.locale.preview` et une signature de débogage. Il ne dispose
pas des secrets de production et ne publie aucune release. Ce binaire permet
une installation à côté de l'app habituelle. Une validation sur télévision
physique reste nécessaire avant toute mise en production.
Ce n'est pas une mise à jour conservant l'identité de l'app habituelle : ses
données sont séparées et sa signature de test peut donner une autre MAC.
Une livraison aux clients devra conserver le package et la signature historiques,
ainsi que les données de l'installation existante.

## Limites précises

- Une langue absente des 16 catalogues utilise la prochaine langue système
  prise en charge, sinon l'anglais. Le chinois traditionnel et le nynorsk
  n'ont pas de catalogues dédiés ; les variantes existantes sont utilisées.
- Les noms de chaînes, titres, descriptions et messages saisis par un fournisseur
  ou un client restent les données reçues. Cette correction ne traduit ni les
  vidéos, ni les conversations, ni les sous-titres externes.
- Les marques, sigles techniques et rapports natifs bruts ne sont pas réécrits.
  Les boutons, aides et intitulés des diagnostics sont traduits.
- La couverture automatique ne remplace pas une relecture linguistique humaine,
  notamment pour les textes longs et les conditions d'utilisation.

## Communication app/panel et production

Les dépôts de données, le protocole de communication, les workers, le lecteur
natif, les identifiants de profil et les configurations de gel restent identiques
à la base. Aucun changement de cadence, endpoint, abonnement ou authentification.
La seule synchronisation ajoutée au lecteur concerne sa préférence de langue.
La fusion et le déploiement demandent toujours l'autorisation du propriétaire
prévue par le gel existant.

## Références techniques

- [Internationalisation Flutter](https://docs.flutter.dev/ui/internationalization)
- [Notification du changement de langue système](https://api.flutter.dev/flutter/widgets/WidgetsBindingObserver/didChangeLocales.html)
- [Langue d'application Android](https://developer.android.com/guide/topics/resources/app-languages)
- [Sens de lecture explicite d'un texte Flutter](https://api.flutter.dev/flutter/widgets/Text/textDirection.html)
- [Algorithme bidirectionnel Unicode](https://www.unicode.org/reports/tr9/)

Ces références expliquent la sélection de langue et le cycle de mise à jour.
Les catalogues et les écrans Zuno doivent explicitement utiliser les messages
traduits ; le système Android ne traduit pas automatiquement un texte en dur.
