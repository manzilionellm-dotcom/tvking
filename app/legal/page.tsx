import type { Metadata } from "next";
import AppOnlyNotice from "../components/site/AppOnlyNotice";
import { ZUNO_APP_ONLY_PHRASE } from "../lib/legal-copy";

export const metadata: Metadata = {
  title: "Mentions légales",
  description: "CGU, confidentialité et mentions légales — 7 Few, LLC.",
};

export default function LegalPage() {
  return (
    <div className="zuno-page mx-auto max-w-3xl px-4 py-14 sm:px-6">
      <h1 className="text-3xl font-bold text-white">Mentions légales</h1>
      <div className="mt-6"><AppOnlyNotice variant="hero" /></div>

      <section className="mt-10 space-y-4 text-sm leading-relaxed text-white/60">
        <h2 className="text-xl font-semibold text-white">Éditeur</h2>
        <p>
          <strong className="text-white/85">7 Few, LLC</strong>
          <br />
          131 Continental Dr Suite 305
          <br />
          Newark, DE 19713
          <br />
          United States
        </p>
        <p>
          Marque commerciale : <strong className="text-white/85">Zuno</strong>.
          Site : zuno.7themotion.com
        </p>
      </section>

      <section className="mt-10 space-y-3 text-sm leading-relaxed text-white/60">
        <h2 className="text-xl font-semibold text-white">Conditions générales d’utilisation</h2>
        <p>
          {ZUNO_APP_ONLY_PHRASE}{" "}
          Zuno est une application IPTV (lecteur). Nous ne vendons pas de chaînes, de contenu TV, de listes M3U ni d’abonnements IPTV. L’utilisateur apporte et est responsable de ses propres sources. Aucun catalogue n’est fourni par l’éditeur.
        </p>
        <p>
          L’accès payant (forfaits Annuel ou À vie) couvre l’usage de l’application et
          des services d’activation associés, selon les conditions du paiement Stripe.
        </p>
        <p>
          L’éditeur peut suspendre un accès en cas d’abus, fraude ou violation des présentes.
        </p>
      </section>

      <section className="mt-10 space-y-3 text-sm leading-relaxed text-white/60">
        <h2 className="text-xl font-semibold text-white">Confidentialité</h2>
        <p>
          Données traitées : e-mail de compte (si créé), adresse MAC pour activation, logs
          techniques. Paiements : traités par Stripe (nous ne stockons pas les numéros de carte).
        </p>
        <p>
          Contact privacy : via le support WhatsApp indiqué sur le site. Vous pouvez demander
          l’accès ou la suppression de vos données de compte.
        </p>
      </section>

      <section className="mt-10 space-y-3 text-sm leading-relaxed text-white/60">
        <h2 className="text-xl font-semibold text-white">Hébergement</h2>
        <p>Site hébergé sur Vercel Inc. Application et API d’activation peuvent utiliser des
          infrastructures Cloudflare / partenaires techniques de 7 Few, LLC.</p>
      </section>
    </div>
  );
}
