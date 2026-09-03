# À FAIRE PAR LE PROPRIÉTAIRE — sécurité

Ces actions ne peuvent PAS être faites depuis une session de
développement : elles demandent tes identifiants Cloudflare et tes
droits GitHub. Elles sont listées ici pour ne pas être oubliées.

**Fais-les dans cet ordre.**

---

## 1. Le dépôt doit passer en PRIVÉ

`manzilionellm-dotcom/tvking` est public. Un dépôt public expose le code
du back-end, les noms des routes, la structure de la base et l'histoire
complète des commits — y compris ce qui a été retiré depuis.

Sur GitHub : *Settings → General → Danger Zone → Change visibility →
Make private*.

## 2. Tourner le secret d'administration

Quatre fichiers de workflow contenaient le mot de passe `change-me`, et
le code retombait sur la chaîne `dev-secret` quand aucun secret n'était
posé. Les deux étaient lisibles par tout le monde. **On doit donc
considérer que le secret actuel est connu.**

```
wrangler secret put ADMIN_SECRET
wrangler secret put JWT_SECRET
```

`JWT_SECRET` est nouveau : il sépare la SIGNATURE des jetons du mot de
passe d'amorçage. Sans cette séparation, tourner l'un obligeait à
tourner l'autre. Mets deux valeurs longues et différentes (30+
caractères aléatoires chacune).

⚠ **Après cette rotation, tout le monde devra se reconnecter au
panneau.** C'est normal : c'est exactement ce que « tourner un secret »
veut dire.

⚠ Si aucun des deux n'est posé, l'API répond désormais **503** et le
dit, au lieu de fonctionner avec un secret public. C'est voulu.

## 3. Changer le mot de passe du compte admin

Le compte `admin` a pu être créé avec `change-me`. Connecte-toi au
panneau et change-le depuis *Compte*.

## 4. Ce qui a été supprimé, et pourquoi

Quatre workflows ont été retirés le 03/09/2026 :

| Fichier | Ce qu'il contenait |
|---|---|
| `diag-api.yml` | le mot de passe `change-me` en clair |
| `diag-reactivate.yml` | le mot de passe `change-me` en clair |
| `diag-family.yml` | gelait un vrai appareil client (`MK:00:00:00:00:01`) |
| `set-admin-password.yml` | recevait le mot de passe comme paramètre de run |

Le dernier mérite une explication : un paramètre de `workflow_dispatch`
est **enregistré en clair dans l'historique des exécutions** et visible
par tous ceux qui voient le dépôt. Un formulaire qui demande un mot de
passe donne l'impression du contraire — c'est ce qui le rend dangereux.

Pour changer le secret, utilise `wrangler secret put` depuis ta machine
(point 2). C'est la seule voie où le secret ne transite par aucun
journal.

---

## Ce qui reste ouvert et sera traité

- **Vague 3 (jeton d'appareil)** : `/api/device-source/:mac` renvoie
  encore les identifiants du fournisseur à qui connaît l'adresse. Le
  transfert et le prêt sont fermés (410) en attendant.
- **Vague 5 (livraison)** : la clé de signature de secours
  `ci/defew-debug.keystore` s'ouvre avec le mot de passe `android` et
  certains builds y retombent en silence.
