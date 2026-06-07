-- =========================================================
--  006_app_nova.sql — Ajoute l'app NOVA+ (TV) au panel
-- =========================================================
--  NOVA+ est la nouvelle app Android TV / Fire TV (front Next.js
--  empaquete en WebView). On l'ajoute dans la table `apps` pour qu'elle
--  apparaisse dans le panneau (liste Applications + menu Activer) avec
--  son lien Downloader copiable. INSERT OR IGNORE + UPDATE = idempotent
--  (re-executer la migration ne casse rien et garde le lien a jour).
-- =========================================================

INSERT OR IGNORE INTO apps (
  id, name, package_name, primary_color, tagline,
  default_playlist_type, download_url, is_active, created_at, updated_at
) VALUES (
  'app_nova', 'NOVA+', 'com.nova.plus', '#e3b96b',
  'La television, simple et premium',
  'none', 'https://99999.7themotion.com/nova', 1,
  CAST(strftime('%s','now') AS INTEGER) * 1000,
  CAST(strftime('%s','now') AS INTEGER) * 1000
);

-- Si la ligne existait deja (re-run), on s'assure que le lien et le nom
-- restent corrects.
UPDATE apps
   SET name = 'NOVA+',
       download_url = 'https://99999.7themotion.com/nova',
       primary_color = '#e3b96b',
       is_active = 1,
       updated_at = CAST(strftime('%s','now') AS INTEGER) * 1000
 WHERE id = 'app_nova';
