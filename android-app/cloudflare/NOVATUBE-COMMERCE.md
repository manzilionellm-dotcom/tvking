# NovaTube : essai et activation payante

Cette intégration concerne uniquement `app_novatube4k` / `com.manthefew`.
Le prix est fixé côté serveur à **999 centimes EUR**, en paiement unique.
La durée payante doit être choisie explicitement avant d'ouvrir les ventes.
Le module ne change ni les prix ni les licences des autres applications.
`adaptive_pricing[enabled]=false` conserve la présentation en EUR du prix
annoncé. Les requêtes API refusent les redirections HTTP du prestataire et
ne transmettent jamais la clé Stripe à un autre hôte.

## État de la configuration vérifié le 14 novembre 2026

Le Worker `seven-motion-backend` ne contient aucun binding de paiement Stripe,
PayPal ou Checkout. Le schéma historique possède une table `payments`, mais
aucune intégration NovaTube ne l'utilisait pour encaisser automatiquement.
Les liens de paiement Zuno présents comme variables d'exemple sur le site
racine ne sont pas des offres NovaTube vérifiées et ne sont pas réutilisés.
Aucun contact d'assistance spécifique à cette application n'a été identifié
dans les sources examinées. Aucun numéro extérieur n'est ajouté par défaut.

**Le paiement en ligne reste donc fermé par défaut.** L'essai de dix jours
et son expiration peuvent fonctionner indépendamment. Après expiration, une
activation administrative existante reste possible ; le client est informé
de l'indisponibilité du paiement en ligne au lieu de voir un faux succès.

## Configuration marchande requise

Les valeurs secrètes sont déposées exclusivement dans le gestionnaire de
secrets Cloudflare, jamais dans Git, l'APK, les journaux ou une conversation.

| Nom | Valeur attendue |
| --- | --- |
| `NOVATUBE_COMMERCE_ENABLED` | `1` pour ouvrir Checkout après validation |
| `NOVATUBE_STRIPE_MODE` | `test` dans une base isolée de test ; `live` pour la production |
| `NOVATUBE_STRIPE_SECRET_KEY` | Clé Stripe correspondant exactement au mode, avec droits Checkout nécessaires |
| `NOVATUBE_STRIPE_WEBHOOK_SECRET` | Secret de signature du webhook NovaTube correspondant au même environnement |
| `NOVATUBE_PAID_DURATION` | Nombre entier de jours, de 1 à 3660, ou `lifetime` si explicitement choisi |
| `NOVATUBE_CHECKOUT_ORIGIN` | Origine HTTPS publique dédiée au client, sans chemin ni paramètres |

Le dernier domaine doit servir les deux routes de retour ci-dessous. Il n'a
pas besoin d'être le domaine d'administration. Les données de carte sont
saisies sur le Checkout Stripe hébergé ; aucune donnée bancaire ou source
M3U/Xtream n'est reçue par ce module.

## Routes et raccordements

- `POST /api/novatube4k/checkout` : garde d'identité existant `raw_mac` et
  `X-Device-Key`, puis `createNovatubeCheckout(env, binding, input, deps)`.
  Le prix, la devise, le produit, l'appareil et la durée viennent du serveur.
- `POST /api/novatube4k/payments/stripe-webhook` : raccord direct à
  `handleNovatubeStripeWebhook(request, env, hooks)` avant le dispatcher
  appareil. Seule une signature Stripe valide autorise son traitement.
- `GET /novatube/payment-return` et `GET /novatube/payment-cancel` :
  `handleNovatubePaymentReturn(request)` affiche une page neutre sans mutation.

Le webhook doit recevoir `checkout.session.completed` et
`checkout.session.async_payment_succeeded`, dans le mode correspondant.
Une session terminée mais encore impayée ne donne aucun accès.

`novatubeCommerceMetadata(env)` expose :

```json
{
  "price_minor": 999,
  "currency": "EUR",
  "auto_renew": false,
  "license_duration": null,
  "checkout_available": false,
  "checkout_url": null
}
```

