// Export CSV du panel : lisible par Excel, sans formule piégée.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { csvCell, toCsv } from './csv.ts';

test('cellules : guillemets, point-virgule et retours à la ligne protégés', () => {
  assert.equal(csvCell('Client 1'), 'Client 1');
  assert.equal(csvCell('a;b'), '"a;b"');
  assert.equal(csvCell('dit "oui"'), '"dit ""oui"""');
  assert.equal(csvCell(null), '');
  assert.equal(csvCell(42), '42');
});

test('une cellule ne peut pas devenir une formule Excel', () => {
  assert.equal(csvCell('=1+1'), "'=1+1");
  assert.equal(csvCell('+33 6'), "'+33 6");
  assert.equal(csvCell('@cmd'), "'@cmd");
  assert.equal(csvCell('-5'), "'-5");
  assert.equal(csvCell('MK:00:11'), 'MK:00:11');
});

test('fichier : marque UTF-8, séparateur ;, lignes Windows', () => {
  assert.equal(
    toCsv(['MAC', 'Client'], [['MK:01', 'Élodie'], ['MK:02', 'a;b']]),
    '﻿MAC;Client\r\nMK:01;Élodie\r\nMK:02;"a;b"\r\n',
  );
});
