"use client";

import { useCallback, useSyncExternalStore } from "react";
import {
  MYLIST_KEY,
  REMINDERS_KEY,
  hasId,
  loadSet,
  subscribeCollections,
  toggleStored,
} from "../lib/collections";

/*
 * The two "investment" buttons of the detail page. They were inert until now
 * (backlog B7): a TV app must never show a control that does nothing.
 *
 * State lives in localStorage and is read through useSyncExternalStore, so the
 * server snapshot is always "not saved" and hydration stays consistent; the real
 * value appears right after mount. aria-pressed exposes the toggle to assistive
 * tech, and the label changes so the state is readable across a room.
 */

function useInCollection(key: string, id: string): boolean {
  return useSyncExternalStore(
    subscribeCollections,
    () => hasId(loadSet(key), id),
    () => false
  );
}

function Toggle({
  on,
  onToggle,
  onLabel,
  offLabel,
  primary,
}: {
  on: boolean;
  onToggle: () => void;
  onLabel: string;
  offLabel: string;
  primary?: boolean;
}) {
  return (
    <button
      type="button"
      data-focusable
      {...(primary ? { "data-focus-default": "" } : {})}
      aria-pressed={on}
      onClick={onToggle}
      className="focusable rounded-[var(--radius)] px-[1.4rem] py-[0.8rem] text-[1.25rem] font-semibold"
      style={
        on
          ? { background: "var(--gold-grad)", color: "#000", fontWeight: 700 }
          : { background: "rgba(255,255,255,0.15)", color: "var(--text-high)" }
      }
    >
      {on ? onLabel : offLabel}
    </button>
  );
}

/** "+ Ma liste" / "✓ Dans ma liste". */
export function SaveButton({ id }: { id: string }) {
  const on = useInCollection(MYLIST_KEY, id);
  const toggle = useCallback(() => toggleStored(MYLIST_KEY, id), [id]);
  return <Toggle on={on} onToggle={toggle} offLabel="+ Ma liste" onLabel="✓ Dans ma liste" />;
}

/**
 * "🔔 Me rappeler" / "✓ Rappel activé" — the tri-state sport model documents an
 * explicit "reminder set" state on upcoming events (research §5).
 */
export function RemindButton({ id }: { id: string }) {
  const on = useInCollection(REMINDERS_KEY, id);
  const toggle = useCallback(() => toggleStored(REMINDERS_KEY, id), [id]);
  return (
    <Toggle
      primary
      on={on}
      onToggle={toggle}
      offLabel="🔔 Me rappeler"
      onLabel="✓ Rappel activé"
    />
  );
}

/** Small card overlay marking an upcoming event the viewer asked to be reminded of. */
export function ReminderFlag({ id }: { id: string }) {
  const on = useInCollection(REMINDERS_KEY, id);
  if (!on) return null;
  return (
    <span
      className="absolute right-[0.6rem] top-[0.6rem] rounded-md px-[0.5rem] py-[0.15rem] text-[0.75rem] font-bold text-black"
      style={{ background: "var(--gold-grad)" }}
    >
      🔔 Rappel
    </span>
  );
}
