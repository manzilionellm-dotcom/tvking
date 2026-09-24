-- =========================================================
--  003_reseller_hierarchy.sql — Revendeurs multi-niveaux
-- =========================================================
--  Ajoute parent_reseller_id pour permettre a un revendeur de
--  creer ses propres sous-revendeurs (arbre de profondeur illimitee).
--  NULL = revendeur cree directement par l'owner (niveau 1).
--
--  A executer une fois sur une base D1 existante :
--    wrangler d1 execute tvking_licensing --remote \
--      --file=cloudflare/migrations/003_reseller_hierarchy.sql
--
--  SQLite n'a pas "ADD COLUMN IF NOT EXISTS" : un 2e passage
--  echouera "duplicate column" — sans gravite (le workflow tolere).
-- =========================================================

ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT;
CREATE INDEX IF NOT EXISTS idx_resellers_parent ON resellers(parent_reseller_id);
