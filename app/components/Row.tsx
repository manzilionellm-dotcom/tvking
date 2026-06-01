import type { Row as RowData } from "../lib/data";
import MediaCard from "./MediaCard";

/*
 * A horizontal content rail. Rows are the core browse unit (Netflix/Hulu/Disney+
 * convention). Most-relevant items sit to the left. Horizontal overflow scrolls;
 * SpatialNav keeps the focused card in view.
 */
export default function Row({ row }: { row: RowData }) {
  return (
    <section className="mb-[2.4rem]">
      <h2 className="mb-[0.9rem] text-[1.5rem] font-bold text-[var(--text-high)]">
        {row.title}
      </h2>
      <div className="no-scrollbar flex gap-[1.2rem] overflow-x-auto overflow-y-visible py-[0.5rem] pr-[var(--safe-x)]">
        {row.items.map((item) => (
          <MediaCard key={item.id} item={item} />
        ))}
      </div>
    </section>
  );
}
