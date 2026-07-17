import Row from "../components/Row";
import { sportRows } from "../lib/data";

export default function SportPage() {
  return (
    <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pt-[var(--page-top)]">
      <header className="mb-[1.8rem] max-md:mb-[1.2rem]">
        <p className="text-[1rem] font-semibold uppercase tracking-[0.2em] text-[var(--sport)] max-md:text-[0.8rem]">
          Sport
        </p>
        <h1 className="font-display text-[3rem] font-extrabold tracking-tight text-[var(--text-high)] max-md:text-[1.8rem]">
          Le direct, à la minute
        </h1>
        <p className="mt-[0.3rem] text-[1.3rem] text-[var(--text-medium)] max-md:text-[0.98rem]">
          Live, scores, calendrier et replays — classés par état et par discipline.
        </p>
      </header>
      {sportRows.map((row) => (
        <Row key={row.id} row={row} />
      ))}
    </div>
  );
}
