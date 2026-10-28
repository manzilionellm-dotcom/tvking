-- schema_complet.sql — toutes les tables de tvking_licensing (schéma seul, sans données)

CREATE TABLE ad_campaigns (id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL DEFAULT 'banner', title TEXT NOT NULL DEFAULT '', body TEXT NOT NULL DEFAULT '', image_url TEXT NOT NULL DEFAULT '', target_url TEXT NOT NULL DEFAULT '', cta TEXT NOT NULL DEFAULT '', placement TEXT NOT NULL DEFAULT 'home', start_hour INTEGER, end_hour INTEGER, enabled INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL DEFAULT 0, impressions INTEGER NOT NULL DEFAULT 0, clicks INTEGER NOT NULL DEFAULT 0);
CREATE TABLE admin_presence (mac TEXT PRIMARY KEY, ip TEXT, country TEXT, last_seen INTEGER, channel TEXT);
CREATE INDEX idx_admin_presence_lastseen ON admin_presence(last_seen);
CREATE TABLE admin_users (
  id              TEXT PRIMARY KEY,
  email           TEXT NOT NULL UNIQUE,
  password_hash   TEXT NOT NULL,                 -- bcrypt-like via Web Crypto + PBKDF2
  name            TEXT,
  role            TEXT NOT NULL DEFAULT 'admin', -- 'super_admin' | 'admin' | 'support'
  is_active       INTEGER NOT NULL DEFAULT 1,
  last_login_at   INTEGER,
  created_at      INTEGER NOT NULL
, password_changed_at INTEGER);
CREATE TABLE api_keys (
       id           TEXT PRIMARY KEY,
       name         TEXT NOT NULL,
       prefix       TEXT NOT NULL,
       key_hash     TEXT NOT NULL,
       scopes       TEXT NOT NULL,
       created_at   INTEGER NOT NULL,
       last_used_at INTEGER,
       revoked_at   INTEGER
     );
