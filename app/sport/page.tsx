import Row from "../components/Row";
import { sportRows } from "../lib/data";

export default function SportPage() {
  return (
    <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pt-[var(--safe-y)]">
      <header className="mb-[1.8rem]">
        <p className="text-[1rem] font-semibold uppercase tracking-[0.2em] text-[var(--sport)]">
          Sport
        </p>
        <h1 className="font-display text-[3rem] font-extrabold tracking-tight text-[var(--text-high)]">
          Le direct, à la minute
        </h1>
        <p className="mt-[0.3rem] text-[1.3rem] text-[var(--text-medium)]">
          Live, scores, calendrier et replays — classés par état et par discipline.
        </p>
      </header>
      {sportRows.map((row) => (
        <Row key={row.id} row={row} />
      ))}
    </div>
  );
}
