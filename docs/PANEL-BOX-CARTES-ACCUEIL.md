# Panel → box : les cartes de l'accueil (annonce, favori du jour, bannières)

Octobre 2026. Côté **box** uniquement (`android-app/lib/features/panel_board/`).
Le Worker (`android-app/cloudflare/`) et le panel (`android-app/admin-panel/`)
n'ont **pas** été touchés : ils sont hors périmètre de la mission. Ce document
dit ce que la box sait lire aujourd'hui, et ce qu'il reste à servir côté panel.

## Ce qui marche déjà de bout en bout (panel existant → box)

| Panel (page) | Route lue par la box | Ordre « signal » | Carte sur l'accueil box |
| --- | --- | --- | --- |
| Annonces & Notifications | `GET /api/announcement` (`id, title, body, url, kind, cta`) | `message` | `TvPanelNotice` : icône selon `kind` (`nouveaute`, `promo`, `info`, `maintenance`), bouton « Vu » (mémorisé par id), QR du lien pour le téléphone si `url` |
| Favori du jour | `GET /api/featured` (`name, note`) | `featured` | `TvFeaturedCard` : seulement si une chaîne de la liste porte ce nom (repli accents/casse, direct d'abord), bouton « Regarder » |

Le canal signal est celui déjà en place (`RemoteActivationWatch` →
`AnnouncementRepository.fetchLatest()` / `FeaturedRepository.refresh()`). La box
écoute `AnnouncementRepository.latest` (nouveau `ValueNotifier`) et
`FeaturedRepository` : la carte change **sans relire le réseau** côté accueil.

## Ce qui attend le panel : les bannières images

Le module « Bannières » du Centre de contrôle est marqué *Bientôt (Phase 2)*.
La box lit déjà `GET /api/banners` (404 aujourd'hui → aucune bannière, rien ne
change à l'écran) et relit sur l'ordre signal `banner` (ou `banners`).

Contrat attendu (`200`, JSON) :

```json
{
  "version": 1700000000000,
  "items": [
    {
      "id": "cdm-2026",
      "image": "https://…/cdm.jpg",
      "title": "Coupe du monde",
      "subtitle": "Tous les matchs en direct",
      "label": "Publicité",
      "cta": "Regarder",
      "channel": "beIN Sports 1",
      "url": "https://…/offre",
      "from": 1760000000000,
      "until": 1762000000000,
      "kids": false
    }
  ]
}
```

| Champ | Obligatoire | Règle côté box |
| --- | --- | --- |
| `id` | oui | ≤ 64 caractères ; identité pour le plafond du jour et « Fermer » |
| `image` | oui | **https** uniquement (http ignoré) ; 16:5 conseillé, ≥ 1280 px de large, décodée à 1280 px max |
| `title`, `subtitle` | non | 80 / 120 caractères max |
| `label` | non | défaut **« Publicité »** ; jamais vide (loi LCEN art. 20 : une publicité se présente comme telle) |
| `cta` | non | libellé du bouton d'action (défaut « Regarder ») |
| `channel` | non | NOM d'une chaîne ; bouton « Regarder » seulement si elle est dans la liste de la box |
| `url` | non | https uniquement ; montré en QR (un lien ne s'ouvre pas à la télécommande) |
| `from`, `until` | non | epoch ms ; fenêtre de diffusion |
| `kids` | non | `true` = visible aussi en mode enfants (défaut : cachée) |

Règles de la box (non négociables côté client) :

- une seule carte à la fois en tête de l'accueil ; l'émission suivie par la
  personne passe devant, puis l'annonce, puis bannière / favori en alternance
  (tic de 20 s) ;
- au plus **6 apparitions par bannière et par jour** ; « Fermer » = 7 jours
  sans elle ; compteurs locaux (SharedPreferences), rien n'est envoyé ;
- jamais de son, jamais de vidéo, jamais plein écran, jamais sur l'image en
  lecture ; en mode enfants, seules les bannières `kids: true` ;
- trois interrupteurs côté box (Réglages → En plus) : « Annonces du service »,
  « Favori du jour », « Bannières » ; coupés, la carte disparaît et rien d'autre
  ne change.

## À faire côté panel / Worker (hors périmètre de cette mission)

1. Table `app_banners` (ou clé `app_config`) + `GET /api/banners` public dans
   `worker.js` (même forme que `/api/featured`) ;
2. `POST/PATCH/DELETE /api/v1/banners` (owner) dans `api_v1.js` qui appelle
   `signalFleet(env, 'banner')` après chaque écriture ;
3. page « Bannières » du panel : image (upload ou URL https), textes, libellé,
   chaîne, lien, dates, case « visible en mode enfants », aperçu 16:5.

Ce document est la spécification que le panel doit respecter pour que la box
affiche la bannière **sans nouvelle version de l'app**.
