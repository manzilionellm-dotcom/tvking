# ZUNO — Samsung Tizen / LG webOS

Client web TV de ZUNO, autonome en HTML/JavaScript, distinct du site Next.js et de l’application Flutter. Samsung utilise AVPlay ; LG et le navigateur utilisent la vidéo HTML5. Cette version couvre le direct via sources M3U/Xtream assignées au panel ; elle ne porte pas toutes les fonctions Flutter (VOD, séries, EPG, DRM, etc.). Aucun média n’est fourni.

## Vérifier et assembler

Depuis ce dossier, Node.js 20+ et Bash :

```sh
node --test tests/smoke.cjs
bash build.sh
```

Le dossier `build/tizen` contient les fichiers de l’application Samsung (pas un paquet signé). Le build vérifie la syntaxe JavaScript et la présence de l’icône. Un assemblage seul ne prouve pas la compatibilité matérielle.

## Signer et installer sur Samsung

1. Installer Tizen Studio avec TV Extension et Samsung Certificate Extension.
2. Dans Certificate Manager, créer ou sélectionner le profil Samsung. Ne jamais envoyer de clé privée dans Git ou dans le chat.
3. Vérifier les identifiants dans `platform/tizen/config.xml` : `ZunoTV2026.ZunoTV` / `ZunoTV2026` sont des identifiants provisoires pour une nouvelle app. Si une fiche Samsung existe déjà, reprendre exactement son identité et son certificat auteur ; augmenter la version pour une mise à jour.
4. Assembler et signer avec le profil local :

```sh
TIZEN_PROFILE=MonProfilSamsung bash build.sh
```

5. Activer Developer Mode sur la TV, connecter via Device Manager / SDB, puis installer le `.wgt` produit :

```sh
tizen install -n ZUNO.wgt -t NOM_CIBLE -- build/tizen
```

Utiliser le nom réel du `.wgt` généré à la place de `ZUNO.wgt`. Pour les tests matériels, inclure le DUID de la TV dans le certificat distributeur lorsque nécessaire. Consulter `submission/SAMSUNG.md` avant tout dépôt.

## Panel et confidentialité

Backend existant : `https://app.7themotion.com` ; heartbeat, statut et sources utilisent les mêmes routes que l’app Flutter. Un identifiant d’installation `MK:…` est mémorisé sous la clé historique `dft.virtual_mac.v1`. Il ne représente pas une MAC réseau et peut changer après effacement des données/désinstallation ; il faudra alors réassocier la licence. Aucun privilège partenaire Samsung n’est requis pour cette identité.

Les réponses bloquées/expirées priment sur `status: active`. Les trois sources éventuelles sont chargées, avec repli si une source échoue. Le statut est revérifié chaque minute pendant le direct. Aucun appel réel au panel ni création de client n’est réalisé par les tests automatisés.

`access origin="*"` autorise les origines réseau du widget ; cela ne garantit pas qu’un fournisseur accepte CORS, TLS, les codecs ou les formats de flux sur toutes les TV. Tester les sources autorisées sur les modèles ciblés. Le navigateur PC n’offre pas AVPlay et ne décode pas nécessairement HLS/TS.

## LG

`build.sh` assemble aussi `build/webos`. La certification LG est séparée ; les icônes spécifiques LG restent à fournir. Aucun paquet `.ipk` ni validation LG ne sont inclus dans cette préparation Samsung.

## Références Samsung

- https://developer.samsung.com/smarttv/develop/guides/multimedia/media-playback/using-avplay.html
- https://developer.samsung.com/smarttv/develop/guides/user-interaction/remote-control.html
- https://developer.samsung.com/smarttv/develop/guides/fundamentals/terminating-applications.html
- https://developer.samsung.com/smarttv/develop/getting-started/setting-up-sdk/creating-certificates.html
- https://developer.samsung.com/tv-seller-office/checklists-for-distribution/launch-checklist.html
