import Recorder from "./recorder";

export default function Home() {
  return (
    <div className="flex min-h-full flex-1 flex-col items-center justify-center bg-gradient-to-br from-black via-zinc-950 to-red-950/40 px-4 py-10 font-sans">
      <Recorder />
    </div>
  );
}
