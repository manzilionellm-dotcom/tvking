# Zuno Windows : compilation et livraison

Le workflow `.github/workflows/build-zuno-windows.yml` compile `main_windows.dart`
avec Flutter 3.47.7 sur `windows-2022`. Il conserve les gardes existantes :
propriétaire du dépôt, branche autorisée, environnement `zuno-app-production`
et gel `.github/app-production.json`. Une compilation n'autorise aucune publication.

`package.ps1` produit le bundle complet (Flutter, libmpv, données et runtime
Visual C++ x64), `Zuno-Setup.exe`, `zuno-windows.zip`, `version.json`,
`build-manifest.json` et `SHA256SUMS.txt`. Le manifeste porte le commit exact.
Le bouton de mise à jour PC lit `zuno-windows/version.json` ; il ne peut pas
découvrir une nouvelle version si ce fichier n'a pas été publié.

## Signature

Pour un certificat Authenticode existant dont la clé est légalement exportable,
configurer dans l'environnement protégé, sans les écrire dans le dépôt :

| Configuration | Type | Contenu |
| --- | --- | --- |
| `WINDOWS_SIGNING_CERTIFICATE_BASE64` | Secret | PFX du certificat réel, encodé en base64 |
| `WINDOWS_SIGNING_CERTIFICATE_PASSWORD` | Secret | Mot de passe du PFX, s'il en possède un |
| `WINDOWS_SIGNING_CERTIFICATE_THUMBPRINT` | Variable | Empreinte SHA-1 du certificat attendu (40 caractères), pas de l'exécutable |

L'empreinte SHA-1 sélectionne le certificat ; les signatures de fichiers et
horodatages utilisent **SHA-256**. L'app, l'installeur et le désinstalleur sont
signés et horodatés. SignTool vérifie la chaîne de confiance Authenticode (`/pa`),
l'identité attendue et l'horodatage. Le PFX temporaire et la clé importée sont
retirés à la fin. Aucun certificat autosigné n'est créé ni ajouté aux racines.

Une clé sous HSM ou un service Microsoft Artifact Signing doit conserver son
mode de protection : ne pas l'exporter pour remplir ces secrets. Il faudra
configurer son fournisseur de signature avant de livrer avec ce mode.

Sans configuration de certificat, le workflow peut produire un **artefact de
revue non signé**, identifié ainsi dans son manifeste et son résumé. Une
publication `publish=true` échoue avant compilation sans configuration et exige
ensuite la preuve de signature, les empreintes des paquets et le commit exact.
La signature ne lève pas le gel de publication et ne garantit pas l'absence
de toute alerte SmartScreen, qui dépend aussi de la réputation.

## Vérification Windows

Après création des vrais paquets, `verify-package.ps1` :

1. contrôle les manifestes, les SHA-256 et tous les fichiers du ZIP ;
2. vérifie les signatures quand elles existent et refuse un exécutable altéré ;
3. installe dans un répertoire temporaire avec `/CURRENTUSER` et
   `/LAUNCHAFTERUPDATE=0`, puis compare le bundle installé ;
4. contrôle le désinstalleur et désinstalle le paquet.

Le test ne lance pas Zuno et ne crée pas d'appareil sur le panel. Il ne remplace
pas un essai de lancement, lecture vidéo et Cast sur un véritable PC. Ces scripts
doivent passer sur le runner Windows ; une analyse YAML sur Linux ne suffit pas.

Le domaine de l'installeur est `https://zuno.7themotion.com`. Le raccourci `/pc`
doit être vérifié après une publication autorisée : ne pas présenter l'ancienne
release comme la nouvelle version et ne pas annoncer un lien non testé.

Références primaires :

- [Bundle Windows Flutter](https://docs.flutter.dev/platform-integration/windows/building)
- [SignTool et vérification Authenticode](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool)
- [Horodatage Authenticode](https://learn.microsoft.com/en-us/windows/win32/seccrypto/time-stamping-authenticode-signatures)
- [Signature Inno Setup](https://jrsoftware.org/ishelp/topic_setup_signtool.htm)
