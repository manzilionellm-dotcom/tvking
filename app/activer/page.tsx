import type { Metadata } from "next";
import Link from "next/link";
import ActivationForm from "../components/site/ActivationForm";
import AppOnlyNotice from "../components/site/AppOnlyNotice";

export const metadata: Metadata = {
  title: "Activer mon appareil",
  description:
    "Activez Zuno avec votre S code et votre M2 (identifiant appareil).",
};

export default function ActiverPage() {
  return (
    <div className="zuno-page mx-auto max-w-3xl px-4 py-14 sm:px-6">
      <div className="text-center">
        <h1 className="text-3xl font-bold text-white sm:text-4xl">
          Activer mon appareil
        </h1>
        <p className="mx-auto mt-3 max-w-xl text-white/50">
          Activation instantanée — comme dans le panel. Saisissez votre{" "}
          <strong className="font-medium text-white/70">S code</strong> et
          votre <strong className="font-medium text-white/70">M2</strong>.
        </p>
      </div>
      <div className="mx-auto mt-8 max-w-md"><AppOnlyNotice variant="banner" /></div>
      <div className="mt-8">
        <ActivationForm />
      </div>
      <ol className="mx-auto mt-12 max-w-md list-decimal space-y-2 pl-5 text-sm text-white/45">
        <li>
          <Link href="/forfaits" className="text-[#60a5fa]">
            Choisir un forfait
          </Link>{" "}
          et payer
        </li>
        <li>Activer ici avec S code + M2</li>
        <li>
          <Link href="/telecharger" className="text-[#60a5fa]">
            Télécharger
          </Link>{" "}
          et ouvrir Zuno
        </li>
      </ol>
    </div>
  );
}
