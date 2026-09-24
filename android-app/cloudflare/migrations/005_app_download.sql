-- =========================================================
--  005_app_download.sql — Lien de telechargement par app
-- =========================================================
--  Ajoute download_url sur apps (lien Downloader/APK a donner aux
--  clients), et renseigne les 2 apps connues avec leurs liens
--  Cloudflare (proxy APK via le worker).
-- =========================================================

ALTER TABLE apps ADD COLUMN download_url TEXT;

UPDATE apps SET download_url = 'https://99999.7themotion.com/dl'
  WHERE id = 'app_7motion';
UPDATE apps SET download_url = 'https://99999.7themotion.com/redroom'
  WHERE id = 'app_redroom';
