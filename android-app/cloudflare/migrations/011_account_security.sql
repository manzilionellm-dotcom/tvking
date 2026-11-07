-- Sessions et facteurs chiffrés. Aucun secret dans cette migration.
CREATE TABLE IF NOT EXISTS auth_sessions (id TEXT PRIMARY KEY, actor TEXT NOT NULL, refresh_hash TEXT NOT NULL, expires_at INTEGER NOT NULL, created_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS auth_factors (actor TEXT PRIMARY KEY, secret TEXT, enabled INTEGER NOT NULL DEFAULT 0, pending TEXT, pending_until INTEGER, last_counter INTEGER NOT NULL DEFAULT -1);
CREATE TABLE IF NOT EXISTS auth_recovery (actor TEXT NOT NULL, code_hash TEXT NOT NULL, PRIMARY KEY(actor, code_hash));
CREATE UNIQUE INDEX IF NOT EXISTS idx_auth_refresh ON auth_sessions(refresh_hash);
CREATE INDEX IF NOT EXISTS idx_auth_actor ON auth_sessions(actor);
