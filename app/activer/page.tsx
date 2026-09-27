import type { Metadata } from "next";
import Link from "next/link";
import ActivationForm from "../components/site/ActivationForm";

export const metadata: Metadata = {
  title: "Activer mon appareil",
  description: "Activez Zuno avec l'adresse MAC et votre code d'activation.",
};

export default function ActiverPage() {
  return (
    <div className="zuno-page mx-auto max-w-3xl px-4 py-14 sm:px-6">
      <div className="text-center">
        <h1 className="text-3xl font-bold text-white sm:text-4xl">Activer mon appareil</h1>
        <p className="mx-auto mt-3 max-w-xl text-white/50">
          Liez votre box ou PC à votre abonnement. MAC + code reçus après paiement.
        </p>
      </div>
      <div className="mt-10">
        <ActivationForm />
      </div>
      <ol className="mx-auto mt-12 max-w-md list-decimal space-y-2 pl-5 text-sm text-white/45">
        <li>
          <Link href="/forfaits" className="text-[#60a5fa]">Choisir un forfait</Link> et payer
        </li>
        <li>Activer ici avec MAC + code</li>
        <li>
          <Link href="/telecharger" className="text-[#60a5fa]">Télécharger</Link> et ouvrir Zuno
        </li>
      </ol>
    </div>
  );
}
