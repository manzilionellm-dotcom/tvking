import assert from 'node:assert/strict';
import { sanitizeBanners } from './banners.js';

const clean = sanitizeBanners({
  items: [
    {
      id: 'cdm',
      image: 'https://cdn.example/cdm.jpg',
      title: 'Coupe',
      subtitle: 'Direct',
      label: '',
      cta: 'Regarder',
      channel: 'beIN',
      url: 'http://insecure.example/x',
      from: 10,
      until: 20,
      kids: false,
    },
    { id: 'cdm', image: 'https://cdn.example/autre.jpg' },
    { id: 'clair', image: 'http://cdn.example/x.jpg' },
    { id: '', image: 'https://cdn.example/x.jpg' },
  ],
}, 1700000000000);

assert.equal(clean.items.length, 1);
assert.equal(clean.items[0].label, 'Publicité');
assert.equal(clean.items[0].url, '');
assert.equal(clean.items[0].image.startsWith('https://'), true);
assert.equal(clean.dropped, 3);
assert.equal(clean.version, 1700000000000);

const empty = sanitizeBanners({ items: [] }, 5);
assert.deepEqual(empty.items, []);

const junk = sanitizeBanners('pas du json', 1);
assert.deepEqual(junk.items, []);

console.log('PASS banners');
