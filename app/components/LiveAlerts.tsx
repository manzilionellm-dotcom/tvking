"use client";

/*
 * Alertes in-app d'événements (sport / favoris) — la version « notifications »
 * qui marche sans infra : tant que l'app est ouverte, dès qu'un grand match (ou
 * un programme sur une chaîne favorite) va commencer, un petit bandeau apparaît
 * en bas avec un bouton « Regarder ». Tout vient du guide (EPG) déjà chargé.
 *
 * (Les notifications hors-app — téléphone éteint/app fermée — nécessitent du
 * natif + un serveur ; à faire dans une étape ultérieure.)
 */

import { useEffect, useRef, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { useSource } from "../lib/client-source";
import { useNow } from "../lib/use-now";
import { useFavorites } from "../lib/favorites";
import { upcomingAlerts, eventKey, type LiveEvent } from "../lib/events";
import { useT } from "../lib/i18n";
import ChannelLogo from "./ChannelLogo";

const TOAST_MS = 15_000;

export default function LiveAlerts() {
  const { playlist, epg } = useSource();
  const now = useNow();
  const { favoriteSet } = useFavorites();
  const pathname = usePathname();
  const router = useRouter();
  const t = useT();

  const [toast, setToast] = useState<LiveEvent | null>(null);
  const shown = useRef<Set<string>>(new Set());
  const hideTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // À chaque tick (30 s), si aucun bandeau n'est affiché, on cherche le prochain
  // événement non encore notifié et on l'affiche un court instant.
  useEffect(() => {
    if (toast || epg.size === 0) return;
    const next = upcomingAlerts(playlist.channels, epg, favoriteSet, now).find(
      (e) => !shown.current.has(eventKey(e)),
    );
    if (!next) return;
    shown.current.add(eventKey(next));
    setToast(next);
    hideTimer.current = setTimeout(() => setToast(null), TOAST_MS);
  }, [now, toast, epg, playlist, favoriteSet]);

  useEffect(() => {
    return () => {
      if (hideTimer.current) clearTimeout(hideTimer.current);
    };
  }, []);

  // Pas de bandeau par-dessus le lecteur plein écran.
  if (!toast || pathname?.startsWith("/watch")) return null;

  const { channel, programme } = toast;
  function dismiss() {
    if (hideTimer.current) clearTimeout(hideTimer.current);
    setToast(null);
  }

  return (
    <div className="fixed bottom-[var(--safe-y)] right-[var(--safe-x)] z-[45] max-w-[26rem]">
      <div className="flex items-center gap-[0.9rem] rounded-[var(--radius-lg)] border border-[var(--hairline)] bg-[var(--surface-2)]/96 p-[0.9rem] shadow-[0_1.2rem_3rem_rgba(0,0,0,0.55)] backdrop-blur">
        <ChannelLogo src={channel.logo} name={channel.name} size="2.8rem" />
        <div className="min-w-0 flex-1">
          <p className="text-[0.8rem] font-bold uppercase tracking-[0.15em] text-[var(--accent-strong)]">
            🔴 {t("starting_soon")}
          </p>
          <p className="truncate text-[1.1rem] font-bold text-[var(--text-high)]">{programme.title}</p>
          <p className="truncate text-[0.95rem] text-[var(--text-medium)]">{channel.name}</p>
        </div>
        <button
          data-focusable
          onClick={() => {
            dismiss();
            router.push(`/watch?c=${encodeURIComponent(channel.id)}`);
          }}
          className="focusable shrink-0 rounded-[var(--radius)] px-[1rem] py-[0.6rem] text-[1rem] font-bold text-black"
          style={{ background: "var(--accent-grad)" }}
        >
          {t("watch")}
        </button>
        <button
          data-focusable
          onClick={dismiss}
          aria-label="✕"
          className="focusable shrink-0 rounded-full px-[0.55rem] py-[0.1rem] text-[1rem] font-bold text-[var(--text-medium)]"
        >
          ✕
        </button>
      </div>
    </div>
  );
}
