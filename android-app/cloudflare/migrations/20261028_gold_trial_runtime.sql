-- À appliquer APRÈS 20261028_gold_trial_policy.sql, sur une copie de staging
-- du schéma exporté. Aucun compte, clé, source ou historique existant modifié.
-- Les ALTER sont suivis par le registre de migrations D1 : ne pas rejouer ce
-- fichier manuellement. L'interrupteur reste OFF.
ALTER TABLE gold_trial_claims_v2 ADD COLUMN android_id TEXT;
CREATE UNIQUE INDEX gold_trial_claims_v2_android ON gold_trial_claims_v2(android_id)
  WHERE android_id IS NOT NULL AND state != 'failed';

CREATE TABLE IF NOT EXISTS device_secrets (
  mac TEXT PRIMARY KEY,
  secret_hash TEXT NOT NULL,
  android_id TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS gold_device_secrets_android ON device_secrets(android_id);

-- Reçus chiffrés ; aucun mot de passe/URL dans les événements ou claims.
-- On conserve les anciennes lignes sans les réécrire ni effacer leur contenu.
CREATE TABLE IF NOT EXISTS gold_trial_receipts_v2 (
  mac TEXT PRIMARY KEY,
  line_id TEXT NOT NULL,
  key_id TEXT,
  expire INTEGER NOT NULL,
  credentials_enc TEXT NOT NULL,
  label TEXT NOT NULL CHECK(label IN ('7 MOTION Essai','Zuno TV Essai')),
  created_at INTEGER NOT NULL,
  delivered_at INTEGER,
  lease_until INTEGER NOT NULL DEFAULT 0,
  lease_token TEXT,
  delivery_attempts INTEGER NOT NULL DEFAULT 0
);

-- Une identité figée ne change pas au gré d'un heartbeat non authentifié.
-- Pas d'import automatique depuis des valeurs Android non vérifiées.
CREATE TABLE IF NOT EXISTS gold_device_proof_rate_v2 (
  request_id TEXT PRIMARY KEY,
  ip TEXT NOT NULL,
  at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS gold_device_proof_rate_v2_ip ON gold_device_proof_rate_v2(ip,at);
