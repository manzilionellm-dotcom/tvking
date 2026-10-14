import { useEffect, useRef, useState, type KeyboardEvent } from 'react';
import { createPortal } from 'react-dom';

// Confirmation à l'écran pour les actions destructrices.
// Remplace window.confirm : même décision (oui / non), présentation lisible.

export interface ConfirmAsk {
  title: string;
  message: string;
  confirmLabel?: string;
  cancelLabel?: string;
  danger?: boolean;
}

type Pending = ConfirmAsk & { resolve: (ok: boolean) => void };

let openAsk: ((ask: ConfirmAsk) => Promise<boolean>) | null = null;

export function confirmAction(ask: ConfirmAsk): Promise<boolean> {
  if (!openAsk) {
    return Promise.resolve(window.confirm(`${ask.title}\n\n${ask.message}`));
  }
  return openAsk(ask);
}

export function ConfirmHost() {
  const [pending, setPending] = useState<Pending | null>(null);
  const dialogRef = useRef<HTMLDivElement>(null);
  const cancelRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    openAsk = (ask) =>
      new Promise((resolve) => {
        setPending({ ...ask, resolve });
      });
    return () => {
      openAsk = null;
    };
  }, []);

  useEffect(() => {
    if (!pending) return;
    cancelRef.current?.focus();
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      document.body.style.overflow = prev;
    };
  }, [pending]);

  if (!pending) return null;

  function close(ok: boolean) {
    pending?.resolve(ok);
    setPending(null);
  }

  function onKeyDown(e: KeyboardEvent<HTMLDivElement>) {
    if (e.key === 'Escape') {
      e.preventDefault();
      close(false);
      return;
    }
    if (e.key !== 'Tab') return;
    const root = dialogRef.current;
    if (!root) return;
    const nodes = Array.from(
      root.querySelectorAll<HTMLElement>('button, [href], input, select, textarea'),
    ).filter((node) => !node.hasAttribute('disabled'));
    if (nodes.length === 0) return;
    const first = nodes[0];
    const last = nodes[nodes.length - 1];
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first.focus();
    }
  }

  return createPortal(
    <div className="fixed inset-0 z-[80] flex items-end justify-center sm:items-center sm:p-4">
      <div className="absolute inset-0 bg-black/70" onClick={() => close(false)} />
      <div
        ref={dialogRef}
        role="alertdialog"
        aria-modal="true"
        aria-labelledby="confirm-title"
        aria-describedby="confirm-body"
        onKeyDown={onKeyDown}
        className="relative w-full max-w-md rounded-t-2xl border border-white/10 bg-midnight p-6 shadow-2xl sm:rounded-2xl"
      >
        <h2 id="confirm-title" className="text-lg font-semibold tracking-tight text-ink-primary">
          {pending.title}
        </h2>
        <p id="confirm-body" className="mt-2 whitespace-pre-line text-sm leading-relaxed text-ink-secondary">
          {pending.message}
        </p>
        <div className="mt-6 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <button
            ref={cancelRef}
            type="button"
            onClick={() => close(false)}
            className="rounded-md border border-white/15 px-4 py-2.5 text-sm font-medium text-ink-primary hover:bg-white/5"
          >
            {pending.cancelLabel || 'Annuler'}
          </button>
          <button
            type="button"
            onClick={() => close(true)}
            className="rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-obsidian hover:bg-accent-bright"
          >
            {pending.confirmLabel || 'Confirmer'}
          </button>
        </div>
      </div>
    </div>,
    document.body,
  );
}
