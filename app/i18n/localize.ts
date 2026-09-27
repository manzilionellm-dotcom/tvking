/*
 * Traduit le catalogue de démonstration (lib/data.ts, écrit en français) :
 * titres, sous-titres, genres, horaires… Les noms propres (équipes,
 * intervenants) et les champs absents du dictionnaire restent tels quels.
 */
import type { MediaItem, Row } from "../lib/data";
import type { Messages } from "./messages";

type ItemText = Partial<
  Pick<MediaItem, "title" | "subtitle" | "description" | "genre" | "startsIn" | "duration" | "clock" | "league">
>;

export function localizeItem(item: MediaItem, m: Messages): MediaItem {
  const t = (m.data.items as Record<string, ItemText>)[item.id] ?? {};
  const badges = m.data.badges as Record<string, string>;
  return {
    ...item,
    ...t,
    badge: item.badge ? (badges[item.badge] ?? item.badge) : undefined,
  };
}

export function localizeRow(row: Row, m: Messages): Row {
  const rows = { ...(m.home.rows as Record<string, string>), ...(m.data.rows as Record<string, string>) };
  return {
    ...row,
    title: rows[row.id] ?? row.title,
    items: row.items.map((it) => localizeItem(it, m)),
  };
}

/** Libellé traduit d'un niveau (« Débutant » → « Beginner »). */
export function levelLabel(level: NonNullable<MediaItem["level"]>, m: Messages): string {
  return (m.levels as Record<string, string>)[level] ?? level;
}
