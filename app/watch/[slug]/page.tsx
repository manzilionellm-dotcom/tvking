import { notFound } from "next/navigation";
import Player from "../../components/Player";
import { allItems, getItem, relatedTo } from "../../lib/data";

export function generateStaticParams() {
  return allItems.map((it) => ({ slug: it.id }));
}

export default async function WatchPage({ params }: PageProps<"/watch/[slug]">) {
  const { slug } = await params;
  const item = getItem(slug);
  if (!item) notFound();

  const next = relatedTo(item)[0] ?? null;
  return <Player item={item} next={next} />;
}
