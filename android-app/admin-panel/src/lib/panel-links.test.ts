import { describe, expect, it } from 'vitest';
import { loginDestination, readPanelTarget } from './panel-links';
const ORIGIN = 'https://panel.example.invalid';
const MAC = 'MK:AA:BB:CC:DD:EE';
const target = '/devices?mac=MK%3AAA%3ABB%3ACC%3ADD%3AEE';

describe('Liens d’alerte et retour après connexion', () => {
  it('ne conserve que la route et la MAC canonique autorisées', () => {
    expect(readPanelTarget(`/devices?mac=${MAC.toLowerCase()}`, ORIGIN)).toEqual({ path: '/devices', mac: MAC, url: target });
    expect(readPanelTarget(ORIGIN + target, ORIGIN)?.url).toBe(target);
    expect(readPanelTarget(target.replace('/devices', '/blackbox'), ORIGIN)?.path).toBe('/blackbox');
    expect(readPanelTarget('/devices?mac=aa:bb:cc:dd:ee:ff', ORIGIN)?.mac).toBe('AA:BB:CC:DD:EE:FF');
  });
  it.each([
    '//evil.invalid/devices?mac=' + MAC, 'https://evil.invalid/devices?mac=' + MAC,
    'javascript:alert(1)', '/devices?mac=' + MAC + '&token=private', '/devices?mac=' + MAC + '&mac=' + MAC,
    '/devices?mac=' + MAC + '#extra', '/devices?mac=bad', '/devices', '/activate?mac=' + MAC,
    '/\\evil.invalid/devices?mac=' + MAC, 'https://user:password@panel.example.invalid/devices?mac=' + MAC,
    '/devices?mac=MK:AA:BB:CC:DD:%0AEE', '/%64evices?mac=' + MAC,
  ])('refuse la destination non autorisée %s', (value) => { expect(readPanelTarget(value, ORIGIN)).toBeNull(); });
  it('préserve un lien de fiche après login et rejette les retours externes', () => {
    expect(loginDestination(target, ORIGIN)).toBe(target);
    expect(loginDestination('/account', ORIGIN)).toBe('/account');
    expect(loginDestination('https://evil.invalid', ORIGIN)).toBe('/');
    expect(loginDestination({ url: target }, ORIGIN)).toBe('/');
  });
});