Quand la configuration est complète, `checkout_available` devient vrai et
`license_duration` contient `lifetime` ou, par exemple, `365_days`.
L'URL de paiement est créée seulement sur demande. La réponse contient
`ok`, `order_id`, `checkout_url`, `expires_at`, `price_minor`, `currency` et
`license_duration`. Ce dernier champ vient de la commande figée ; l'application
le compare à l'offre affichée avant d'ouvrir Checkout.
Le domaine de `checkout_url` doit être exactement `checkout.stripe.com` en HTTPS.

## Confirmation, concurrence et conservation

Le module vérifie la signature HMAC-SHA256 sur le corps brut, avec une fenêtre
de cinq minutes. Il accepte plusieurs signatures `v1` pendant une rotation,
mais n'utilise jamais les champs de diagnostic non signés du header.

Il relit ensuite la session et le PaymentIntent auprès de Stripe. Le mode
live/test, la devise, les 999 centimes, le produit d'application, l'appareil,
la licence, la commande, la quantité et le paiement réellement réussi doivent
tous correspondre. Une URL de retour, un paramètre `paid=true` ou la seule
réception de `checkout.session.completed` ne constitue pas une preuve.

Une seule commande ouverte est autorisée par licence. Les reprises réseau
conservent le même identifiant d'idempotence Stripe. Avant de remplacer une
ancienne commande, le serveur vérifie qu'elle est réellement expirée et
impayée chez Stripe ; un paiement dont le webhook est en retard est rapproché
sans ouvrir une seconde commande.

La commande, le paiement, la licence et l'audit sont engagés dans un lot D1
atomique. Un rejeu ou des webhooks concurrents ne donnent pas un second accès.
Les crédits revendeur ne sont jamais débités par ce circuit. Une modification
administrative concurrente, un blocage ou un gel empêche l'écrasement de la
licence. Le paiement reçu est alors conservé dans `payments` et la commande
est marquée `review`, avec un audit distinct, pour traitement par l'assistance.
Une licence existante active et payée n'est jamais remise à zéro par Checkout.

Les tables `novatube4k_purchase_orders` et `novatube4k_purchase_guard` sont
additives. Aucun secret fournisseur ou numéro de carte n'y est enregistré.
Une panne de notification n'annule pas un paiement engagé : la prochaine
lecture de l'état serveur retrouve l'activation.

## Vérification et limites avant ouverture des ventes

Les tests `novatube4k-commerce.test.mjs` utilisent SQLite réel et un serveur
Stripe simulé. Ils couvrent fermeture par défaut, contrôle du montant et de
la portée, signatures, mode live/test, commandes concurrentes, réponse
perdue, expiration, webhook retardé, transactions, rejeux et conservation des
licences administrativement modifiées. Aucun paiement réel n'est effectué.

Il reste nécessaire de choisir la durée payante, connecter le compte marchand,
enregistrer le webhook, servir les pages de retour sur l'origine client et
réaliser le parcours Stripe en mode test dans une base isolée avant d'activer
la configuration live. Les taxes, factures, conditions commerciales et contacts
marchands doivent être définis par le propriétaire. Le module ne prétend pas
les avoir configurés. Les remboursements et litiges ne déclenchent pas encore
une révocation automatique ; ils doivent être traités par l'administration.

## Documentation officielle consultée

- [Création d'une session Checkout, version API 2026-10-28.endive](https://docs.stripe.com/api/checkout/sessions/create)
- [Exécution après paiement confirmé et idempotence](https://docs.stripe.com/checkout/fulfillment.md?ui=full-page)
- [Réception des événements et signatures](https://docs.stripe.com/webhooks?lang=node)
- [Dépannage des signatures, corps brut et champs non signés](https://docs.stripe.com/events/manage-webhook-endpoints)
- [Tarification adaptée et présentation de la devise](https://docs.stripe.com/payments/currencies/localize-prices/adaptive-pricing.md?payment-ui=stripe-hosted)
