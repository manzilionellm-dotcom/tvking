// =========================================================
//  watch/[slug]/page.tsx — Lecteur d'un contenu
// =========================================================
//  Récupère l'item + calcule le « À suivre » (élément suivant du même
//  univers, en boucle) et délègue au composant Player.
// =========================================================

import { notFound } from "next/navigation";
import { Player } from "../../components/Player";
import { getById, getByUniverse } from "../../lib/data";

export default async function WatchPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const item = getById(slug);
  if (!item) notFound();

  // « À suivre » : l'élément suivant du même univers (boucle).
  const siblings = getByUniverse(item.universe);
  const idx = siblings.findIndex((m) => m.id === item.id);
  const next =
    siblings.length > 1 ? siblings[(idx + 1) % siblings.length] : null;

  return (
    <div style={{ paddingTop: "1rem" }}>
      <Player item={item} next={next} />
    </div>
  );
}
