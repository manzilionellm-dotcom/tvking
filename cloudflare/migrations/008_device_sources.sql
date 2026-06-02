-- =========================================================
--  008_device_sources.sql — Source IPTV assignée par MAC
-- =========================================================
--  Une "source" = l'abonnement IPTV (Xtream OU M3U) qu'un admin /
--  revendeur assigne à un appareil par sa MAC depuis le panel.
--  L'app la récupère via la route publique GET /api/device-source/:mac
--  (worker.js) et la charge automatiquement : le client n'a RIEN à
--  saisir.
--
--  Gérée via l'API /api/v1/sources/:mac (GET/PUT/DELETE) et lors de
--  l'activation /api/v1/activate (champ `source` optionnel).
--
--  NB : le Worker crée déjà la table à la volée (ensureSourcesTable).
--  On la garde ici pour documentation. Idempotent.
-- =========================================================

CREATE TABLE IF NOT EXISTS device_sources (
  mac        TEXT PRIMARY KEY,   -- MK:XX:XX:XX:XX:XX (majuscules)
  type       TEXT NOT NULL,      -- 'xtream' | 'm3u'
  label      TEXT,               -- libellé optionnel (ex. "Serveur 1")
  server_url TEXT,               -- Xtream : base du serveur (avec port)
  username   TEXT,               -- Xtream : identifiant
  password   TEXT,               -- Xtream : mot de passe
  m3u_url    TEXT,               -- M3U : URL de la playlist
  epg_url    TEXT,               -- optionnel : guide TV XMLTV
  updated_at INTEGER NOT NULL
);
