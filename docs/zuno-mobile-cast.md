# Cast dans Zuno mobile

Zuno conserve le dernier lecteur et les corrections de la version 109. Sur un
**téléphone ou une tablette Android**, les lecteurs Direct et Films/Séries
proposent le sélecteur Cast de 7 MOTION : mêmes découvertes mDNS/SSDP, même
Google Cast SDK, mêmes transports Google Cast, DLNA et Roku. Sur Windows, les
transports disponibles restent inchangés. Une box ne devient pas un émetteur.

Le plugin local `zuno_cast` compile les trois bridges Kotlin déjà utilisés par
7 MOTION. Il ne recopie pas son activité Android : les callbacks AppForeground
et la gestion audio des derniers builds Zuno restent dans leur activité.
Les listeners de session et le verrou multicast sont libérés à la destruction.

Avant d'ouvrir le sélecteur, le flux du mobile est fermé. Une annulation ou une
déconnexion le reprend ; pendant le Cast, le retour au premier plan et les
reconnexions du lecteur ne peuvent pas rouvrir un deuxième flux. La position
locale d'un film est conservée. La reprise à la position avancée sur le récepteur
n'est pas ajoutée : le moteur Cast existant ne fournit pas cette synchronisation.

## Validation

- Analyse et tests Flutter via `quality-zuno.yml`.
- Tests de sélection téléphone/box, transfert au récepteur, arrêt, annulation et
  ordre des fermetures dans `test/features/tv/desktop/`.
- Compilation Android du pont Kotlin dans l'APK de revue séparé, sans signature
  de production. Un build réussi ne prouve pas la compatibilité de chaque TV.

## Recette avec un téléphone et un récepteur réels

1. Même Wi-Fi : ouvrir une chaîne puis Cast ; retrouver Chromecast/Google TV ou
   le récepteur DLNA/Roku utilisé avec 7 MOTION.
2. Vérifier l'image et le son sur l'écran distant, et l'absence de son/double
   flux sur le mobile. Tester pause, reprise et arrêt.
3. Fermer le sélecteur sans choisir de TV : la lecture mobile reprend.
4. Caster puis changer de chaîne : seule la nouvelle chaîne est transmise.
5. Caster un film ; revenir au mobile puis dans l'app : aucun second flux ne
   démarre pendant la session. À l'arrêt, reprise locale à sa position conservée.
6. Couper le Wi-Fi / éteindre le récepteur : message public, pas d'URL fournisseur.
7. Vérifier une box Android TV : comportement de lecture et gestion Home/Retour
   identiques à Zuno 109, sans commandes Cast émetteur.

Les APK de revue utilisent des packages et signatures de développement séparés.
Ils ne remplacent pas une installation client et ne sont pas des mises à jour
publiées. Valider cette recette avant un build signé et une livraison client.
