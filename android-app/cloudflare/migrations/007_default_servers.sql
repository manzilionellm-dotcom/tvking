-- =========================================================
--  007_default_servers.sql — Serveurs IPTV par défaut
-- =========================================================
--  Ces serveurs sont ceux proposés dans l'app cliente. Le client ne
--  saisit JAMAIS d'URL : il choisit « Serveur 1 / 2 / 3… » et ne tape
--  que son code Xtream (utilisateur + mot de passe). L'URL reste
--  cachée côté serveur — conforme AGENTS.md règle n°2.
--
--  Gérés depuis le PANEL ADMIN (page « Serveurs ») via l'API
--  /api/v1/servers, et lus par l'app via la route publique
--  GET /api/servers (worker.js).
--
--  NB : le Worker crée déjà cette table à la volée (CREATE TABLE
--  IF NOT EXISTS dans ensureServersTable) pour que ça marche même
--  sans jouer cette migration. On la garde ici pour documentation
--  et pour seeder le 1ᵉʳ serveur. INSERT OR IGNORE = idempotent.
-- =========================================================

CREATE TABLE IF NOT EXISTS default_servers (
  id         TEXT PRIMARY KEY,
  label      TEXT NOT NULL,
  url        TEXT NOT NULL,
  position   INTEGER NOT NULL DEFAULT 0,
  enabled    INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Serveur par défaut (modifiable / supprimable depuis le panel).
INSERT OR IGNORE INTO default_servers
  (id, label, url, position, enabled, created_at, updated_at)
VALUES
  ('srv_default_1', 'Serveur 1', 'http://line.iptvmadrid.es', 1, 1, 0, 0);
