import { describe, expect, it } from 'vitest';
import { applyMacSearchEdit, macSearchDisplay, macSearchMatches } from './mac-search';
import { filterRows, pageWindow, sortRows } from '../tableView';

describe('édition mixte et filtre MAC opt-in', () => {
  it.each(['cafe', 'deadbeef', 'Jean-Pierre', 'john.doe', '192.', '192.168.0.1', 'fe80::1', 'client@example.org'])('préserve le texte %s', (text) => {
    expect(macSearchDisplay(text)).toBe(text);
  });
  it('une treizième lettre reste saisissable et restaure la casse originale', () => {
    const edit = applyMacSearchEdit('AA:BB:CC:DD:EE:FFg', 18, 'aabbccddeeff', 'backward');
    expect(edit).toEqual({ value: 'aabbccddeeffg', caret: 13 });
    expect(macSearchDisplay(edit.value)).toBe('aabbccddeeffg');
  });
  it('un email commencé comme MAC retrouve exactement son préfixe brut', () => {
    const edit = applyMacSearchEdit('AA:BB@', 6, 'aabb', 'backward');
    expect(edit).toEqual({ value: 'aabb@', caret: 5 });
  });
  it('Suppr sur le séparateur reste utilisable avec la même position de curseur', () => {
    const edit = applyMacSearchEdit('MK:FB88', 5, 'mkfb88', 'forward');
    expect(edit).toEqual({ value: 'mkfb8', caret: 5 });
    expect(macSearchDisplay(edit.value)).toBe('MK:FB:8');
  });
  it('le filtre MAC complète le texte avant tri et pagination, sans élargir une IP', () => {
    const rows = [
      { name: 'Alice', ip: '192.168.1.1', mac: 'MK:FB:88:05:2B:68' },
      { name: 'Béatrice', ip: '10.0.0.1', mac: 'AA:BB:CC:DD:EE:FF' },
      { name: 'mkfb88052b68 client', ip: '10.0.0.2', mac: '11:22:33:44:55:66' },
    ];
    const textOf = (row: typeof rows[number]) => [row.name, row.ip, row.mac].join(' ');
    const matches = (row: typeof rows[number], query: string) => macSearchMatches(row.mac, query);
    expect(filterRows(rows, 'mkfb88052b68', textOf, matches)).toHaveLength(2);
    expect(filterRows(rows, 'Béatrice', textOf, matches)).toEqual([rows[1]]);
    expect(filterRows(rows, '192.168.1.1', textOf, matches)).toEqual([rows[0]]);
    expect(macSearchMatches('19:21:68:11:AA:BB', '192.168.1.1')).toBe(false);
    const selected = sortRows(filterRows(rows, 'mkfb88052b68', textOf, matches), 'name', 'asc', (row) => row.name);
    const page = pageWindow(selected.length, 2, 1);
    expect(selected.slice(page.start, page.end)).toEqual([rows[2]]);
  });
});
