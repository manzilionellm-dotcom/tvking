import { describe, expect, it } from 'vitest';
import {
  applyMacEdit, caretForUsefulCount, formatMacAddress, looksLikeMac, macMatches,
  normalizeMac, sameMac, usefulCountBefore,
} from './mac';

describe('formatMacAddress', () => {
  it.each([
    ['MKFB88052B68', 'MK:FB:88:05:2B:68'],
    ['AABBCCDDEEFF', 'AA:BB:CC:DD:EE:FF'],
    ['mkfb88052b68', 'MK:FB:88:05:2B:68'],
    ['aa:bb:cc:dd:ee:ff', 'AA:BB:CC:DD:EE:FF'],
    ['aa-bb-cc-dd-ee-ff', 'AA:BB:CC:DD:EE:FF'],
    ['aabb.ccdd.eeff', 'AA:BB:CC:DD:EE:FF'],
    [' aa bb cc dd ee ff ', 'AA:BB:CC:DD:EE:FF'],
    ['MK::FB:::88', 'MK:FB:88'],
    ['MK:FB:88:05:2B:68:99:00', 'MK:FB:88:05:2B:68'],
    ['mk!fb@88#', 'MK:FB:88'],
    ['MK:', 'MK'],
    ['M', 'M'],
    ['MKF', 'MK:F'],
    ['', ''],
  ])('%s → %s', (input, out) => {
    expect(formatMacAddress(input)).toBe(out);
    expect(formatMacAddress(input).length).toBeLessThanOrEqual(17);
  });
  it('accepte M et K (pas de validation hex stricte)', () => {
    expect(formatMacAddress('mk1234567890')).toBe('MK:12:34:56:78:90');
  });
  it('null / undefined', () => {
    expect(formatMacAddress(null)).toBe('');
    expect(formatMacAddress(undefined)).toBe('');
  });
});

describe('normalizeMac / sameMac / macMatches', () => {
  it('normalise', () => {
    expect(normalizeMac('mk:fb-88.05 2b68')).toBe('MKFB88052B68');
  });
  it('compare quel que soit le format stocké', () => {
    expect(sameMac('MK:FB:88:05:2B:68', 'mkfb88052b68')).toBe(true);
    expect(sameMac('mk-fb-88-05-2b-68', 'MK:FB:88:05:2B:68')).toBe(true);
    expect(sameMac('', '')).toBe(false);
  });
  it('recherche partielle', () => {
    expect(macMatches('MK:FB:88:05:2B:68', 'fb88')).toBe(true);
    expect(macMatches('mk:fb:88:05:2b:68', 'FB-88-05')).toBe(true);
    expect(macMatches('MK:FB:88:05:2B:68', 'B8805')).toBe(true);
    expect(macMatches('MK:FB:88:05:2B:68', 'zz')).toBe(false);
    expect(macMatches('MK:FB:88:05:2B:68', '')).toBe(false);
  });
  it('looksLikeMac', () => {
    expect(looksLikeMac('mkfb88')).toBe(true);
    expect(looksLikeMac('fb-88')).toBe(true);
    expect(looksLikeMac('AABBCC')).toBe(true);
    expect(looksLikeMac('salon')).toBe(false);
    expect(looksLikeMac('jean dupont')).toBe(false);
    expect(looksLikeMac('MK')).toBe(false);
  });
});

describe('curseur', () => {
  it('caretForUsefulCount', () => {
    expect([0, 1, 2, 3, 4, 5, 12].map(caretForUsefulCount)).toEqual([0, 1, 2, 4, 5, 7, 17]);
  });
  it('usefulCountBefore', () => {
    expect(usefulCountBefore('MK:FB:88', 3)).toBe(2);
    expect(usefulCountBefore('MK:FB:88', 5)).toBe(4);
  });
});

