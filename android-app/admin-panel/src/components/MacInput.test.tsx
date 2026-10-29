// @vitest-environment jsdom
import { act, useState } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { MacInput, initialMac } from './MacInput';

(globalThis as any).IS_REACT_ACT_ENVIRONMENT = true;

let host: HTMLDivElement;
let root: Root;
let last = '';

function Harness({ start = '' }: { start?: string }) {
  const [v, setV] = useState(start);
  last = v;
  return <MacInput value={v} onValueChange={setV} placeholder="MK:XX:XX:XX:XX:XX" />;
}

const input = () => host.querySelector('input') as HTMLInputElement;

/** Reproduit ce que fait le navigateur : nouvelle valeur + curseur, puis événement input. */
function edit(raw: string, caret: number, inputType = 'insertText') {
  const el = input();
  act(() => {
    el.dispatchEvent(new InputEvent('beforeinput', { inputType, bubbles: true, cancelable: true }));
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
    setter.call(el, raw);
    el.setSelectionRange(caret, caret);
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

beforeEach(() => {
  host = document.createElement('div');
  document.body.appendChild(host);
  root = createRoot(host);
});
afterEach(() => { act(() => root.unmount()); host.remove(); });

describe('MacInput (DOM)', () => {
  it('attributs mobiles', () => {
    act(() => root.render(<Harness />));
    const el = input();
    expect(el.getAttribute('autocapitalize')).toBe('characters');
    expect(el.getAttribute('autocorrect')).toBe('off');
    expect(el.getAttribute('spellcheck')).toBe('false');
    expect(el.getAttribute('autocomplete')).toBe('off');
    expect(el.type).toBe('text');
  });

  it('frappe progressive + curseur', () => {
    act(() => root.render(<Harness />));
    input().focus();
    let v = '';
    for (const ch of 'mkfb88052b68') {
      edit(v + ch, v.length + 1);
      v = input().value;
      expect(input().selectionStart).toBe(v.length);
    }
    expect(last).toBe('MK:FB:88:05:2B:68');
  });

  it('collage', () => {
    act(() => root.render(<Harness />));
    input().focus();
    edit('aa-bb-cc-dd-ee-ff', 17, 'insertFromPaste');
    expect(input().value).toBe('AA:BB:CC:DD:EE:FF');
  });

  it('Retour arrière à travers un « : » (clavier mobile, beforeinput)', () => {
    act(() => root.render(<Harness start="MK:FB:88" />));
    input().focus();
    edit('MK:FB88', 5, 'deleteContentBackward');
    expect(input().value).toBe('MK:F8:8');
    expect(input().selectionStart).toBe(4);
  });

  it('Suppr à travers un « : »', () => {
    act(() => root.render(<Harness start="MK:FB:88" />));
    input().focus();
    edit('MK:FB88', 5, 'deleteContentForward');
    expect(input().value).toBe('MK:FB:8');
    expect(input().selectionStart).toBe(5);
  });

  it('édition au milieu : curseur conservé', () => {
    act(() => root.render(<Harness start="MK:FB" />));
    input().focus();
    edit('MK:1FB', 4);
    expect(input().value).toBe('MK:1F:B');
    expect(input().selectionStart).toBe(4);
  });

  it('caractère refusé : valeur et curseur intacts', () => {
    act(() => root.render(<Harness start="MK:FB:88:05:2B:68" />));
    input().focus();
    edit('MK:FB:88:05:2B:689', 18);
    expect(input().value).toBe('MK:FB:88:05:2B:68');
    expect(input().selectionStart).toBe(17);
  });

  it('initialMac', () => {
    expect(initialMac('mkfb88052b68')).toBe('MK:FB:88:05:2B:68');
    expect(initialMac(null, 'MK:')).toBe('MK:');
  });
});
