-- Ordres panel → box. Créées aussi au premier appel (ensureSignalSchema).
-- Ce fichier sert de trace : on ne l'exécute PAS sur la base de
-- production dans ce travail.

CREATE TABLE IF NOT EXISTS box_commands (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  mac TEXT NOT NULL,
  kind TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  applied_at INTEGER
);

CREATE INDEX IF NOT EXISTS idx_box_commands_mac ON box_commands(mac, id);

CREATE TABLE IF NOT EXISTS fleet_commands (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS fleet_acks (
  mac TEXT NOT NULL,
  command_id INTEGER NOT NULL,
  applied_at INTEGER NOT NULL,
  PRIMARY KEY (mac, command_id)
);
