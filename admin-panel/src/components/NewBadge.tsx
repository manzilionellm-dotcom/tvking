// =========================================================
//  NewBadge / is-new — marquage « nouveau contrôle » admin
// =========================================================
//  Convention Lionel : tout nouveau contrôle admin = bleu + danse
//  (`is-new`) jusqu'à retrait manuel.
//
//  Pourquoi : Lionel veut VOIR et tester ce qu'on vient d'ajouter
//  (vague ops #23/#24, puis les suivantes) sans chercher dans le
//  sidebar historique. Le bleu n'est PAS le rouge marque (accent
//  ember) : c'est un signal temporaire, distinct, lisible en dark.
//
//  Usage — poser `is-new` sur le bouton / chip / champ :
//
//    <button {...applyNew('copy-whatsapp', 'rounded-md border …')}>
//      Copier WhatsApp
//    </button>
//
//    <NewBadge id="admin-note">…champ entier…</NewBadge>
//
//  Pour retirer le marquage plus tard : enlever l'id de
//  NEW_FEATURE_IDS (ou passer `enabled: false`). Le data-attribute
//  `data-new="2026-09-13"` permet aussi un grep / un retrait CSS.
// =========================================================

import type { ReactNode } from 'react';
import { cn } from '@/lib/utils';

/// Vague courante — date du marquage (retire-la quand Lionel a testé).
export const NEW_WAVE_DATE = '2026-09-13';

/// Contrôles encore « nouveaux ». Retirer un id ici = plus de bleu/danse.
export const NEW_FEATURE_IDS = [
  'filter-expiring-7d',
  'filter-expired',
  'filter-no-sub',
  'filter-frozen',
  'filter-banned',
  'filter-online-unpaid',
  'renew-monthly',
  'renew-quarterly',
  'renew-biannual',
  'renew-yearly',
  'trial-24h',
  'trial-48h',
  'trial-7d',
  'admin-note',
  'copy-whatsapp',
  'clear-license',
  'badge-online-unpaid',
  'ban-online-unpaid',
  'filter-problematic',
  'change-mac',
  'regenerate-mac',
] as const;

export type NewFeatureId = (typeof NEW_FEATURE_IDS)[number];

const NEW_SET: ReadonlySet<string> = new Set(NEW_FEATURE_IDS);

export function isNewFeature(id: string | undefined | null): boolean {
  return !!id && NEW_SET.has(id);
}

/// Classe CSS seule (`is-new`) si l'id est encore dans la liste.
export function isNewClass(id: string | undefined | null): string {
  return isNewFeature(id) ? 'is-new' : '';
}

/// Attributs data-* pour un retrait ultérieur (`[data-new="2026-09-13"]`).
export function newDataAttrs(id: string | undefined | null): {
  'data-new'?: string;
  'data-new-id'?: string;
} {
  if (!isNewFeature(id) || !id) return {};
  return { 'data-new': NEW_WAVE_DATE, 'data-new-id': id };
}

/// Helper principal : classes + data-attr à étaler sur le contrôle.
///
///   <button {...applyNew('filter-expired', 'rounded-full border px-2 …')} />
export function applyNew(
  id: string | undefined | null,
  className?: string,
): {
  className: string;
  'data-new'?: string;
  'data-new-id'?: string;
} {
  const active = isNewFeature(id);
  return {
    className: cn(className, active && 'is-new'),
    ...(active && id ? { 'data-new': NEW_WAVE_DATE, 'data-new-id': id } : {}),
  };
}

/// Enveloppe un groupe (label + champ, pastille + texte) pour le
/// marquer d'un coup. Préférer `applyNew` directement sur un bouton.
export function NewBadge({
  id,
  children,
  className,
  as: Tag = 'div',
}: {
  id: string;
  children: ReactNode;
  className?: string;
  as?: 'div' | 'span' | 'label';
}) {
  return (
    <Tag {...applyNew(id, className)}>
      {children}
    </Tag>
  );
}