/** Simule une frappe : insère `text` à `caret` dans `value` (sélection éventuelle). */
function type(value: string, caret: number, text: string, selEnd = caret) {
  const raw = value.slice(0, caret) + text + value.slice(selEnd);
  return applyMacEdit(raw, caret + text.length, value);
}
function backspace(value: string, caret: number) {
  const raw = value.slice(0, caret - 1) + value.slice(caret);
  return applyMacEdit(raw, caret - 1, value, 'backward');
}
function del(value: string, caret: number) {
  const raw = value.slice(0, caret) + value.slice(caret + 1);
  return applyMacEdit(raw, caret, value, 'forward');
}

describe('applyMacEdit — saisie progressive', () => {
  it('frappe caractère par caractère', () => {
    let v = '';
    for (const ch of 'mkfb88052b68') v = type(v, v.length, ch).value;
    expect(v).toBe('MK:FB:88:05:2B:68');
  });
  it('le curseur passe après le « : » ajouté', () => {
    expect(type('MK', 2, 'f')).toEqual({ value: 'MK:F', caret: 4 });
  });
  it('part du pré-remplissage « MK: »', () => {
    expect(type('MK:', 3, '1')).toEqual({ value: 'MK:1', caret: 4 });
    expect(backspace('MK:', 3)).toEqual({ value: 'MK', caret: 2 });
  });
  it('bloque au-delà de 12 caractères utiles', () => {
    expect(type('MK:FB:88:05:2B:68', 17, '9')).toEqual({ value: 'MK:FB:88:05:2B:68', caret: 17 });
    expect(type('MK:FB:88:05:2B:68', 3, '9')).toEqual({ value: 'MK:FB:88:05:2B:68', caret: 2 });
  });
  it('ignore les caractères invalides', () => {
    expect(type('MK:F', 4, '#')).toEqual({ value: 'MK:F', caret: 4 });
  });
  it('« : » tapé à la main → pas de double deux-points', () => {
    expect(type('MK', 2, ':')).toEqual({ value: 'MK', caret: 2 });
    expect(type('MK:FB', 5, ':').value).toBe('MK:FB');
  });
});

describe('applyMacEdit — collage', () => {
  it('collage complet sans séparateur', () => {
    expect(type('', 0, 'mkfb88052b68')).toEqual({ value: 'MK:FB:88:05:2B:68', caret: 17 });
  });
  it('collage avec tirets / espaces', () => {
    expect(type('', 0, ' aa-bb-cc-dd-ee-ff ').value).toBe('AA:BB:CC:DD:EE:FF');
  });
  it('collage qui remplace une sélection', () => {
    expect(type('MK:FB:88:05:2B:68', 0, 'aabbccddeeff', 17).value).toBe('AA:BB:CC:DD:EE:FF');
  });
  it('collage trop long tronqué à 17', () => {
    expect(type('', 0, 'MKFB88052B6899').value).toBe('MK:FB:88:05:2B:68');
  });
});

describe('applyMacEdit — suppression et édition au milieu', () => {
  it('Retour arrière en fin', () => {
    expect(backspace('MK:FB:8', 7)).toEqual({ value: 'MK:FB', caret: 5 });
  });
  it('Retour arrière juste après un « : » efface le caractère utile précédent', () => {
    expect(backspace('MK:FB:88', 6)).toEqual({ value: 'MK:F8:8', caret: 4 });
  });
  it('Suppr juste avant un « : » efface le caractère utile suivant', () => {
    expect(del('MK:FB:88', 5)).toEqual({ value: 'MK:FB:8', caret: 5 });
  });
  it('Retour arrière au milieu conserve la position', () => {
    // MK:F|B:88 → supprime F
    expect(backspace('MK:FB:88', 4)).toEqual({ value: 'MK:B8:8', caret: 2 }); // MK|:B8:8
  });
  it('insertion au milieu conserve la position', () => {
    // MK:|FB → tape 1 → MK:1F:B, curseur après 1
    expect(type('MK:FB', 3, '1')).toEqual({ value: 'MK:1F:B', caret: 4 });
  });
  it('MAC incomplète reste éditable', () => {
    expect(formatMacAddress('MKFB8')).toBe('MK:FB:8');
  });
  it('tout effacer', () => {
    expect(applyMacEdit('', 0, 'MK:FB:88:05:2B:68')).toEqual({ value: '', caret: 0 });
  });
});
