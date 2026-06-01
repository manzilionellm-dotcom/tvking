import type { Row as RowData } from "../lib/data";
import MediaCard from "./MediaCard";

/*
 * A horizontal content rail. Rows are the core browse unit (Netflix/Hulu/Disney+
 * convention). Most-relevant items sit to the left. Horizontal overflow scrolls;
 * SpatialNav keeps the focused card in view.
 */
export default function Row({ row }: { row: RowData }) {
  return (
    <section className="relative z-[2] mb-[2.4rem]">
      <h2 className="font-display mb-[0.9rem] flex items-center gap-[0.8rem] text-[1.7rem] font-bold text-[var(--text-high)]">
        <span className="inline-block h-[1.3rem] w-[0.28rem] rounded-full" style={{ background: "var(--gold-grad)" }} />
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
