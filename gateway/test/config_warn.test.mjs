// =========================================================
//  config_warn.test.mjs — warnConfig (avertissements NON bloquants)
// =========================================================
//  On vérifie que le gateway JUGE PUBLIC_BASE avec le MÊME contrat que le
//  Worker (validateFacadeBase) : seul « https + vrai domaine » est sondable
//  (aucun avertissement) ; tout le reste FONCTIONNE mais déclenche un
//  avertissement « informatif » clair. warnConfig prend un cfg en argument →
//  aucun besoin de toucher process.env (tests purs, déterministes).
import test from 'node:test';
import assert from 'node:assert/strict';
import { warnConfig } from '../src/config.js';

// Petit fabricant de cfg minimal pour n'exercer que la logique PUBLIC_BASE.
const cfg = (publicBase) => ({ publicBase });
const codes = (pb) => warnConfig(cfg(pb)).map((w) => w.code);

test('https + vrai domaine → SONDABLE, aucun avertissement (cas « vert »)', () => {
  assert.deepEqual(codes('https://gw.7themotion.com'), []);
});

test('PUBLIC_BASE vide → avertit (pas de réécriture de façade)', () => {
  assert.deepEqual(codes(''), ['public_base_missing']);
});

test('http (au lieu de https) → non sondable, avertit', () => {
  assert.deepEqual(codes('http://gw.7themotion.com'), ['public_base_not_https']);
});

test('https sur IP brute → non sondable, avertit', () => {
  assert.deepEqual(codes('https://167.233.193.51'), ['public_base_ip']);
});

test('http sur IP brute → non-https prime (un seul avertissement clair)', () => {
  // On signale d'abord le protocole : c'est le premier levier à corriger.
  assert.deepEqual(codes('http://167.233.193.51'), ['public_base_not_https']);
});

test('URL illisible → avertissement invalide (jamais un crash)', () => {
  assert.deepEqual(codes('pas-une-url'), ['public_base_invalid']);
});

test('le message d’avertissement est humain et actionnable', () => {
  const w = warnConfig(cfg('http://gw.7themotion.com'))[0];
  assert.match(w.message, /https/i);
  assert.ok(w.message.length > 40, 'le message doit expliquer, pas juste un code');
});
