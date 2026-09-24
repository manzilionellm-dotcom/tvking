-- =========================================================
--  009_credit_model.sql — Modèle de crédits revendeur
-- =========================================================
--  Décision commerciale (demande owner) :
--    - 1 crédit  = 1 an   (plan 'yearly')
--    - 2 crédits = à vie  (plan 'lifetime')
--
--  Les revendeurs ne vendent QUE ces deux plans (cf. contrôle
--  serveur dans api_v1.js : handleActivate). L'activation 'monthly'
--  (1 mois) reste possible mais est RÉSERVÉE à l'administrateur —
--  son coût en crédits n'a donc pas d'impact côté revendeur.
--
--  On force la mise à jour des lignes existantes (ON CONFLICT) car
--  l'ancien seed valait yearly=10 / lifetime=25.
-- =========================================================

INSERT INTO plan_costs (plan, credits) VALUES
  ('yearly', 1),
  ('lifetime', 2)
ON CONFLICT(plan) DO UPDATE SET credits = excluded.credits;
