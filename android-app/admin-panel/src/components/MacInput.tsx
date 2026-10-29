import {
  forwardRef, useCallback, useEffect, useImperativeHandle, useLayoutEffect, useRef,
  type ChangeEvent, type InputHTMLAttributes, type KeyboardEvent,
} from 'react';
import { applyMacEdit, formatMacAddress, MAC_DISPLAY_LENGTH, type MacDeleteDirection } from '@/lib/mac-format/mac';
import { applyMacSearchEdit, macSearchDisplay } from '@/lib/mac-format/mac-search';

// =========================================================
//  MacInput — champ MAC qui ajoute les « : » tout seul
// =========================================================
//  Remplace un <input> MAC : même className / placeholder / autoFocus…
//  `onValueChange` reçoit toujours la valeur formatée (« MK:FB:88:05:2B:68 »).
//  Gère la frappe, le collage, Retour arrière à travers un « : », l'édition
//  au milieu (curseur conservé) et les claviers mobiles (Android/iOS).
// =========================================================

type NativeInputProps = Omit<InputHTMLAttributes<HTMLInputElement>, 'value' | 'onChange' | 'type'>;

export interface MacInputProps extends NativeInputProps {
  value: string;
  onValueChange: (value: string) => void;
  /** Recherche mixte : affichage MAC, mais callback brut et texte libre sans limite MAC. */
  mode?: 'mac' | 'search';
}

export const MacInput = forwardRef<HTMLInputElement, MacInputProps>(function MacInput(
  { value, onValueChange, onKeyDown, mode = 'mac', ...rest },
  ref,
) {
  const inputRef = useRef<HTMLInputElement>(null);
  useImperativeHandle(ref, () => inputRef.current as HTMLInputElement);
  const pendingCaret = useRef<number | null>(null);
  const direction = useRef<MacDeleteDirection>('backward');
  const displayValue = mode === 'search' ? macSearchDisplay(value) : value;

  // Les claviers mobiles n'envoient pas toujours la touche (keyCode 229) :
  // on lit le sens de suppression via l'événement natif `beforeinput`.
  useEffect(() => {
    const el = inputRef.current;
    if (!el) return;
    const onBeforeInput = (e: Event) => {
      const t = (e as InputEvent).inputType || '';
      direction.current = t.startsWith('deleteContentForward') ? 'forward' : 'backward';
    };
    el.addEventListener('beforeinput', onBeforeInput);
    return () => el.removeEventListener('beforeinput', onBeforeInput);
  }, []);

  const handleKeyDown = useCallback((e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Delete') direction.current = 'forward';
    else if (e.key === 'Backspace') direction.current = 'backward';
    onKeyDown?.(e);
  }, [onKeyDown]);

  const handleChange = useCallback((e: ChangeEvent<HTMLInputElement>) => {
    const el = e.target;
    const res = mode === 'search'
      ? applyMacSearchEdit(el.value, el.selectionStart, value, direction.current)
      : applyMacEdit(el.value, el.selectionStart, value, direction.current);
    direction.current = 'backward';
    pendingCaret.current = res.caret;
    if (res.value === value) {
      // React ne re-rend pas : on remet la valeur et le curseur nous-mêmes.
      el.value = mode === 'search' ? macSearchDisplay(res.value) : res.value;
      try { el.setSelectionRange(res.caret, res.caret); } catch { /* input non focus */ }
      pendingCaret.current = null;
      return;
    }
    onValueChange(res.value);
  }, [value, onValueChange, mode]);

  useLayoutEffect(() => {
    const el = inputRef.current;
    const caret = pendingCaret.current;
    pendingCaret.current = null;
    if (!el || caret === null || document.activeElement !== el) return;
    try { el.setSelectionRange(caret, caret); } catch { /* ignore */ }
  }, [value]);

  return (
    <input
      {...rest}
      ref={inputRef}
      type={mode === 'search' ? 'search' : 'text'}
      value={displayValue}
      onChange={handleChange}
      onKeyDown={handleKeyDown}
      inputMode="text"
      autoCapitalize={mode === 'search' ? 'none' : 'characters'}
      autoCorrect="off"
      autoComplete="off"
      spellCheck={false}
      maxLength={mode === 'search' ? undefined : MAC_DISPLAY_LENGTH + 8 /* marge pour un collage avec espaces */}
      data-mac-input=""
    />
  );
});

/** Valeur initiale propre (ex. « ?mac=mkfb88… » dans l'URL). « MK: » reste « MK: ». */
export function initialMac(v: string | null | undefined, fallback = ''): string {
  if (!v) return fallback;
  return formatMacAddress(v) || fallback;
}
