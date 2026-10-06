// =========================================================
//  instant.test.ts — « Envoi instantané » : la liste est-elle sur la TV ?
//  node --experimental-strip-types --test src/lib/instant.test.ts
//  Adresses en example.test, identifiants fictifs.
// =========================================================
import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  INSTANT_GIVE_UP_MS,
  INSTANT_POLL_MS,
  allOnTv,
  hostKey,
  instantLabel,
  listOnTv,
  userFromGetPhp,
} from './instant.ts';

test('hôte comme la box : minuscules, port seulement s’il est écrit', () => {
  assert.equal(hostKey('http://Serveur.Example.test:8080/get.php?username=a&password=b'), 'serveur.example.test:8080');
  assert.equal(hostKey('http://serveur.example.test/get.php'), 'serveur.example.test');
  assert.equal(hostKey('serveur.example.test:25461'), 'serveur.example.test:25461');
  assert.equal(hostKey(''), '');
  assert.equal(hostKey('pas une adresse'), 'pas une adresse'.includes(' ') ? hostKey('pas une adresse') : '');
});

test('M3U : même hôte = sur la TV ; autre hôte = pas vue', () => {
  const inv = [
    { type: 'm3u' as const, server: 'serveur.example.test:8080', username: '', channels: 18230 },
    { type: 'xtream' as const, server: 'autre.example.test', username: 'u1', channels: 900 },
  ];
  const hit = listOnTv(inv, { type: 'm3u', m3u_url: 'http://serveur.example.test:8080/get.php?username=x&password=y' });
  assert.ok(hit && hit.channels === 18230);
  assert.equal(listOnTv(inv, { type: 'm3u', m3u_url: 'http://inconnu.example.test/get.php' }), null);
  // Un type différent sur le même hôte n’est pas la même liste.
  assert.equal(listOnTv(inv, { type: 'xtream', server_url: 'http://serveur.example.test:8080', username: 'u1' }), null);
});

test('Xtream : hôte ET identifiant', () => {
  const inv = [{ type: 'xtream' as const, server: 'srv.example.test:25461', username: 'client1', channels: 4200 }];
  assert.ok(listOnTv(inv, { type: 'xtream', server_url: 'http://srv.example.test:25461', username: 'client1' }));
  assert.equal(listOnTv(inv, { type: 'xtream', server_url: 'http://srv.example.test:25461', username: 'client2' }), null);
  assert.equal(listOnTv(null, { type: 'xtream', server_url: 'http://srv.example.test:25461', username: 'client1' }), null);
});

test('lien get.php envoyé en M3U, lu par la box comme compte Xtream', () => {
  assert.equal(userFromGetPhp('http://srv.example.test:80/get.php?username=u9&password=p9&type=m3u_plus'), 'u9');
  assert.equal(userFromGetPhp('http://srv.example.test/liste.m3u'), '');
  assert.equal(userFromGetPhp('http://srv.example.test/get.php?username=u9'), '');
  const inv = [{ type: 'xtream' as const, server: 'srv.example.test:80', username: 'u9', channels: 3100 }];
  const hit = listOnTv(inv, { type: 'm3u', m3u_url: 'http://srv.example.test:80/get.php?username=u9&password=p9' });
  assert.ok(hit && hit.channels === 3100);
  // Autre identifiant sur le même serveur : pas la même liste.
  assert.equal(listOnTv(inv, { type: 'm3u', m3u_url: 'http://srv.example.test:80/get.php?username=u8&password=p8' }), null);
  // Un vrai fichier .m3u n'est jamais pris pour un compte Xtream.
  assert.equal(listOnTv(inv, { type: 'm3u', m3u_url: 'http://srv.example.test:80/liste.m3u' }), null);
});

test('plusieurs listes : vues et manquantes', () => {
  const inv = [{ type: 'm3u' as const, server: 'a.example.test', channels: 10 }];
  const r = allOnTv(inv, [
    { type: 'm3u', m3u_url: 'http://a.example.test/l.m3u' },
    { type: 'm3u', m3u_url: 'http://b.example.test/l.m3u' },
  ]);
  assert.equal(r.seen.length, 1);
  assert.equal(r.missing, 1);
});

test('phrases : vue, en attente, abandon avec la raison', () => {
  const ok = instantLabel({ elapsedMs: 14_300, seen: [{ type: 'm3u', server: 'a', channels: 18230 }], missing: 0, lastSeen: 0, now: 0 });
  assert.equal(ok.kind, 'ok');
  assert.match(ok.text, /après 14 s/);
  assert.match(ok.text, /18 230 chaînes|18 230 chaînes/);

  const wait = instantLabel({ elapsedMs: 3_400, seen: [], missing: 1, lastSeen: 0, now: 0 });
  assert.equal(wait.kind, 'wait');
  assert.match(wait.text, /3,4 s/);

  const now = 1_700_000_000_000;
  const never = instantLabel({ elapsedMs: INSTANT_GIVE_UP_MS, seen: [], missing: 1, lastSeen: 0, now });
  assert.equal(never.kind, 'late');
  assert.match(never.text, /jamais connectée/);
  const off = instantLabel({ elapsedMs: INSTANT_GIVE_UP_MS, seen: [], missing: 1, lastSeen: now - 20 * 60_000, now });
  assert.match(off.text, /il y a 20 min/);
  const online = instantLabel({ elapsedMs: INSTANT_GIVE_UP_MS, seen: [], missing: 1, lastSeen: now - 30_000, now });
  assert.match(online.text, /en ligne/);
});

test('cadence : relecture 2 s, abandon 2 min', () => {
  assert.equal(INSTANT_POLL_MS, 2000);
  assert.equal(INSTANT_GIVE_UP_MS, 120_000);
});
