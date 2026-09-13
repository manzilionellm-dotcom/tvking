-- =========================================================
--  011_device_admin_note.sql — Note client (WhatsApp / tél / remarque)
-- =========================================================
--  Le panel /devices a besoin d'un champ LIBRE par MAC (prénom WhatsApp,
--  numéro, « payé cash le 12/09 »). `label` reste l'étiquette appareil
--  (« Salon Fire TV ») : on n'y mélange pas le carnet client.
--
--  ALTER tolérant : re-passage = duplicate column → ignoré par le
--  workflow Setup D1 (même convention que 004_device_block).
-- =========================================================

ALTER TABLE devices ADD COLUMN admin_note TEXT;
