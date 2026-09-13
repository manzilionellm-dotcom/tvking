# Test Lionel — Régénérer MAC (tablette `CD:18:EF:A1:A0`)

Client **mobile / tablette** (pas TV). Le numéro affiché « YOUR REFERENCE NUMBER »
est `CD:18:EF:A1:A0` → identité interne `MK:CD:18:EF:A1:A0`.

M3U à pousser (ne pas coller dans le code de production) :

`http://pro.best-iptvinreviews.com/get.php?username=068fcc739b36&password=b70751f486&type=m3u_plus&output=ts`

## Pré-requis

1. Worker déployé (colonne `devices.superseded_by` + routes
   `POST /api/v1/devices/:id/regenerate-mac` et `change-mac`).
2. Panel admin à jour (chips bleus danse : **MACs problématiques**,
   **Changer la MAC**, **Régénérer MAC**).
3. Tablette ouverte sur l’écran verrou, Wi-Fi OK (pastille verte si possible).

## Flow

1. Admin → **Appareils**. Cherche `CD:18:EF:A1:A0` (ou `MK:CD:18:EF:A1:A0`).
2. Ouvre la fiche → **Régénérer MAC** (bleu danse).
3. Coche la confirmation danger.
4. Laisse **Activer tout de suite** (plan 1 an) + colle le M3U ci-dessus.
5. Valide.

**Attendu panel**

- Toast : `Nouveau MAC : MK:…` (le numéro NU est copié dans le presse-papier).
- L’ancienne fiche devient un tombstone **banni** (`superseded_by` = nouveau).
- La fiche live porte le nouveau MAC, abo actif, source M3U.

**Attendu tablette (online)**

- RT `mac_reassigned` **ou** prochain heartbeat / sondage sources (≤ 8–45 s).
- L’écran **YOUR REFERENCE NUMBER** affiche le **nouveau** numéro (plus `CD:18:EF:A1:A0`).
- Heartbeat + licence + sources suivent → déverrouillage.

**Si tablette éteinte / app fermée**

- Au prochain open : heartbeat voit `mac_reassigned`, adopte, re-pingue, déverrouille.

## Contrôle anti-freeloader

- L’ancienne MAC `MK:CD:18:EF:A1:A0` reste en base, **bannie**, **sans** `android_id`.
- Un heartbeat sur l’ancien numéro ne redonne **pas** d’essai : il pousse
  seulement le nouveau numéro.
- Une 3ᵉ MAC aléatoire avec le même `android_id` n’ouvre pas un 2ᵉ essai.

## Filtre « MACs problématiques »

Pastille bleue. Doit lister au moins :

- plusieurs licences / lifetime inactive qui masque un abo jouable
  (`license_pick` — Activer OK mais `paid=false`) ;
- `android_id` en double ;
- online sans abo ;
- MAC remplacée dont l’app n’a pas encore adopté (`pending_reassign`).
