-- =========================================================
--  010_device_blackbox.sql — Journal boîte noire par MAC
-- =========================================================
--  Dernières lignes techniques envoyées par l'app (POST
--  /api/blackbox), lues par le panel (GET /api/v1/blackbox).
--  Le texte est déjà filtré : pas d'adresse de flux, pas de
--  mot de passe, pas d'identifiant.
--
--  NB : le Worker crée aussi cette table à la volée
--  (ensureBlackboxTable). On la garde ici pour documentation.
--  Idempotent.
-- =========================================================

CREATE TABLE IF NOT EXISTS device_blackbox (
  mac          TEXT PRIMARY KEY,
  body         TEXT NOT NULL,
  updated_at   INTEGER NOT NULL,
  requested_at INTEGER NOT NULL DEFAULT 0
);
