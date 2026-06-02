-- =========================================================
--  004_device_block.sql — Blocage / bannissement par appareil
-- =========================================================
--  Ajoute block_status sur devices pour que l'admin (ou un revendeur
--  sur ses appareils) puisse a distance :
--    - 'frozen'  : geler → l'app figee affiche son ecran "compte gele"
--                  (= rappel de payer)
--    - 'banned'  : bannir → l'app affiche "banni" (abus)
--    - NULL/'active' : normal (essai ou licence)
--
--  A executer une fois (le workflow Setup D1 l'applique, tolerant aux
--  re-passages "duplicate column").
-- =========================================================

ALTER TABLE devices ADD COLUMN block_status TEXT;
