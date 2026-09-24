-- =========================================================
--  002_resellers_credits.sql — Migration pour bases D1 EXISTANTES
-- =========================================================
--  A executer UNE fois sur une base deja deployee (le schema.sql
--  complet couvre deja ces changements pour les NOUVELLES bases) :
--
--    wrangler d1 execute tvking_licensing \
--      --file=cloudflare/migrations/002_resellers_credits.sql --remote
--
--  SQLite (D1) supporte `ALTER TABLE ... ADD COLUMN` mais PAS
--  `IF NOT EXISTS` sur les colonnes : si tu relances cette migration
--  une 2e fois, les ADD COLUMN echoueront « duplicate column » —
--  c'est sans gravite (les CREATE/INSERT plus bas sont idempotents).
-- =========================================================

-- Solde de credits (compteur) du revendeur, distinct du solde en cents.
ALTER TABLE resellers ADD COLUMN credit_balance INTEGER NOT NULL DEFAULT 0;

-- Revendeur "proprietaire" d'un device (scoping : un revendeur ne voit
-- que ses propres appareils).
ALTER TABLE devices ADD COLUMN reseller_id TEXT;
CREATE INDEX IF NOT EXISTS idx_devices_reseller ON devices(reseller_id);

-- Historique des mouvements de credits.
CREATE TABLE IF NOT EXISTS credit_ledger (
  id              TEXT PRIMARY KEY,
  reseller_id     TEXT NOT NULL,
  delta           INTEGER NOT NULL,
  reason          TEXT NOT NULL,
  balance_after   INTEGER NOT NULL,
  ref_license_id  TEXT,
  ref_device_mac  TEXT,
  actor_type      TEXT,
  actor_id        TEXT,
  note            TEXT,
  created_at      INTEGER NOT NULL,
  FOREIGN KEY (reseller_id) REFERENCES resellers(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_ledger_reseller ON credit_ledger(reseller_id);
CREATE INDEX IF NOT EXISTS idx_ledger_created  ON credit_ledger(created_at);

-- Cout en credits de chaque plan (reglable par l'admin).
CREATE TABLE IF NOT EXISTS plan_costs (
  plan     TEXT PRIMARY KEY,
  credits  INTEGER NOT NULL
);
INSERT OR IGNORE INTO plan_costs (plan, credits) VALUES
  ('trial', 0),
  ('monthly', 1),
  ('quarterly', 3),
  ('biannual', 5),
  ('yearly', 10),
  ('lifetime', 25),
  ('custom', 1);
