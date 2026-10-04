-- =========================================================
--  010_client_powers.sql — « Pouvoirs clients » du panel
-- =========================================================
--  Messages / demande de paiement affichés dans l'app (par MAC) et
--  notes internes sur un client. Tout est ADDITIF : aucune colonne
--  existante n'est modifiée, rien n'est lu tant que l'interrupteur
--  CLIENT_POWERS du Worker est coupé (valeur par défaut).
--
--  Le journal des actions réutilise la table existante audit_logs
--  (aucune nouvelle table de journal).
--
--  NB : le Worker crée aussi ces tables à la volée (ensureClientPowersTables),
--  on les garde ici pour la documentation. Idempotent.
-- =========================================================

-- Une ligne par (MAC, genre). genre : 'payment' | 'message' | 'refresh'
CREATE TABLE IF NOT EXISTS client_notices (
  mac        TEXT NOT NULL,
  kind       TEXT NOT NULL,
  active     INTEGER NOT NULL DEFAULT 1,
  title      TEXT,
  body       TEXT,
  amount     TEXT,            -- demande de paiement : montant affiché (texte libre)
  currency   TEXT,
  link       TEXT,            -- demande de paiement : lien https de paiement (optionnel)
  due_at     INTEGER,         -- demande de paiement : échéance (ms epoch, optionnelle)
  expires_at INTEGER,         -- message : fin d'affichage (ms epoch, optionnelle)
  rev        INTEGER NOT NULL, -- change à chaque envoi : la box affiche une seule fois par rev
  actor_id   TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (mac, kind)
);

-- Notes internes (jamais envoyées à la box).
CREATE TABLE IF NOT EXISTS client_notes (
  id         TEXT PRIMARY KEY,
  mac        TEXT NOT NULL,
  body       TEXT NOT NULL,
  actor_id   TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_client_notes_mac ON client_notes(mac, created_at);
