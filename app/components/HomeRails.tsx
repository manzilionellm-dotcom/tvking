"use client";

import { useMemo } from "react";
import Rail from "./Rail";
import RailCard from "./RailCard";
import LazyRow from "./LazyRow";
import { useSource, nowNextMap } from "../lib/client-source";
import { useFavorites, useRecents } from "../lib/favorites";
import { useNow } from "../lib/use-now";
import { liveEvents, tonightEvents } from "../lib/events";
import { useT } from "../lib/i18n";
import type { Channel } from "../lib/iptv-types";

/*
 * Accueil « lean-back » en rails personnalisés (modèle 10-foot). Ordre :
 *   1. Reprendre               — la dernière chaîne regardée (recents[0])
 *   2. En direct maintenant    — événements sport détectés dans l'EPG
 *   3. Tes favoris en direct   — favoris dont un programme est en cours
 *   4. Récemment vues          — le reste de l'historique
 *   5. Catégories              — un rail par groupe de la playlist (lazy)
 * Les rails vides sont masqués. Tout est local, aucun réseau.
 */

// Garde-fous box bas de gamme : un grand groupe ne monte pas 1000 cartes.
// La profondeur complète reste accessible via la Recherche.
const MAX_PER_CAT = 60;

export default function HomeRails() {
  const { playlist, epg } = useSource();
  const { favoriteSet } = useFavorites();
  const recents = useRecents();
  const now = useNow();
  const t = useT();

  // now/next de toute la playlist (recalculé quand la source change).
  const nowNext = useMemo(() => {
    void playlist;
    return nowNextMap();
  }, [playlist]);

  const byId = useMemo(() => {
    const m = new Map<string, Channel>();
    for (const c of playlist.channels) m.set(c.id, c);
    return m;
  }, [playlist]);

  const recentChannels = recents.map((id) => byId.get(id)).filter(Boolean) as Channel[];
  const resume = recentChannels[0];
  const restRecent = recentChannels.slice(1);

  const live = useMemo(() => liveEvents(playlist.channels, epg, now, 24), [playlist, epg, now]);

  const favLive = useMemo(() => {
    const out: Channel[] = [];
    for (const c of playlist.channels) {
      if (favoriteSet.has(c.id) && nowNext[c.id]) out.push(c);
    }
    return out;
  }, [playlist, favoriteSet, nowNext]);

  const tonight = useMemo(
    () => tonightEvents(playlist.channels, epg, favoriteSet, now, 20),
    [playlist, epg, favoriteSet, now],
  );

  // Heure locale courte pour la pastille du rail « Pour ce soir ».
  const hhmm = (ms: number) =>
    new Date(ms).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

  return (
    <div className="no-scrollbar h-screen overflow-y-auto pl-[6.5rem] pr-[var(--safe-x)] py-[var(--safe-y)]">
      {resume && (
        <Rail title={t("rail_resume")}>
          <RailCard channel={resume} nowNext={nowNext[resume.id]} />
        </Rail>
      )}

      {live.length > 0 && (
        <Rail title={t("rail_live_now")}>
          {live.map((e) => (
            <RailCard
              key={e.channel.id}
              channel={e.channel}
              nowNext={nowNext[e.channel.id]}
              subtitle={e.programme.title}
            />
          ))}
        </Rail>
      )}

      {favLive.length > 0 && (
        <Rail title={t("rail_fav_live")}>
          {favLive.map((c) => (
            <RailCard key={c.id} channel={c} nowNext={nowNext[c.id]} />
          ))}
        </Rail>
      )}

      {tonight.length > 0 && (
        <Rail title={t("rail_tonight")}>
          {tonight.map((e) => (
            <RailCard
              key={`${e.channel.id}@${e.programme.start}`}
              channel={e.channel}
              subtitle={e.programme.title}
              badge={hhmm(e.programme.start)}
            />
          ))}
        </Rail>
      )}

      {restRecent.length > 0 && (
        <Rail title={t("recently_viewed")}>
          {restRecent.map((c) => (
            <RailCard key={c.id} channel={c} nowNext={nowNext[c.id]} />
          ))}
        </Rail>
      )}

      {/* Catégories : un rail par groupe (monté à l'approche du viewport). */}
      {playlist.groups.map((g) => (
        <LazyRow key={g.id} minHeight="15.5rem">
          <Rail title={g.name}>
            {g.channels.slice(0, MAX_PER_CAT).map((c) => (
              <RailCard key={c.id} channel={c} nowNext={nowNext[c.id]} />
            ))}
          </Rail>
        </LazyRow>
      ))}
    </div>
  );
}
