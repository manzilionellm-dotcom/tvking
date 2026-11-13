// Boîte noire : le panel lit le journal et dit la panne en clair.
// Extrait d'un vrai journal (13/11/2026), chemin et identifiants retirés.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { diagnoseBlackBox } from './blackboxDiagnosis.ts';

const REAL = `
05/10 21:15:45 I [BOOT] ===== démarrage Zuno TV v106.0.13+13 =====
05/10 21:15:45 E [Zone] SqfliteFfiException(sqlite_error: 1, , SqliteException(1): while preparing statement, no such column: hidden, SQL logic error (code 1)
05/10 21:59:54 E [GEL] fil UI bloqué ~62560 ms
06/10 00:05:17 E [GEL] fil UI bloqué ~7515518 ms
13/11 12:49:44 I [BOOT] ===== démarrage ZUNO TV v113.0.3+3 =====
13/11 12:49:44 F [EXIT] session précédente : FERMETURE BRUTALE · raison inconnue (Android < 11)
13/11 12:50:14 I [MEM] [périodique] rss 1032 Mo
13/11 12:51:34 I [SOURCE] nouvelle liste Xtream (lien) reçue du panel : chargement
13/11 12:51:34 W [SOURCE] liste Xtream (lien) du panel refusée après 0.3 s : SqfliteFfiException(sqlite_error: 1, , SqliteException(1): while preparing statement, table playlists has no column n…
13/11 12:51:41 I [DIRECT] 0 chaînes · 0 catégories
13/11 12:52:11 I [PANEL] ordre source n°3 en échec : refused (révision 2) trace=x
13/11 12:52:47 W [SOURCE] ajout source ouverte échoué (SqfliteFfiException)
13/11 12:54:44 I [MEM] [périodique] rss 1320 Mo
`;

test('le vrai journal : la base abîmée est LA cause, dite une seule fois', () => {
  const d = diagnoseBlackBox(REAL);
  assert.equal(d.version, '113.0.3+3');
  assert.equal(d.lastBoot, '13/11 12:49:44');
  const top = d.findings[0];
  assert.equal(top.id, 'db_schema');
  assert.equal(top.severity, 'critical');
  assert.equal(top.current, true);
  assert.match(top.why, /« hidden »/);
  assert.match(top.evidence, /no column n|no such column/);
  // Les conséquences ne sont pas présentées comme d'autres pannes.
  const ids = d.findings.map((f) => f.id);
  for (const hidden of ['panel_refused', 'manual_add', 'panel_order', 'no_channels']) {
    assert.ok(!ids.includes(hidden), hidden);
  }
  // La mémoire est signalée à part, avec le vrai maximum.
  const mem = d.findings.find((f) => f.id === 'memory');
  assert.ok(mem);
  assert.match(mem.title, /1320 Mo/);
});

test('un écran figé pendant des heures est une mise en veille, pas une panne', () => {
  const d = diagnoseBlackBox(REAL);
  const freeze = d.findings.find((f) => f.id === 'ui_freeze');
  assert.ok(freeze);
  assert.equal(freeze.count, 1);       // 62 s compte, 2 heures non
  assert.equal(freeze.current, false); // c'était avant le dernier démarrage
});

test('ajout à la main : le type d’erreur donne la cause et le geste', () => {
  const log = (kind: string) => `
01/01 10:00:00 I [BOOT] ===== démarrage ZUNO TV v117.0.0+1 =====
01/01 10:01:00 W [SOURCE] ajout source ouverte échoué (${kind})`;
  const of = (kind: string) => diagnoseBlackBox(log(kind)).findings.find((f) => f.id === 'manual_add');
  assert.match(of('SocketException')!.why, /joindre le serveur/);
  assert.match(of('TimeoutException')!.why, /trop lentement/);
  assert.match(of('FormatException')!.action, /abonnement expiré|identifiants/);
  assert.match(of('PlaylistDeletedException')!.action, /à la main/);
  // Type inconnu : on le dit, sans inventer une cause.
  assert.match(of('TrucInconnu')!.why, /ne détaille pas/);
});

test('coupures de lecture : signalées à partir de trois', () => {
  const cut = '01/01 10:05:00 W [PLAYER] reconnexion dans 1000ms (tentative 1/5) après gel 15 s';
  const boot = '01/01 10:00:00 I [BOOT] ===== démarrage ZUNO TV v117.0.0+1 =====';
  const two = diagnoseBlackBox([boot, cut, cut].join('\n'));
  assert.equal(two.findings.find((f) => f.id === 'playback_cuts'), undefined);
  const many = diagnoseBlackBox([boot, ...Array(12).fill(cut)].join('\n'));
  const f = many.findings.find((x) => x.id === 'playback_cuts');
  assert.equal(f!.severity, 'critical');
  assert.equal(f!.count, 12);
});

test('journal vide ou sain : aucun diagnostic inventé', () => {
  assert.deepEqual(diagnoseBlackBox('').findings, []);
  const ok = diagnoseBlackBox(`
01/01 10:00:00 I [BOOT] ===== démarrage ZUNO TV v117.0.0+1 =====
01/01 10:00:05 I [MEM] [boot] rss 310 Mo
01/01 10:00:09 I [DIRECT] 812 chaînes · 40 catégories`);
  assert.deepEqual(ok.findings, []);
  assert.equal(ok.version, '117.0.0+1');
});
