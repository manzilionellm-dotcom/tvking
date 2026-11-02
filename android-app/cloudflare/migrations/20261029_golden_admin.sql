-- Registre additif des créations Golden confirmées. Aucun réglage existant
-- ni crédit n'est modifié ; l'essai gratuit reste désactivé.
CREATE TABLE IF NOT EXISTS golden_orders (
  id TEXT PRIMARY KEY, actor_id TEXT NOT NULL, mac TEXT NOT NULL,
  device_id TEXT NOT NULL, sub INTEGER NOT NULL CHECK(sub IN (1,3,6,12)),
  bouquet_id TEXT NOT NULL, bouquet_name TEXT NOT NULL,
  key_id TEXT NOT NULL, key_label TEXT NOT NULL,
  cost REAL NOT NULL CHECK(cost>0), credit_floor REAL NOT NULL,
  credits_before REAL NOT NULL, credits_after REAL,
  state TEXT NOT NULL CHECK(state IN ('quoted','preparing','creating','uncertain','created','delivering','delivered','refused')),
  created_at INTEGER NOT NULL, quote_until INTEGER NOT NULL,
  confirmed_at INTEGER, provider_created_at INTEGER, delivered_at INTEGER,
  expected_source_version INTEGER NOT NULL, expected_clear_at INTEGER NOT NULL,
  source_enc TEXT, provider_user_id TEXT, source_rev INTEGER,
  source_order_id TEXT, license_order_id TEXT, source_saved_at INTEGER,
  delivery_lease_until INTEGER NOT NULL DEFAULT 0, error_code TEXT
);
-- Une ambiguïté ne devient JAMAIS une autorisation après un délai.
CREATE UNIQUE INDEX IF NOT EXISTS golden_one_creation_per_mac ON golden_orders(mac)
  WHERE state NOT IN ('quoted','refused');
CREATE INDEX IF NOT EXISTS golden_daily ON golden_orders(confirmed_at,state);
CREATE TABLE IF NOT EXISTS golden_key_locks (
  key_id TEXT PRIMARY KEY, order_id TEXT NOT NULL UNIQUE
);
