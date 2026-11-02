-- Additive uniquement. Aucune table historique, clé ni licence n'est modifiée.
-- À appliquer sur staging puis réconcilier les anciens essais AVANT activation.
CREATE TABLE IF NOT EXISTS gold_trial_settings_v2 (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  gold_trial_enabled INTEGER NOT NULL DEFAULT 0 CHECK (gold_trial_enabled IN (0,1)),
  daily_cap INTEGER NOT NULL DEFAULT 50 CHECK (daily_cap BETWEEN 0 AND 10000),
  updated_at INTEGER NOT NULL DEFAULT 0,
  revision INTEGER NOT NULL DEFAULT 0
);
INSERT OR IGNORE INTO gold_trial_settings_v2(id) VALUES (1);

-- La MAC canonique est la clé globale, indépendante de l'app et du revendeur.
-- Un résultat fournisseur incertain conserve sa réservation : aucun doublon.
CREATE TABLE IF NOT EXISTS gold_trial_claims_v2 (
  mac TEXT PRIMARY KEY,
  request_id TEXT NOT NULL UNIQUE,
  state TEXT NOT NULL CHECK (state IN ('reserved','created','delivered','uncertain','failed','used')),
  created_at INTEGER NOT NULL,
  expire INTEGER,
  line_id TEXT,
  ip TEXT NOT NULL,
  app_version TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS gold_trial_claims_v2_day ON gold_trial_claims_v2(created_at, state);

CREATE TABLE IF NOT EXISTS gold_trial_events_v2 (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  mac TEXT,
  event TEXT NOT NULL,
  reason TEXT,
  created_at INTEGER NOT NULL,
  expire INTEGER,
  line_id TEXT,
  ip TEXT NOT NULL,
  app_version TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS gold_trial_events_v2_mac ON gold_trial_events_v2(mac, id);

-- Fenêtre glissante persistante : pas de compteur en mémoire par isolate.
CREATE TABLE IF NOT EXISTS gold_trial_rate_v2 (
  request_id TEXT PRIMARY KEY,
  ip TEXT NOT NULL,
  at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS gold_trial_rate_v2_ip ON gold_trial_rate_v2(ip, at);
