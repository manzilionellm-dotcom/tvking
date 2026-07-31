# SPORTS-COMPLIANCE — Conformité cotes & affiliation sportive

## Position actuelle (Phase 1)

AUCUNE cote, AUCUN bookmaker, AUCUN lien de pari dans l'app. Le Centre
Sportif est purement informatif (calendrier, scores, favoris, rappels).
Il n'y a donc aujourd'hui aucune exposition réglementaire jeu d'argent.

## Ce que l'app ne fera JAMAIS (règle fondamentale du prompt)

- accepter des mises, conserver de l'argent, gérer un portefeuille ;
- exécuter un pari dans l'app ;
- contourner une géo-restriction (VPN/proxy interdits) ;
- présenter un opérateur non licencié dans le pays du client ;
- cibler les mineurs ; garantir des gains ; messages agressifs
  (« Parie maintenant », « Gagne facilement » : bannis).

## Conditions préalables à la Phase 3 (cotes informatives + affiliation)

1. **Contrats réels** : un fournisseur de cotes autorisé (ex. The Odds API)
   ET des programmes d'affiliation d'opérateurs licenciés, pays par pays.
   Aucun n'est signé aujourd'hui.
2. **Géo-routage restrictif** : pays détecté + pays du compte + règles
   configurées → le résultat le PLUS restrictif gagne. Table `geo_rules`
   à créer côté D1, gérée depuis le panel.
3. **Confirmation d'âge** avant activation, désactivation permanente
   possible, kill switch global (`odds_enabled=0` dans `app_config`,
   diffusé en temps réel — mécanique existante).
4. **Transparence** : mention visible « L'application peut recevoir une
   commission si vous utilisez ce lien. » + « Les cotes peuvent évoluer.
   Vérifiez les conditions sur le site de l'opérateur. »
5. **Jeu responsable** : section dédiée avec liens configurables
   (aide locale, auto-exclusion, limites).
6. **Séparation** : les cotes vivent dans une section séparée,
   désactivable, jamais mêlées au suivi sportif de base.

## Protection des données (déjà en vigueur, à maintenir)

- Clés fournisseurs côté Worker uniquement (jamais dans l'APK).
- Liens sortants : HTTPS obligatoire, domaine validé côté serveur
  (le panel n'accepte que des URLs http(s), `api_v1.js parseCampaignBody`) ;
  l'app n'ouvre jamais une URL arbitraire non posée par l'owner.
- Clics affiliés comptés par id de campagne, SANS identité client
  (`/api/campaigns/track` : {id, event} — aucune donnée personnelle).
- Habitudes sportives (équipes suivies) stockées localement sur
  l'appareil, non partagées.
