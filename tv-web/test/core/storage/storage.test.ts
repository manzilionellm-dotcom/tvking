// =========================================================
//  storage.test.ts — Persistance LocalStorage
// =========================================================
//  jsdom fournit un localStorage natif compatible W3C — on peut donc
//  tester pour de vrai sans mock complique.
//
//  Test isolation : `_testReset()` purge l'espace tv-web entre chaque
//  test pour eviter les fuites d'etat.
// =========================================================

import { describe, it, expect, beforeEach } from 'vitest';
import {
  loadLastSource,
  saveLastSource,
  clearLastSource,
  loadLastChannelId,
  saveLastChannelId,
  loadFavorites,
  saveFavorites,
  toggleFavorite,
  _testReset,
  type PlaylistSource,
} from '../../../src/core/storage/storage.js';
import { logger } from '../../../src/core/observability/structured_logger.js';

beforeEach(() => {
  _testReset();
  logger.clearSinks();
});

describe('PlaylistSource persistence', () => {
  it('null par defaut', () => {
    expect(loadLastSource()).toBeNull();
  });

  it('roundtrip pour une source M3U', () => {
    const src: PlaylistSource = {
      kind: 'm3u',
      url: 'http://example.com/p.m3u',
    };
    saveLastSource(src);
    expect(loadLastSource()).toEqual(src);
  });

  it('roundtrip pour une source Xtream', () => {
    const src: PlaylistSource = {
      kind: 'xtream',
      serverUrl: 'http://srv.example.com',
      username: 'alice',
      password: 'wonder',
    };
    saveLastSource(src);
    expect(loadLastSource()).toEqual(src);
  });

  it('overwrite par sauvegarde successive', () => {
    saveLastSource({ kind: 'm3u', url: 'http://a' });
    saveLastSource({ kind: 'm3u', url: 'http://b' });
    expect(loadLastSource()).toEqual({ kind: 'm3u', url: 'http://b' });
  });

  it('clearLastSource() retire la valeur', () => {
    saveLastSource({ kind: 'm3u', url: 'http://x' });
    clearLastSource();
    expect(loadLastSource()).toBeNull();
  });

  it('renvoie null sur JSON corrompu (pas de throw)', () => {
    // On force une valeur invalide directement dans localStorage
    window.localStorage.setItem('tv-web:last_source', '{not json');
    expect(loadLastSource()).toBeNull();
  });

  it("renvoie null sur shape inconnue (validateur runtime)", () => {
    window.localStorage.setItem(
      'tv-web:last_source',
      JSON.stringify({ kind: 'satellite', url: 'http://x' }),
    );
    expect(loadLastSource()).toBeNull();
  });
});

describe('Last channel ID', () => {
  it('null par defaut', () => {
    expect(loadLastChannelId()).toBeNull();
  });

  it('roundtrip simple', () => {
    saveLastChannelId('xtream:42');
    expect(loadLastChannelId()).toBe('xtream:42');
  });

  it('overwrite', () => {
    saveLastChannelId('a');
    saveLastChannelId('b');
    expect(loadLastChannelId()).toBe('b');
  });
});

describe('Favorites', () => {
  it('[] par defaut', () => {
    expect(loadFavorites()).toEqual([]);
  });

  it('saveFavorites + loadFavorites roundtrip', () => {
    saveFavorites(['a', 'b', 'c']);
    expect(loadFavorites()).toEqual(['a', 'b', 'c']);
  });

  it('toggleFavorite ajoute si absent', () => {
    expect(toggleFavorite('chan-1')).toContain('chan-1');
    expect(loadFavorites()).toContain('chan-1');
  });

  it('toggleFavorite retire si present', () => {
    saveFavorites(['chan-1', 'chan-2']);
    const after = toggleFavorite('chan-1');
    expect(after).not.toContain('chan-1');
    expect(after).toContain('chan-2');
  });

  it('renvoie [] sur JSON corrompu', () => {
    window.localStorage.setItem('tv-web:favorites', 'not json');
    expect(loadFavorites()).toEqual([]);
  });

  it("renvoie [] si la donnee n'est pas un tableau de strings", () => {
    window.localStorage.setItem(
      'tv-web:favorites',
      JSON.stringify([1, 2, 3]),
    );
    expect(loadFavorites()).toEqual([]);
  });

  it('deduplique automatiquement via le Set interne du toggle', () => {
    saveFavorites(['a', 'a', 'b']);
    // saveFavorites accepte le tableau tel quel — c'est toggleFavorite
    // qui dedup. Verifions le comportement attendu : toggle dedup.
    const after = toggleFavorite('c');
    // Le tableau initial avait des doublons, le Set dedup
    const uniqueA = after.filter((x) => x === 'a').length;
    expect(uniqueA).toBe(1);
    expect(after).toContain('b');
    expect(after).toContain('c');
  });
});
