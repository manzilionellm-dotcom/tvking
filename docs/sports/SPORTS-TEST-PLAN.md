# SPORTS-TEST-PLAN — Couverture actuelle et cible

## Suite actuelle

`flutter test` : 684 tests verts au moment de ce lot (676 avant +
8 tests campagnes `test/features/ads/campaign_repository_test.dart`).

Sports — testé indirectement aujourd'hui :
- modèles parsés défensivement (`SportEvent.fromJson` tolère champs
  manquants) ;
- notifications locales couvertes par les tests NotificationService
  existants.

## À ajouter avec ce lot / les suivants

Phase 1 (données actuelles)
- [ ] `SportEvent.startsAt` : timestamp ISO → local, date seule, invalide.
- [ ] Persistance favoris : v1 → v2 (migration une équipe → plusieurs).
- [ ] Recherche : réponse vide, réseau KO (best-effort, pas de crash).

Phase 2 (fournisseur live — quand souscrit)
- [ ] un incident = UNE notification (déduplication par event_id) ;
- [ ] but corrigé/annulé : pas de fausse deuxième alerte ;
- [ ] match reporté/annulé ; prolongation ; tirs au but ;
- [ ] perte du fournisseur → bascule secours → données périmées signalées ;
- [ ] périodes silencieuses ; multi-appareils ; fuseaux horaires.

Phase 3 (cotes/affiliation — quand contrats signés)
- [ ] pays autorisé / bloqué ; mineur ; opérateur suspendu ;
- [ ] campagne inactive ; aucun opérateur disponible ; domaine non validé.

TV (manuel, télécommande uniquement)
- [x] tv_sports_screen : navigation D-pad, focus visible, retour cohérent
      (couvert par le lot « toutes les télécommandes », commit 1618213) ;
- [ ] longue liste de matchs ; reprise après perte réseau.
