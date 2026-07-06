-- =========================================================
--  010_fix_trial_days.sql — Remet l'essai gratuit à 7 jours
-- =========================================================
--  Décision owner (2026-07-06) : l'essai gratuit doit être de 7 jours,
--  pas 30. Le code (worker.js TRIAL_DAYS, api_v1.js handlePricingPut)
--  utilise déjà 7 comme défaut — mais une valeur "30" avait été
--  enregistrée dans app_config au moment de la configuration initiale
--  des tarifs (page « Tarifs » du panel), et cette valeur enregistrée
--  prime sur le défaut du code. Cette migration corrige la donnée.
--
--  ON CONFLICT (et pas un simple UPDATE) : marche aussi si la ligne
--  n'existe pas encore (première init de app_config).
-- =========================================================

CREATE TABLE IF NOT EXISTS app_config (key TEXT PRIMARY KEY, value TEXT);

INSERT INTO app_config (key, value) VALUES ('trial_days', '7')
ON CONFLICT(key) DO UPDATE SET value = '7';
