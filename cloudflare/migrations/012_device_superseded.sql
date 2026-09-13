-- MAC régénérée / changée : l'ancienne fiche pointe vers le nouveau
-- numéro. Heartbeat et GET /status renvoient mac_reassigned pour que
-- l'app mobile ADOPTE le nouveau (écran « YOUR REFERENCE NUMBER »).
-- L'ancienne ligne est un tombstone banni, SANS android_id — sinon
-- ensureD1Device hériterait le ban sur la fiche neuve (anti-freeloader).
ALTER TABLE devices ADD COLUMN superseded_by TEXT;
CREATE INDEX IF NOT EXISTS idx_devices_superseded ON devices(superseded_by);
