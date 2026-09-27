import { notFound } from "next/navigation";
import Player from "../../../components/Player";
import { allItems, getItem, relatedTo } from "../../../lib/data";
import { localizeItem } from "../../../i18n/localize";
import { pageI18n } from "../../../i18n/server";

export function generateStaticParams() {
  return allItems.map((it) => ({ slug: it.id }));
}

export default async function WatchPage({ params }: PageProps<"/[lang]/watch/[slug]">) {
  const { slug } = await params;
  const { m } = await pageI18n(params);
  const raw = getItem(slug);
  if (!raw) notFound();

  const next = relatedTo(raw)[0] ?? null;
  return <Player item={localizeItem(raw, m)} next={next ? localizeItem(next, m) : null} />;
}
