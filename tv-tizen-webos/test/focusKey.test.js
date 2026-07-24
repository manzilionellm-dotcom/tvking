// Tests de focusKey.js (dérivation de clé + mémoire de focus par écran).
// Exécution : node --test tv-tizen-webos/test/
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { keyOf, createFocusMemory } = require('../shared/js/focusKey.js');

// Faux élément minimal (getAttribute + textContent), comme un noeud DOM.
function el(attrs, text) {
  attrs = attrs || {};
  return {
    getAttribute: function (n) { return Object.prototype.hasOwnProperty.call(attrs, n) ? attrs[n] : null; },
    textContent: text || '',
  };
}

test('keyOf prefers data-fk', () => {
  assert.strictEqual(keyOf(el({ 'data-fk': 'ch:http://x/1' }, 'CNN')), 'ch:http://x/1');
});

test('keyOf falls back to normalized text', () => {
  assert.strictEqual(keyOf(el({}, '  Sport  1 \n')), 'txt:Sport 1');
});

test('keyOf returns null when nothing identifies the element', () => {
  assert.strictEqual(keyOf(el({}, '   ')), null);
  assert.strictEqual(keyOf(null), null);
  assert.strictEqual(keyOf(undefined), null);
});

test('focus memory remembers and recalls per scene', () => {
  const m = createFocusMemory();
  assert.strictEqual(m.recall('live'), null);
  m.remember('live', 'ch:5');
  m.remember('activation', 'btn:refresh');
  assert.strictEqual(m.recall('live'), 'ch:5');
  assert.strictEqual(m.recall('activation'), 'btn:refresh');
});

test('focus memory ignores null keys and blank scenes (no crash, no write)', () => {
  const store = {};
  const m = createFocusMemory(store);
  m.remember('live', null);
  m.remember('', 'ch:1');
  m.remember(null, 'ch:1');
  assert.deepStrictEqual(store, {});
  assert.strictEqual(m.recall(''), null);
  assert.strictEqual(m.recall(null), null);
});

test('later remember overwrites (last place wins) and forget clears', () => {
  const m = createFocusMemory();
  m.remember('live', 'ch:1');
  m.remember('live', 'ch:9');
  assert.strictEqual(m.recall('live'), 'ch:9');
  m.forget('live');
  assert.strictEqual(m.recall('live'), null);
});
