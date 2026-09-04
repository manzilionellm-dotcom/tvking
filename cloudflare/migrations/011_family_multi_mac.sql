-- =========================================================
--  011_family_multi_mac.sql — Ligne M3U unique partagée (multi-MAC)
-- =========================================================
--  ADDITIF uniquement : on n'efface rien, on n'écrase aucune
--  table. Les colonnes naissent à 0 / NULL → le comportement
--  actuel (302 /api/m3u/:token vers le fournisseur) reste le
--  défaut tant que le toggle panel n'est pas allumé.
--
--  Produit :
--    UNE ligne M3U amont (credentials source_json de la famille)
--    + N adresses MAC (10–12) collées en CSV dans le panel.
--    Chaque appareil s'authentifie avec SA MAC, mais tous
--    consomment le même flux fournisseur via /api/m3u/{token}.
--
--  SQLite (D1) : ALTER TABLE ADD COLUMN n'a PAS de IF NOT EXISTS.
--  Un 2e passage échoue « duplicate column » — sans gravité.
--  Le Worker applique aussi ces colonnes à la volée
--  (ensureFamilyMultiMac) donc cette migration est documentaire
--  + filet pour les bases déjà déployées.
--
--    wrangler d1 execute tvking_licensing \
--      --file=cloudflare/migrations/011_family_multi_mac.sql --remote
-- =========================================================

-- 0 = OFF (comportement actuel, zéro régression).
-- 1 = ON  (intercepter /api/m3u/:token et servir le M3U multi-MAC).
ALTER TABLE families ADD COLUMN multi_mac_enabled INTEGER NOT NULL DEFAULT 0;

-- CSV brut collé par l'admin (MAC séparées par des virgules).
-- Conservé tel quel pour ré-afficher le textarea du panel.
ALTER TABLE families ADD COLUMN multi_macs TEXT;
