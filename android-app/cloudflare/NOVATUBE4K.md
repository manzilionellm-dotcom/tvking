# NOVATUBE 4K dans Atlas

Le client Android `com.manthefew` utilise son propre circuit d'activation
`app_novatube4k`. L'administrateur conserve les écrans Atlas existants :
**Appareils**, **Activer une box**, puis **Chaînes**.

## Identité et activation

- La MAC 4K d'origine reste conservée sur l'appareil et dans le libellé de sa
  fiche. L'identifiant Atlas affiché par l'app est `MK:` suivi des cinq premiers
  octets de SHA-256 de `novatube4k:` + MAC brute canonique en majuscules.
- L'installation génère une clé aléatoire privée de 32 octets. Seul son hash
  est enregistré dans la nouvelle table `novatube4k_devices`.
- Le premier enregistrement crée atomiquement une fiche et une licence
  inactive expirée à zéro. Il ne crée aucun essai ni activation automatique.
- La route existante `/api/v1/activate` reconnaît les MAC inscrites par ce
  circuit et affecte leur licence à `app_novatube4k`. JWT, origine, droits,
  appartenance revendeur et idempotence restent contrôlés par l'API existante.
- Cette activation du lecteur ne déclenche pas le hook de fourniture Gold.
  Les autres appareils conservent leur chemin historique.

## API de l'appareil

Trois requêtes POST JSON sous `/api/novatube4k/` :

| Route | Corps | Effet |
| --- | --- | --- |
| `register` | `{raw_mac}` | Inscription inactive ou reprise avec la même clé |
| `state` | `{raw_mac}` | État de la licence dédiée et listes autorisées |
| `ack` | `{raw_mac,source_rev,applied:true,app_version}` | Reçu après sauvegarde locale des profils |

Toutes utilisent `X-Device-Key` (64 caractères hexadécimaux minuscules).
Ni le secret admin ni un jeton de panel ne sont présents dans l'APK.
Une mauvaise clé ne peut pas réclamer une fiche existante. `state` et `ack`
n'inscrivent jamais un appareil inconnu.

Le statut tient compte de la licence de cette app, de sa date de fin, de
`apps.is_active` et des gels/bannissements. Une licence d'une autre application
ne donne aucun accès. Les anciennes routes publiques basées seulement sur la
MAC sont refusées pour les nouvelles fiches NOVATUBE ; les sous-appels de
lecture sont internes, après validation de la clé et de la licence.

Les sources M3U/Xtream sont déchiffrées par le handler déjà utilisé par Atlas.
La réponse dédiée leur ajoute si nécessaire des identifiants stables, sans
modifier le store partagé. Un changement de libellé ou de mot de passe Xtream
ne change pas l'identité du profil. `sources_ok:false` signifie qu'il faut
conserver la dernière configuration locale, et non supprimer les listes.

Le reçu `config_saved` confirme les profils validés et sauvegardés sur la box,
pas la disponibilité du fournisseur ni une lecture vidéo. Il ne valide que
les ordres `source` et `source_clear` de la révision courante réellement servie.
Les ordres `activate`/`renew` conservent leur état de suivi historique ;
l'ouverture du lecteur dépend du statut de licence lu par l'appareil.

## Vérification et publication

- `node --test novatube4k.test.mjs` : contrat et transactions D1/SQLite.
- `node --test novatube4k-wrapper.test.mjs` : routes réelles du panel,
  autorisations, idempotence, isolation, sources et reçus.
- `NOVATUBE4K_TEST_ENTRY=/chemin/novatube4k-live-entry.js node --test
  novatube4k-wrapper.test.mjs` : mêmes contrôles sur le candidat exact.
- `node novatube4k.workerd.mjs` : runtime Workers, D1 et Durable Object locaux,
  date de compatibilité de production et réseau sortant interdit.

`novatube4k-entry.js` est l'entrée reproductible depuis les sources du dépôt.
Pour la première publication, `prepare_novatube4k_release.py` applique le pont
au bundle déjà en production, dont l'empreinte et la version sont exigées.
Tous les corps des fonctions historiques restent identiques. Seuls des
exports internes sont ajoutés pour injecter les helpers. La publication doit
conserver les bindings et la classe `RealtimeHub` existants, sans migration
de Durable Object et sans remplacer les secrets.

## Conservation de l'installation

La mise à jour Android conserve le package, la clé de signature dédiée et les
préférences. L'effacement des données détruit la clé privée d'installation :
une nouvelle clé est alors refusée sur l'ancienne fiche. Le candidat de
réassociation ajoute un code d'assistance temporaire affiché par l'appareil,
un aperçu administrateur et une approbation explicite. Il remplace uniquement
la clé après vérification transactionnelle ; il ne recrée pas la fiche et ne
change ni licence, ni expiration, ni sources, ni crédits.

Le contrat et les limites sont décrits dans [NOVATUBE_RECOVERY_CONTRACT.md](NOVATUBE_RECOVERY_CONTRACT.md).
La présence du code dans le dépôt ne signifie pas que le Worker, le panel et
l'APK correspondants sont déjà publiés. La suppression d'une fiche n'est pas
une récupération neutre : ses licences peuvent être supprimées par les
contraintes de la base.
