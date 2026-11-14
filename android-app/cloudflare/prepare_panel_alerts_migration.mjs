#!/usr/bin/env node
// Prépare seulement le SQL à relire/appliquer. Aucun appel D1 ou réseau.
// Les deux CREATE recovery restent extraits de la fonction déjà validée :
// il n'est pas nécessaire de modifier son module pour exposer le schéma.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { panelAlertSchemaStatements, panelAlertTriggerStatements } from './panel-alerts.js';

const here = dirname(fileURLToPath(import.meta.url));
const sha256 = (value) => createHash('sha256').update(value).digest('hex');

export function buildPanelAlertsMigration() {
  const recovery = readFileSync(join(here, 'novatube4k-recovery.js'), 'utf8');
  const start = recovery.indexOf('async function schema(env) {');
  const end = recovery.indexOf('\n// La portée exige', start);
  assert.ok(start >= 0 && end > start, 'Fonction de schéma recovery non reconnue');
  const definitions = [...recovery.slice(start, end).matchAll(/env\.DB\.prepare\(`(CREATE TABLE IF NOT EXISTS [\s\S]*?)`\)/g)]
    .map((match) => match[1]);
  assert.equal(definitions.length, 2, 'Exactement deux CREATE recovery attendus');
  assert.ok(definitions[0].startsWith('CREATE TABLE IF NOT EXISTS novatube4k_recovery_requests ('));
  assert.ok(definitions[1].startsWith('CREATE TABLE IF NOT EXISTS novatube4k_recovery_guard ('));
  assert.ok(definitions.every((sql) => !sql.includes('${')), 'Interpolation recovery inattendue');
  const existingTables = ['devices', 'licenses', 'box_orders', 'novatube4k_devices'];
  const statements = [...definitions, ...panelAlertSchemaStatements(),
    ...panelAlertTriggerStatements([...existingTables, 'novatube4k_recovery_requests'])];
  for (const sql of statements) {
    assert.ok(/^CREATE (?:TABLE|INDEX|TRIGGER) IF NOT EXISTS\b/.test(sql)
      || /^INSERT OR IGNORE INTO panel_alert_meta\(id, installed_at\) VALUES\(1, /.test(sql),
    'Instruction de migration hors portée');
  }
  const sql = '-- Migration additive Atlas : aucune modification de licence, appareil ou source.\n'
    + statements.map((statement) => statement.trim().replace(/;$/, '') + ';').join('\n\n') + '\n';
  const sourceNames = ['novatube4k-recovery.js', 'panel-alerts.js', 'prepare_panel_alerts_migration.mjs'];
  return {
    format: 1,
    name: 'atlas-panel-owner-alerts-v1',
    preconditions: { existing_tables: existingTables, production_version: 318 },
    source_sha256: Object.fromEntries(sourceNames.map((name) => [name, sha256(readFileSync(join(here, name)))])),
    statement_count: statements.length,
    statement_sha256: statements.map((statement) => sha256(statement)),
    statements,
    sql,
    sql_sha256: sha256(sql),
    data_writes: ['panel_alert_meta: INSERT OR IGNORE id=1, installed_at=heure D1'],
    existing_business_rows_modified: false,
    replay_safe: true,
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const output = process.argv[2];
  if (!output) throw new Error('Usage: node prepare_panel_alerts_migration.mjs /chemin/dossier-preuves');
  const migration = buildPanelAlertsMigration();
  mkdirSync(output, { recursive: true });
  writeFileSync(join(output, 'panel-alerts-migration.sql'), migration.sql);
  writeFileSync(join(output, 'panel-alerts-migration.json'), JSON.stringify(migration, null, 2) + '\n');
  console.log(JSON.stringify({ statement_count: migration.statement_count, sql_sha256: migration.sql_sha256,
    source_sha256: migration.source_sha256, existing_business_rows_modified: false }));
}
