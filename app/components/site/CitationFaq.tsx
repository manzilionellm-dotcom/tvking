import { faqFor } from "../../../lib/aio";

type Props = {
  /** null : pas de titre de section (la page a déjà un h1). */
  heading?: string | null;
  className?: string;
};

/**
 * Questions/réponses Citation Hook, rendues en HTML serveur.
 * Chaque h3 se termine par « ? » et est suivi immédiatement d'un paragraphe visible.
 */
export default function CitationFaq({
  heading = "Questions fréquentes",
  className = "",
}: Props) {
  const faq = faqFor();
  return (
    <section id="faq" className={className} aria-labelledby={heading ? "aio-faq-title" : undefined}>
      {heading ? (
        <>
          <h2 id="aio-faq-title" className="text-2xl font-bold text-white">
            {heading}
          </h2>
          <p className="mt-3 text-sm leading-relaxed text-white/60">
            Réponses reprises des pages du site : accueil, forfaits, téléchargement, activation, revendeur et mentions légales.
          </p>
        </>
      ) : null}
      <div className={heading ? "mt-8 space-y-8" : "space-y-8"}>
        {faq.map((item) => (
          <div key={item.q}>
            <h3 className="text-lg font-semibold text-white">{item.q}</h3>
            <p className="mt-2 text-sm leading-relaxed text-white/70">{item.a}</p>
          </div>
        ))}
      </div>
    </section>
  );
}