CREATE TABLE app_broadcasts (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, body TEXT, url TEXT, created_at INTEGER, kind TEXT, cta TEXT, country TEXT, expires_at INTEGER, active INTEGER DEFAULT 1);
CREATE TABLE app_config (key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE app_family_codes (code TEXT PRIMARY KEY, owner_mac TEXT NOT NULL, expires_at INTEGER NOT NULL);
CREATE TABLE app_family_links (member_mac TEXT PRIMARY KEY, owner_mac TEXT NOT NULL, created_at INTEGER, label TEXT);
CREATE INDEX idx_app_family_owner ON app_family_links(owner_mac);
CREATE TABLE app_family_plan (owner_mac TEXT PRIMARY KEY, enabled INTEGER NOT NULL DEFAULT 0, max_members INTEGER, updated_at INTEGER);
CREATE TABLE app_family_positions (family_mac TEXT NOT NULL, profile_id TEXT NOT NULL, content_key TEXT NOT NULL, position_ms INTEGER NOT NULL DEFAULT 0, duration_ms INTEGER NOT NULL DEFAULT 0, finished INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL, name TEXT, poster_url TEXT, is_episode INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (family_mac, profile_id, content_key));
CREATE TABLE app_invites (code TEXT PRIMARY KEY, issuer_mac TEXT NOT NULL, redeemer_mac TEXT, plan TEXT NOT NULL, created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL, redeemed_at INTEGER, guest_until INTEGER, hours INTEGER, channel_json TEXT, mode TEXT, owner_expires_at INTEGER, return_at INTEGER, returned_at INTEGER);
CREATE INDEX idx_app_invites_issuer ON app_invites(issuer_mac);
CREATE INDEX idx_app_invites_redeemer ON app_invites(redeemer_mac);
CREATE TABLE app_masters (mac TEXT PRIMARY KEY, note TEXT, created_at INTEGER);
CREATE TABLE app_reports (id INTEGER PRIMARY KEY AUTOINCREMENT, device TEXT NOT NULL DEFAULT '', app TEXT NOT NULL DEFAULT 'phone', version_name TEXT NOT NULL DEFAULT '', version_code INTEGER NOT NULL DEFAULT 0, platform TEXT NOT NULL DEFAULT '', locale TEXT NOT NULL DEFAULT '', country TEXT NOT NULL DEFAULT '', day TEXT NOT NULL DEFAULT '', failure_count INTEGER NOT NULL DEFAULT 0, failures_json TEXT NOT NULL DEFAULT '[]', created_at INTEGER NOT NULL DEFAULT 0);
CREATE UNIQUE INDEX idx_app_reports_device_day ON app_reports (device, day);
CREATE TABLE apps (
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
, download_url TEXT);
CREATE TABLE audit_logs (
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
, correlation_id TEXT);
CREATE INDEX idx_audit_actor   ON audit_logs(actor_type, actor_id);
CREATE INDEX idx_audit_created ON audit_logs(created_at);
CREATE INDEX idx_audit_target  ON audit_logs(target_type, target_id);
CREATE TABLE bench_runs (mac TEXT NOT NULL, build_label TEXT NOT NULL, platform TEXT, note INTEGER, minutes INTEGER, crashs INTEGER, err INTEGER, mem INTEGER, nostart INTEGER, lecture INTEGER, gels INTEGER, verrou_ko INTEGER, verrou_ok INTEGER, updated_at INTEGER, ttff_med INTEGER, ttff_n INTEGER, PRIMARY KEY (mac, build_label));
CREATE TABLE box_orders (order_id TEXT PRIMARY KEY, mac TEXT NOT NULL, customer_id TEXT, device_id TEXT, kind TEXT NOT NULL, op TEXT, trace_id TEXT, seq INTEGER, config_rev INTEGER, state TEXT NOT NULL, t0_client INTEGER, t1_api INTEGER, t2_commit INTEGER, t3_published INTEGER, received_at INTEGER, received_srv INTEGER, applied_at INTEGER, applied_srv INTEGER, failed_at INTEGER, failed_srv INTEGER, late_ack INTEGER NOT NULL DEFAULT 0, result TEXT, error_code TEXT, error_message TEXT, applied_rev INTEGER, app_version TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE INDEX idx_box_orders_created ON box_orders(created_at);
CREATE INDEX idx_box_orders_mac ON box_orders(mac, created_at);
CREATE INDEX idx_box_orders_trace ON box_orders(trace_id);
CREATE TABLE credit_ledger (
  id              TEXT PRIMARY KEY,
  reseller_id     TEXT NOT NULL,
  delta           INTEGER NOT NULL,                 -- +emission / -consommation
  reason          TEXT NOT NULL,                    -- 'issue'|'activation'|'renew'|'adjust'|'refund'
  balance_after   INTEGER NOT NULL,
  ref_license_id  TEXT,
  ref_device_mac  TEXT,
  actor_type      TEXT,                             -- 'admin'|'reseller'|'system'
  actor_id        TEXT,
  note            TEXT,
  created_at      INTEGER NOT NULL,
  FOREIGN KEY (reseller_id) REFERENCES resellers(id) ON DELETE CASCADE
);
CREATE INDEX idx_ledger_created  ON credit_ledger(created_at);
CREATE INDEX idx_ledger_reseller ON credit_ledger(reseller_id);
CREATE TABLE credit_requests (id TEXT PRIMARY KEY, reseller_id TEXT NOT NULL, amount INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'pending', note TEXT, decided_by TEXT, decided_at INTEGER, created_at INTEGER NOT NULL);
CREATE INDEX idx_credit_req_status ON credit_requests(status, created_at);
CREATE TABLE customers (
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
CREATE INDEX idx_customers_email    ON customers(email);
CREATE INDEX idx_customers_reseller ON customers(reseller_id);
CREATE TABLE default_servers (
         id TEXT PRIMARY KEY,
         label TEXT NOT NULL,
         url TEXT NOT NULL,
         position INTEGER NOT NULL DEFAULT 0,
         enabled INTEGER NOT NULL DEFAULT 1,
         created_at INTEGER NOT NULL,
         updated_at INTEGER NOT NULL
       );
CREATE TABLE device_backups (
         mac        TEXT PRIMARY KEY,
         data_json  TEXT,
         updated_at INTEGER
       );
CREATE TABLE device_blackbox (mac TEXT PRIMARY KEY, body TEXT NOT NULL, updated_at INTEGER NOT NULL, requested_at INTEGER NOT NULL DEFAULT 0);
CREATE TABLE device_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, mac TEXT, title TEXT, body TEXT, kind TEXT, duration_sec INTEGER, created_at INTEGER, delivered_at INTEGER, read_at INTEGER);
CREATE INDEX idx_devmsg_mac ON device_messages(mac, delivered_at);
CREATE TABLE device_net (
       mac        TEXT PRIMARY KEY,
       proxy      TEXT NOT NULL,
       label      TEXT,
       updated_at INTEGER NOT NULL
     , shared_stream INTEGER);
CREATE TABLE device_orders (id INTEGER PRIMARY KEY AUTOINCREMENT, mac TEXT NOT NULL, kind TEXT NOT NULL, target_json TEXT, created_at INTEGER, applied_at INTEGER);
CREATE INDEX idx_device_orders_mac ON device_orders (mac, applied_at);
CREATE TABLE device_profiles (
         mac TEXT PRIMARY KEY,
         profiles_json TEXT NOT NULL,
         updated_at INTEGER NOT NULL);
CREATE TABLE device_source_clears (mac TEXT PRIMARY KEY, cleared_at INTEGER NOT NULL);
CREATE TABLE device_sources (
         mac        TEXT PRIMARY KEY,
         type       TEXT NOT NULL,
         label      TEXT,
         server_url TEXT,
         username   TEXT,
         password   TEXT,
         m3u_url    TEXT,
         epg_url    TEXT,
         updated_at INTEGER NOT NULL
       , sources_json TEXT, origin TEXT, reseller_id TEXT, version INTEGER NOT NULL DEFAULT 0);
CREATE TABLE device_sync (mac TEXT PRIMARY KEY, rev INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL);
CREATE TABLE devices (
  id              TEXT PRIMARY KEY,
  customer_id     TEXT NOT NULL,
  mac             TEXT NOT NULL UNIQUE,          -- MK:XX:XX:XX:XX:XX
  label           TEXT,                          -- "Salon Fire TV"
  reseller_id     TEXT,                          -- revendeur "proprietaire" (scoping)
  first_seen_at   INTEGER NOT NULL,
  last_seen_at    INTEGER NOT NULL, block_status TEXT, device_model TEXT, android_build TEXT, android_release TEXT, app_build INTEGER, platform TEXT, android_id TEXT, app_version TEXT, local_sources_json TEXT, recent_json TEXT, build_label TEXT, admin_note TEXT, superseded_by TEXT, mem_mb INTEGER, mem_peak_mb INTEGER, cpu_pct INTEGER, cpu_peak_pct INTEGER, res_at INTEGER, store_build INTEGER, reset_at INTEGER,
  FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE,
  FOREIGN KEY (reseller_id) REFERENCES resellers(id) ON DELETE SET NULL
);
CREATE INDEX idx_devices_androidid ON devices(android_id);
CREATE INDEX idx_devices_customer ON devices(customer_id);
CREATE INDEX idx_devices_lastseen ON devices(last_seen_at);
CREATE INDEX idx_devices_mac      ON devices(mac);
CREATE INDEX idx_devices_reseller ON devices(reseller_id);
CREATE INDEX idx_devices_superseded ON devices(superseded_by);
CREATE TABLE error_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, mac TEXT, level TEXT, tag TEXT, message TEXT, detail TEXT, app_version TEXT, app_build TEXT, platform TEXT, country TEXT, created_at INTEGER);
CREATE INDEX idx_error_logs_created ON error_logs (created_at DESC);
CREATE INDEX idx_error_logs_mac ON error_logs (mac);
CREATE TABLE families (
       id TEXT PRIMARY KEY,
       name TEXT NOT NULL,
       source_json TEXT,
       reseller_id TEXT,
       created_at INTEGER,
       updated_at INTEGER
     );
CREATE TABLE family_codes (code TEXT PRIMARY KEY, owner_mac TEXT NOT NULL, expires_at INTEGER NOT NULL);
CREATE TABLE family_links (
       id TEXT PRIMARY KEY,
       family_id TEXT NOT NULL,
       token TEXT NOT NULL UNIQUE,
       label TEXT,
       created_at INTEGER
     );
CREATE TABLE family_members (
       id TEXT PRIMARY KEY,
       family_id TEXT NOT NULL,
       mac TEXT NOT NULL,
       label TEXT,
       created_at INTEGER,
       UNIQUE(family_id, mac)
     );
CREATE TABLE feedback (id INTEGER PRIMARY KEY AUTOINCREMENT, mac TEXT, country TEXT, rating INTEGER, message TEXT, created_at INTEGER);
CREATE TABLE gold_history (
      id TEXT PRIMARY KEY, mac TEXT NOT NULL, event TEXT NOT NULL, gold_line_id TEXT,
      gold_user_id TEXT, sub INTEGER, expire TEXT, ip TEXT, app_version TEXT, actor TEXT,
      detail_json TEXT, created_at INTEGER NOT NULL);
CREATE INDEX ix_gold_history_mac ON gold_history(mac, created_at);
CREATE TABLE gold_keys (
    id TEXT PRIMARY KEY, enc TEXT NOT NULL, fp TEXT NOT NULL UNIQUE, reseller TEXT, masked TEXT,
    trial_priority INTEGER NOT NULL DEFAULT 10, use_for_paid INTEGER NOT NULL DEFAULT 0,
    trial_cap_per_day INTEGER, pack TEXT, enabled INTEGER NOT NULL DEFAULT 1,
    last_error TEXT, last_used_at INTEGER, created_at INTEGER NOT NULL);
CREATE TABLE gold_lines (
      id TEXT PRIMARY KEY, mac TEXT NOT NULL, kind TEXT NOT NULL, status TEXT NOT NULL,
      gold_user_id TEXT, username TEXT, password TEXT, url TEXT, sub INTEGER, expire TEXT,
      android_id TEXT, ip TEXT, app_version TEXT, created_by TEXT, error TEXT,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, key_id TEXT);
CREATE UNIQUE INDEX ux_gold_lines_mac_kind ON gold_lines(mac, kind);
CREATE TABLE home_layout (key TEXT PRIMARY KEY, position INTEGER, enabled INTEGER DEFAULT 1, ribbon TEXT DEFAULT '', featured INTEGER DEFAULT 0, updated_at INTEGER);
CREATE TABLE home_layout_history (id INTEGER PRIMARY KEY AUTOINCREMENT, payload_json TEXT, label TEXT, created_at INTEGER);
CREATE TABLE idempotency_keys (k TEXT PRIMARY KEY, actor_id TEXT, request_hash TEXT NOT NULL, status INTEGER, body_json TEXT, created_at INTEGER NOT NULL, committed_at INTEGER, commit_ref TEXT);
CREATE TABLE lab_sources (id TEXT PRIMARY KEY, name TEXT, url TEXT, source_json TEXT, created_at INTEGER);
CREATE TABLE licenses (
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
CREATE INDEX idx_licenses_app      ON licenses(app_id);
CREATE INDEX idx_licenses_customer ON licenses(customer_id);
CREATE INDEX idx_licenses_device   ON licenses(device_id);
CREATE INDEX idx_licenses_expires  ON licenses(expires_at);
CREATE INDEX idx_licenses_status   ON licenses(status);
CREATE UNIQUE INDEX uq_licenses_device_app
  ON licenses(device_id, app_id);
CREATE TABLE master_test_list (mac TEXT PRIMARY KEY, m3u TEXT, updated_at INTEGER, gateway_base TEXT, gateway_user TEXT, gateway_pass TEXT);
CREATE TABLE match_predictions (match_id TEXT NOT NULL, mac TEXT NOT NULL, pick TEXT NOT NULL, kickoff_ms INTEGER, at INTEGER NOT NULL, PRIMARY KEY (match_id, mac));
CREATE TABLE notifications (
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
CREATE INDEX idx_notif_status_sched
  ON notifications(status, scheduled_for);
CREATE TABLE pair_sessions (code TEXT PRIMARY KEY, token TEXT NOT NULL, created_at INTEGER NOT NULL, payload TEXT);
CREATE TABLE payments (
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
CREATE INDEX idx_payments_customer ON payments(customer_id);
CREATE INDEX idx_payments_status   ON payments(status);
CREATE TABLE plan_costs (
  plan     TEXT PRIMARY KEY,
  credits  INTEGER NOT NULL
);
CREATE TABLE playlists (
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
CREATE TABLE presence (mac TEXT PRIMARY KEY, ip TEXT, country TEXT, last_seen INTEGER, channel TEXT, playing INTEGER);
CREATE INDEX idx_presence_channel ON presence(channel);
CREATE INDEX idx_presence_lastseen ON presence(last_seen);
CREATE TABLE rate_limits (k TEXT PRIMARY KEY, count INTEGER NOT NULL, window_start INTEGER NOT NULL);
CREATE TABLE resellers (
  id              TEXT PRIMARY KEY,
  email           TEXT NOT NULL UNIQUE,
  password_hash   TEXT NOT NULL,
  name            TEXT,
  credit_balance_cents INTEGER NOT NULL DEFAULT 0,
  credit_balance  INTEGER NOT NULL DEFAULT 0,  -- solde de CREDITS (compteur) pour activations revendeur
  commission_rate REAL NOT NULL DEFAULT 0.20,
  status          TEXT NOT NULL DEFAULT 'active',  -- 'active' | 'suspended'
  created_at      INTEGER NOT NULL
, parent_reseller_id TEXT, level TEXT NOT NULL DEFAULT 'basique', permissions TEXT);
CREATE INDEX idx_resellers_parent ON resellers(parent_reseller_id);
CREATE TABLE screen_sessions (
       code        TEXT PRIMARY KEY,
       state_json  TEXT,
       created_at  INTEGER,
       updated_at  INTEGER,
       expires_at  INTEGER
     );
CREATE TABLE source_revisions (mac TEXT NOT NULL, rev INTEGER NOT NULL, state TEXT NOT NULL, panel_json TEXT NOT NULL, item_count INTEGER NOT NULL, hosts TEXT, trace_id TEXT, actor_type TEXT, actor_id TEXT, rollback_of INTEGER, validated_at INTEGER, published_at INTEGER, acked_at INTEGER, ack_result TEXT, ack_error TEXT, created_at INTEGER NOT NULL, PRIMARY KEY (mac, rev));
CREATE TABLE text_i18n (hash TEXT NOT NULL, lang TEXT NOT NULL, body TEXT, created_at INTEGER, PRIMARY KEY (hash, lang));
CREATE TABLE trial_anchors (mac TEXT PRIMARY KEY, android_id TEXT, started_at INTEGER NOT NULL, extended_until INTEGER);
CREATE INDEX idx_trial_anchors_android ON trial_anchors(android_id);
CREATE TABLE trial_extensions (id TEXT PRIMARY KEY, mac TEXT NOT NULL, days INTEGER NOT NULL, previous_until INTEGER, new_until INTEGER NOT NULL, actor_type TEXT, actor_id TEXT, created_at INTEGER NOT NULL);
CREATE TABLE webhooks (
       id            TEXT PRIMARY KEY,
       url           TEXT NOT NULL,
       secret        TEXT NOT NULL,
       events        TEXT NOT NULL,
       active        INTEGER NOT NULL DEFAULT 1,
       created_at    INTEGER NOT NULL,
       last_fired_at INTEGER,
       last_status   TEXT
     );
