import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Scripts closer",
  robots: { index: false, follow: false },
};

const SCRIPTS = [
  ["J+0", "Tu as bien ta playlist ? Dis-moi l'appareil (Firestick, Android, iPhone)."],
  ["J+1", "Ça lit chez toi ? Si oui on active le plan. Sinon envoie une capture de l'erreur."],
  ["J+2", "Dernier jour. Tu restes ou tu bloques encore ?"],
];

export default function OpsPage() {
  return (
    <main className="mx-auto max-w-xl px-5 py-12 text-[var(--text-high)]">
      <h1 className="text-2xl font-bold">Scripts — 447307410512</h1>
      <p className="mt-2 text-sm text-[var(--text-medium)]">Noindex. Copier-coller.</p>
      {SCRIPTS.map(([label, text]) => (
        <section key={label} className="mt-6 rounded-xl bg-[var(--surface-1)] p-4 ring-1 ring-[var(--hairline)]">
          <h2 className="text-sm font-semibold text-[#25D366]">{label}</h2>
          <pre className="mt-2 whitespace-pre-wrap text-sm">{text}</pre>
        </section>
      ))}
    </main>
  );
}
