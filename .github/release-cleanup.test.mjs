// Les canaux actifs et une entrée shell malveillante ne sont jamais des tags nettoyables.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cleanupTags } from './release-cleanup.mjs';

test('anciens builds valides : ordre préservé et doublons retirés', () => {
  assert.deepEqual(cleanupTags('build-522 cast-1132 build-522\nbuild-526'), ['build-522', 'cast-1132', 'build-526']);
});
for (const tag of ['zuno-tv', 'zuno-tv-test', 'zuno-windows', 'latest', 'prive-latest', 'phone-latest', 'phone-test', '7motion-test', 'tv-prod', 'cinema-test', 'nouveau-canal']) {
  test(`${tag} : aucun mélange avec un ancien build ne peut le supprimer`, () => assert.throws(() => cleanupTags(`build-522 ${tag}`)));
}
for (const input of [undefined, '', ' ', 'build-1; touch /tmp/interdit', '$(touch /tmp/interdit)', '`touch /tmp/interdit`', '--help', '../build-1', 'build-1\n--yes', 'build-12345678901', 'x'.repeat(1001), Array.from({ length: 21 }, (_, i) => `build-${i}`).join(' ')]) {
  test(`entrée invalide ${String(input).slice(0,28)} : refus avant toute suppression`, () => assert.throws(() => cleanupTags(input)));
}
