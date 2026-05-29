-- =========================================================
--  schema.sql — Cloudflare D1 schema for App Licensing Platform
-- =========================================================
--  Apply via :
--    cd cloudflare
--    wrangler d1 create tvking_licensing       # one-time, get the id
--    # paste id into wrangler.toml [[d1_databases]] section
--    wrangler d1 execute tvking_licensing --file=schema.sql --remote
--
--  Design notes :
--    - SQLite under the hood (Cloudflare D1 = managed SQLite).
--    - All IDs are TEXT (we generate them as ULIDs or short uuids
--      client-side ; D1 doesn't have native UUID type).
--    - Timestamps are epoch milliseconds (Date.now() in JS).
--    - Foreign keys are declared and enforced (PRAGMA on by default
--      in D1 since wrangler 3.x).
--    - Strings that may contain secrets (Xtream username/password)
--      end with `_enc` to signal they're encrypted at rest via
--      AES-GCM with a key from the SECRETS_KEY env var.
--    - Booleans = INTEGER 0/1 (SQLite convention).
-- =========================================================

-- ---------------------------------------------------------
-- apps : registry of all apps that this platform manages
-- ---------------------------------------------------------
--  No more hardcoded apps. Adding "Motion TV 4K" tomorrow =
--  inserting one row. The mobile apps already know their own
--  package_name from FlavorConfig ; the dashboard maps it back
--  via this table.
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS apps (
  id              TEXT PRIMARY KEY,
  name            TEXT NOT NULL,
  package_name    TEXT NOT NULL UNIQUE,         -- e.g. "com.manzilionellm.tvking"
  logo_url        TEXT,
  primary_color   TEXT,                          -- "#D63A30"
  tagline         TEXT,
  default_iptv_server TEXT,                      -- e.g. "http://pro.best-iptvinreviews.com"
  default_playlist_type TEXT NOT NULL DEFAULT 'xtream',   -- 'xtream' | 'm3u' | 'none'
  pricing_json    TEXT,                          -- '{"monthly":500,"yearly":1300,"lifetime":9900}' (cents)
  is_active       INTEGER NOT NULL DEFAULT 1,
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL
);

-- ---------------------------------------------------------
-- admin_users : super admin + admins + support staff
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS admin_users (
  id              TEXT PRIMARY KEY,
  email           TEXT NOT NULL UNIQUE,
  password_hash   TEXT NOT NULL,                 -- bcrypt-like via Web Crypto + PBKDF2
  name            TEXT,
  role            TEXT NOT NULL DEFAULT 'admin', -- 'super_admin' | 'admin' | 'support'
  is_active       INTEGER NOT NULL DEFAULT 1,
  last_login_at   INTEGER,
  created_at      INTEGER NOT NULL
);

-- ---------------------------------------------------------
-- resellers : optional reseller layer (Phase 3)
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS resellers (
  id              TEXT PRIMARY KEY,
  email           TEXT NOT NULL UNIQUE,
  password_hash   TEXT NOT NULL,
  name            TEXT,
  credit_balance_cents INTEGER NOT NULL DEFAULT 0,
  commission_rate REAL NOT NULL DEFAULT 0.20,
  status          TEXT NOT NULL DEFAULT 'active',  -- 'active' | 'suspended'
  created_at      INTEGER NOT NULL
);

-- ---------------------------------------------------------
-- customers : end users who pay for app access
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS customers (
  id              TEXT PRIMARY KEY,
  email           TEXT,                          -- optional in v1 (MAC-only customers)
  password_hash   TEXT,                          -- nullable, set when they activate self-service portal
  name            TEXT,
  phone           TEXT,
  reseller_id     TEXT,
  notes           TEXT,
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL,
  FOREIGN KEY (reseller_id) REFERENCES resellers(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_customers_email    ON customers(email);
CREATE INDEX IF NOT EXISTS idx_customers_reseller ON customers(reseller_id);

-- ---------------------------------------------------------
-- devices : physical devices that run our apps
-- ---------------------------------------------------------
--  One customer can have many devices. The MAC is the universal
--  client-side identifier (our virtual MK:XX:XX:XX:XX:XX format).
--  When a heartbeat arrives from a device with no customer, the
--  Worker auto-creates a customer record (anonymous, MAC-only).
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS devices (
  id              TEXT PRIMARY KEY,
  customer_id     TEXT NOT NULL,
  mac             TEXT NOT NULL UNIQUE,          -- MK:XX:XX:XX:XX:XX
  label           TEXT,                          -- "Salon Fire TV"
  first_seen_at   INTEGER NOT NULL,
  last_seen_at    INTEGER NOT NULL,
  FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_devices_customer ON devices(customer_id);
CREATE INDEX IF NOT EXISTS idx_devices_mac      ON devices(mac);

-- ---------------------------------------------------------
-- licenses : the core. One license = (customer × device × app)
-- ---------------------------------------------------------
--  A device can hold multiple licenses (one per installed app of
--  ours, e.g. 7 MOTION AND Red Room on the same phone, each with
--  its own expiry).
--  expires_at is nullable for lifetime plans.
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS licenses (
  id              TEXT PRIMARY KEY,
  customer_id     TEXT NOT NULL,
  device_id       TEXT NOT NULL,
  app_id          TEXT NOT NULL,
  status          TEXT NOT NULL DEFAULT 'active',   -- 'active' | 'expired' | 'frozen' | 'banned' | 'pending'
  plan            TEXT NOT NULL DEFAULT 'trial',    -- 'trial' | 'monthly' | 'quarterly' | 'biannual' | 'yearly' | 'lifetime' | 'custom'
  started_at      INTEGER NOT NULL,
  expires_at      INTEGER,                          -- NULL = lifetime
  auto_renew      INTEGER NOT NULL DEFAULT 0,
  reseller_id     TEXT,
  payment_id      TEXT,
  notes           TEXT,
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL,
  FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE,
  FOREIGN KEY (device_id)   REFERENCES devices(id)   ON DELETE CASCADE,
  FOREIGN KEY (app_id)      REFERENCES apps(id),
  FOREIGN KEY (reseller_id) REFERENCES resellers(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_licenses_customer ON licenses(customer_id);
CREATE INDEX IF NOT EXISTS idx_licenses_device   ON licenses(device_id);
CREATE INDEX IF NOT EXISTS idx_licenses_app      ON licenses(app_id);
CREATE INDEX IF NOT EXISTS idx_licenses_status   ON licenses(status);
CREATE INDEX IF NOT EXISTS idx_licenses_expires  ON licenses(expires_at);
CREATE UNIQUE INDEX IF NOT EXISTS uq_licenses_device_app
  ON licenses(device_id, app_id);  -- one active license per (device, app)

-- ---------------------------------------------------------
-- playlists : Xtream/M3U creds tied to a license
-- ---------------------------------------------------------
--  Pushed remotely from the admin panel. Mobile apps fetch them
--  on heartbeat. Username/password are encrypted at rest.
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS playlists (
  id              TEXT PRIMARY KEY,
  license_id      TEXT NOT NULL UNIQUE,
  type            TEXT NOT NULL,                 -- 'xtream' | 'm3u'
  server_url      TEXT,                          -- when type='xtream'
  username_enc    TEXT,                          -- AES-GCM encrypted
  password_enc    TEXT,                          -- AES-GCM encrypted
  m3u_url         TEXT,                          -- when type='m3u'
  epg_url         TEXT,
  updated_by      TEXT,                          -- admin_user.id or reseller.id
  updated_at      INTEGER NOT NULL,
  FOREIGN KEY (license_id) REFERENCES licenses(id) ON DELETE CASCADE
);

-- ---------------------------------------------------------
-- payments : every monetary transaction
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS payments (
  id                  TEXT PRIMARY KEY,
  customer_id         TEXT,
  reseller_id         TEXT,
  amount_cents        INTEGER NOT NULL,
  currency            TEXT NOT NULL DEFAULT 'EUR',
  gateway             TEXT NOT NULL,            -- 'stripe' | 'paypal' | 'manual' | 'reseller_credit'
  gateway_payment_id  TEXT,
  status              TEXT NOT NULL DEFAULT 'pending',  -- 'pending' | 'succeeded' | 'failed' | 'refunded'
  license_id          TEXT,
  invoice_number      TEXT UNIQUE,
  metadata_json       TEXT,
  created_at          INTEGER NOT NULL,
  paid_at             INTEGER,
  FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL,
  FOREIGN KEY (reseller_id) REFERENCES resellers(id) ON DELETE SET NULL,
  FOREIGN KEY (license_id)  REFERENCES licenses(id)  ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_payments_customer ON payments(customer_id);
CREATE INDEX IF NOT EXISTS idx_payments_status   ON payments(status);

-- ---------------------------------------------------------
-- audit_logs : who did what when
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_logs (
  id              TEXT PRIMARY KEY,
  actor_type      TEXT NOT NULL,                -- 'admin' | 'reseller' | 'customer' | 'system'
  actor_id        TEXT,
  action          TEXT NOT NULL,                -- 'license.create' | 'playlist.update' | ...
  target_type     TEXT,                          -- 'license' | 'customer' | ...
  target_id       TEXT,
  before_json     TEXT,
  after_json      TEXT,
  ip              TEXT,
  user_agent      TEXT,
  created_at      INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_actor   ON audit_logs(actor_type, actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_target  ON audit_logs(target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_logs(created_at);

-- ---------------------------------------------------------
-- notifications : outbound message queue
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS notifications (
  id              TEXT PRIMARY KEY,
  customer_id     TEXT,
  reseller_id     TEXT,
  channel         TEXT NOT NULL,                 -- 'email' | 'push' | 'in_app'
  type            TEXT NOT NULL,                 -- 'license.expiring' | 'payment.received' | ...
  payload_json    TEXT,
  status          TEXT NOT NULL DEFAULT 'pending',  -- 'pending' | 'sent' | 'failed'
  scheduled_for   INTEGER NOT NULL,
  sent_at         INTEGER,
  created_at      INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_notif_status_sched
  ON notifications(status, scheduled_for);

-- ---------------------------------------------------------
-- Seed data : the 2 apps we already know about
-- ---------------------------------------------------------
--  INSERT OR IGNORE so re-running schema.sql is idempotent.
-- ---------------------------------------------------------
INSERT OR IGNORE INTO apps
  (id, name, package_name, primary_color, tagline,
   default_iptv_server, default_playlist_type, pricing_json,
   is_active, created_at, updated_at)
VALUES
  ('app_7motion', '7 MOTION', 'com.manzilionellm.tvking',
   '#D63A30', 'THE FEW · NOT FOR EVERYONE',
   'http://pro.best-iptvinreviews.com', 'xtream',
   '{"monthly":500,"yearly":1300,"lifetime":9900}',
   1, strftime('%s','now') * 1000, strftime('%s','now') * 1000),
  ('app_redroom', 'Red Room', 'com.redroom.player',
   '#D63A30', 'STRICTLY 18+ · AFTER HOURS',
   'http://pro.best-iptvinreviews.com', 'xtream',
   '{"monthly":900,"yearly":2900,"lifetime":14900}',
   1, strftime('%s','now') * 1000, strftime('%s','now') * 1000);
