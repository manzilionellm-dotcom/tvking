import { useEffect, useState } from 'react';
import { cn } from '@/lib/utils';
import { awaitRtOutcome } from '@/lib/realtime';
import type { RtInfo } from '@/lib/api';

// =========================================================
//  Toast — notifications éphémères partagées (impératif)
// =========================================================
//  Usage : toast('Message', 'success') depuis n'importe où (pas besoin
//  de contexte React). Le <ToastHost /> est monté une fois dans
//  AppLayout et affiche la pile en bas à droite, auto-dismiss 4 s.
// =========================================================

export type ToastKind = 'info' | 'success' | 'warning' | 'error';

interface ToastItem {
  id: number;
  msg: string;
  kind: ToastKind;
}

let nextId = 1;
let pushFn: ((t: ToastItem) => void) | null = null;
// File d'attente si un toast part avant que le host soit monté.
const pending: ToastItem[] = [];

/// Affiche un toast (appelable hors React).
export function toast(msg: string, kind: ToastKind = 'info'): void {
  const item: ToastItem = { id: nextId++, msg, kind };
  if (pushFn) pushFn(item);
  else pending.push(item);
}

/// Feedback standard « action instantanée » à partir du champ `rt` des
/// réponses de mutation (spec §4) — machine à états partagée awaitRtOutcome :
///   delivered ≥ 1 → « ⚡ Appliqué… » tout de suite, puis le verdict ;
///   delivered = 0 → « Appareil hors ligne — appliqué à sa prochaine connexion. »
export async function rtActionFeedback(rt?: RtInfo | null): Promise<void> {
  if (rt && rt.delivered >= 1) toast("⚡ Appliqué sur l'appareil…", 'info');
  const out = await awaitRtOutcome(rt);
  switch (out.status) {
    case 'acked':
      // Latence affichée seulement si le hub la connaît (jamais « null ms »).
      toast(
        `✓ Appliqué sur l'appareil${typeof out.latencyMs === 'number' ? ` en ${out.latencyMs} ms` : ''}`,
        'success',
      );
      break;
    case 'ack_error':
      toast(
        out.error
          ? `L'appareil a signalé une erreur : ${out.error}`
          : "L'appareil a signalé une erreur.",
        'error',
      );
      break;
    case 'timeout':
      toast("Pas de confirmation reçue — l'appareil appliquera au prochain contact.", 'warning');
      break;
    case 'offline':
      toast('Appareil hors ligne — appliqué à sa prochaine connexion.', 'warning');
      break;
    case 'none':
      break; // backend sans temps réel → silence (fail-open)
  }
}

const KIND_CLS: Record<ToastKind, string> = {
  info: 'border-white/10 bg-midnight text-ink-primary',
  success: 'border-success/30 bg-success/10 text-success',
  warning: 'border-warning/30 bg-warning/10 text-warning',
  error: 'border-accent/30 bg-accent/10 text-accent-bright',
};

/// Hôte des toasts — monté une seule fois (AppLayout).
export function ToastHost() {
  const [items, setItems] = useState<ToastItem[]>([]);

  useEffect(() => {
    pushFn = (t) => {
      setItems((prev) => [...prev, t]);
      // Auto-dismiss après 4 s.
      setTimeout(() => {
        setItems((prev) => prev.filter((x) => x.id !== t.id));
      }, 4000);
    };
    // Rejoue les toasts partis avant le montage.
    const queued = pending.splice(0, pending.length);
    queued.forEach((t) => pushFn!(t));
    return () => { pushFn = null; };
  }, []);

  if (items.length === 0) return null;
  return (
    <div className="pointer-events-none fixed bottom-4 right-4 z-[100] flex w-72 flex-col gap-2">
      {items.map((t) => (
        <div
          key={t.id}
          className={cn(
            'pointer-events-auto rounded-lg border px-3 py-2.5 text-xs font-medium shadow-2xl backdrop-blur',
            KIND_CLS[t.kind],
          )}
        >
          {t.msg}
        </div>
      ))}
    </div>
  );
}
