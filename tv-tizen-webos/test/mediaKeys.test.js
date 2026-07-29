// Tests de mediaKeys.js (contrat des touches média de la télécommande).
// Exécution : node --test tv-tizen-webos/test/
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { mediaKeyAction } = require('../shared/js/mediaKeys.js');

test('play/pause family maps to toggle', () => {
  assert.strictEqual(mediaKeyAction('MediaPlayPause'), 'toggle');
  assert.strictEqual(mediaKeyAction('MediaPlay'), 'toggle');
  assert.strictEqual(mediaKeyAction('MediaPause'), 'toggle');
});

test('MediaStop maps to stop', () => {
  assert.strictEqual(mediaKeyAction('MediaStop'), 'stop');
});

test('unmapped keys return null (no seek/next in live TV)', () => {
  assert.strictEqual(mediaKeyAction('MediaTrackNext'), null);
  assert.strictEqual(mediaKeyAction('MediaFastForward'), null);
  assert.strictEqual(mediaKeyAction('MediaRewind'), null);
  assert.strictEqual(mediaKeyAction('Enter'), null);
  assert.strictEqual(mediaKeyAction(''), null);
  assert.strictEqual(mediaKeyAction(undefined), null);
});
