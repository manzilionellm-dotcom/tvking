-- Additive migration only. Do not apply automatically or during CI against production.
CREATE TABLE IF NOT EXISTS device_secrets (
  mac TEXT PRIMARY KEY NOT NULL,
  secret_hash TEXT NOT NULL,
  android_id TEXT,
  enrolled_at INTEGER NOT NULL,
  rotated_at INTEGER
);
CREATE INDEX IF NOT EXISTS idx_device_secrets_android_id ON device_secrets(android_id);
