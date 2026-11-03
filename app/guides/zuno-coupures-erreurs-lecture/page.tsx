import type { Metadata } from "next";
import Link from "next/link";
import { breadcrumbJsonLd, graph, jsonLdString, aio } from "../../../lib/aio";
import { canonicalFor, canonicalUrl } from "../../lib/seo";

/**
 * Guide Q&R : coupures, chargement sans fin et erreurs de lecture dans Zuno.
 * Étapes de dépannage Fire TV reprises de l'aide Amazon ; débits relevés le 3 nov. 2026 sur les pages
 * officielles listées dans SOURCES. Aucun chiffre sans source ouverte et datée.
 */

const PATH = "/guides/zuno-coupures-erreurs-lecture";
const TITLE = "Zuno qui coupe ou qui charge sans fin : régler la mise en mémoire tampon et les erreurs de lecture";
const DESCRIPTION =
  "Image qui se fige, chargement sans fin, chaîne qui ne démarre pas dans Zuno : les causes (débit, Wi-Fi, source) et les étapes pour corriger, avec les débits recommandés par Netflix, YouTube et Amazon.";
const PUBLISHED = "2026-11-03";
const WA_HELP = `https://wa.me/447307410512?text=${encodeURIComponent(
  "Bonjour Zuno — j'ai une question sur un problème de lecture.",
)}`;

const SOURCES = [
  {
    label: "Fiche Google Play « ZUNO - IPTV Player » (lue le 3 novembre 2026, mise à jour du 22 oct. 2026)",
    href: "https://play.google.com/store/apps/details?id=com.sevenmotion.tv.seven_tv",
  },
  {
    label: "Netflix — Débits Internet recommandés (consulté le 3 novembre 2026)",
    href: "https://help.netflix.com/fr/node/306",
  },
  {
    label: "Aide YouTube — Configuration système requise et débits recommandés (consulté le 3 novembre 2026)",
    href: "https://support.google.com/youtube/answer/78358?hl=fr",
  },
  {
    label: "Amazon — Problèmes de diffusion en direct sur Prime Video (consulté le 3 novembre 2026)",
    href: "https://www.amazon.com/gp/help/customer/display.html?nodeId=GLF6K9WFVYXMR7BS",
  },
  {
    label: "Amazon — Résoudre les problèmes de lecture sur Fire TV (consulté le 3 novembre 2026)",
    href: "https://www.amazon.com/gp/help/customer/display.html?nodeId=G4XBG7CZQ9RCNGQE",
  },
];

const FAQ = [
  {
    q: "Pourquoi Zuno coupe-t-il seulement pendant les matchs en direct ?",
    a: "Le direct laisse moins de marge que la vidéo à la demande : le lecteur ne peut pas télécharger loin en avance, donc la moindre baisse de débit se voit. Aux heures de grande affluence, le serveur de votre fournisseur peut aussi saturer. Testez une autre chaîne de la même source pour faire la différence.",
  },
  {
    q: "Le problème vient-il de Zuno ou de ma source ?",
    a: "Faites un test simple : si plusieurs chaînes de la même source coupent alors qu'une vidéo YouTube ou Netflix tourne bien sur le même appareil, la source est en cause. Si tout coupe, regardez votre réseau. La fiche Google Play rappelle que la qualité vidéo dépend des médias fournis par vos sources.",
  },
  {
    q: "Faut-il un câble Ethernet pour éviter les coupures ?",
    a: "Ce n'est pas obligatoire, mais c'est souvent la solution la plus fiable. L'aide YouTube indique qu'une connexion câblée au lieu d'une connexion sans fil peut aider la lecture. Sur une clé Fire TV sans prise réseau, rapprochez la box ou utilisez le Wi-Fi 5 GHz si votre box le propose.",
  },
  {
    q: "Quel débit minimum pour regarder en HD sans coupure ?",
    a: "Comptez au moins 5 Mbit/s par écran en HD : c'est le minimum donné par Prime Video pour la HD en direct, et le chiffre de Netflix et de YouTube pour le 1080p, relevés le 3 novembre 2026. En SD, Prime Video indique 1 Mbit/s. Additionnez les débits si plusieurs écrans regardent en même temps.",
  },
  {
    q: "Vider le cache de Zuno efface-t-il mes playlists ?",
    a: "Vider le cache n'efface normalement que les fichiers temporaires. Effacer les données de l'application, en revanche, remet l'application à zéro sur l'appareil, et vous devrez peut-être rajouter vos sources. Notez vos accès M3U ou Xtream avant de le faire, et commencez toujours par le simple redémarrage de l'appareil.",
  },
  {
    q: "Une question sur un problème de lecture ?",
    a: "Écrivez au support Zuno sur WhatsApp au +44 7307 410512 (wa.me/447307410512). Indiquez votre appareil, la chaîne ou la vidéo concernée, le message d'erreur et le résultat de votre test de débit. Ne partagez jamais votre mot de passe en clair. Le support aide pour l'application : il ne fournit pas de chaînes.",
  },
];

export const metadata: Metadata = {
  title: "Zuno qui coupe ou charge sans fin : solutions aux erreurs de lecture",
  description: DESCRIPTION,
  ...canonicalFor(PATH),
  openGraph: { title: TITLE, description: DESCRIPTION, url: canonicalUrl(PATH), type: "article" },
};

function GuideJsonLd() {
  const url = canonicalUrl(PATH);
  const orgId = `${aio.siteUrl}/#org`;
  const article = {
    "@type": "Article",
    "@id": `${url}#article`,
    headline: TITLE,
    description: DESCRIPTION,
    inLanguage: "fr",
    datePublished: PUBLISHED,
    dateModified: PUBLISHED,
    mainEntityOfPage: url,
    author: { "@type": "Organization", name: "Équipe éditoriale Zuno", url: aio.brandUrl },
    publisher: { "@id": orgId },
    citation: SOURCES.map((s) => s.href),
    about: { "@type": "SoftwareApplication", name: "ZUNO - IPTV Player", operatingSystem: "Android, Windows", applicationCategory: "MultimediaApplication" },
  };
  const org = {
    "@type": "Organization",
    "@id": orgId,
    name: aio.siteName,
    legalName: aio.legalName,
    url: aio.brandUrl,
    contactPoint: { "@type": "ContactPoint", contactType: "customer support", url: aio.contact.whatsapp },
  };
  const faq = {
    "@type": "FAQPage",
    "@id": `${url}#faq`,
    inLanguage: "fr",
    mainEntity: FAQ.map((f) => ({
      "@type": "Question",
      name: f.q,
      acceptedAnswer: { "@type": "Answer", text: f.a },
    })),
  };
  const crumbs = breadcrumbJsonLd([{ name: "Coupures et erreurs de lecture", path: PATH }]);
  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: jsonLdString(graph(article, org, faq, crumbs)) }}
    />
  );
}

const h2 = "mt-12 text-2xl font-bold text-white";
const p = "mt-3 text-[15px] leading-relaxed text-white/70";
const li = "text-[15px] leading-relaxed text-white/70";
const a = "text-[#60a5fa] hover:underline";
const th = "px-4 py-3 font-semibold";
const td = "px-4 py-3";

export default function ZunoCoupuresGuide() {
  return (
    <article className="zuno-page mx-auto max-w-3xl px-4 py-14 sm:px-6">
      <GuideJsonLd />
      <p className="text-xs uppercase tracking-wide text-white/40">
        Guide · Équipe éditoriale · publié le 3 novembre 2026
      </p>
      <h1 className="mt-2 text-3xl font-bold text-white sm:text-4xl">{TITLE}</h1>
      <p className="mt-5 text-base leading-relaxed text-white/80">
        <strong className="text-white">Réponse rapide :</strong> une image qui se fige dans Zuno vient le
        plus souvent d&apos;un débit trop faible, d&apos;un Wi-Fi instable ou d&apos;une source surchargée.
        Mesurez votre débit (au moins 5 Mbit/s par écran en HD), redémarrez l&apos;appareil et la box,
        rapprochez-vous du routeur ou passez au câble, puis testez une autre chaîne de votre source.
      </p>
      <p className="mt-4 text-sm text-white/50">
        Une question ?{" "}
        <a href={WA_HELP} target="_blank" rel="noopener noreferrer" className={a}>
          wa.me/447307410512
        </a>
      </p>

      <h2 className={h2}>Pourquoi Zuno met-il en mémoire tampon ?</h2>
      <p className={p}>
        La mise en mémoire tampon apparaît quand les données arrivent moins vite que la vidéo ne se lit. Les
        causes habituelles sont un débit insuffisant, un Wi-Fi faible, un appareil trop sollicité ou un
        serveur de source saturé. Zuno lit le flux de votre source : il ne peut pas aller plus vite
        qu&apos;elle.
      </p>
      <div className="mt-5 overflow-x-auto rounded-xl border border-white/10">
        <table className="w-full text-left text-sm text-white/70">
          <thead className="bg-white/[0.04] text-white">
            <tr>
              <th className={th}>Symptôme</th>
              <th className={th}>Cause probable</th>
              <th className={th}>Premier réflexe</th>
            </tr>
          </thead>
          <tbody>
            <tr className="border-t border-white/10">
              <td className={td}>Toutes les chaînes coupent</td>
              <td className={td}>Réseau ou appareil</td>
              <td className={td}>Test de débit, redémarrage appareil et box</td>
            </tr>
            <tr className="border-t border-white/10">
              <td className={td}>Une seule chaîne coupe</td>
              <td className={td}>Flux de la source</td>
              <td className={td}>Essayer une autre chaîne, prévenir le fournisseur</td>
            </tr>
            <tr className="border-t border-white/10">
              <td className={td}>Coupures le soir ou pendant les matchs</td>
              <td className={td}>Affluence sur le réseau ou le serveur</td>
              <td className={td}>Baisser la qualité, câble Ethernet</td>
            </tr>
            <tr className="border-t border-white/10">
              <td className={td}>Chaîne qui ne démarre jamais</td>
              <td className={td}>Accès expiré ou adresse erronée</td>
              <td className={td}>Vérifier l&apos;abonnement et les identifiants</td>
            </tr>
          </tbody>
        </table>
      </div>

      <h2 className={h2}>Quel débit faut-il pour éviter les coupures ?</h2>
      <p className={p}>
        Visez au moins 5 Mbit/s stables par écran en HD et 15 à 20 Mbit/s en 4K. Prime Video donne 1 Mbit/s
        pour la SD et 5 Mbit/s pour la HD en direct ; Netflix recommande 15 Mbit/s en 4K et YouTube 20 Mbit/s.
        Chiffres relevés le 3 novembre 2026 sur leurs pages d&apos;aide.
      </p>
      <ul className="mt-3 list-disc space-y-2 pl-6">
        <li className={li}>Prime Video (direct) : 1 Mbit/s en SD, 5 Mbit/s en HD.</li>
        <li className={li}>Netflix : 3 Mbit/s en 720p, 5 Mbit/s en 1080p, 15 Mbit/s en 4K.</li>
        <li className={li}>YouTube : 1,1 Mbit/s en 480p, 2,5 Mbit/s en 720p, 5 Mbit/s en 1080p, 20 Mbit/s en 4K.</li>
      </ul>
      <p className={p}>
        Faites le test de débit sur un téléphone posé à côté du téléviseur, sur le même Wi-Fi : c&apos;est là
        que le signal compte, pas à côté de la box.
      </p>

      <h2 className={h2}>Comment corriger les coupures dans Zuno, étape par étape ?</h2>
      <p className={p}>
        Suivez les étapes dans l&apos;ordre et testez la lecture après chacune : la plupart des coupures
        disparaissent dès les trois premières. Ces étapes reprennent celles qu&apos;Amazon conseille pour les
        problèmes de lecture sur Fire TV, et s&apos;appliquent aussi à Android TV, Google TV et aux téléphones
        Android.
      </p>
      <ol className="mt-3 list-decimal space-y-2 pl-6">
        <li className={li}>
          Redémarrez l&apos;appareil. Amazon conseille de débrancher l&apos;adaptateur secteur de la Fire TV
          pendant 1 minute, puis de le rebrancher.
        </li>
        <li className={li}>
          Redémarrez le modem et le routeur : débranchez-les 30 secondes, rebranchez d&apos;abord le modem,
          puis le routeur, selon l&apos;aide Amazon.
        </li>
        <li className={li}>Mettez à jour le système de l&apos;appareil et l&apos;application Zuno depuis Google Play.</li>
        <li className={li}>Rapprochez l&apos;appareil du routeur, passez en Wi-Fi 5 GHz ou branchez un câble Ethernet.</li>
        <li className={li}>Fermez les autres applications et coupez les téléchargements en cours sur le réseau.</li>
        <li className={li}>Testez une autre chaîne de votre source pour savoir si le problème vient du flux.</li>
        <li className={li}>En dernier recours, videz le cache de Zuno dans les paramètres Applications de l&apos;appareil.</li>
      </ol>

      <h2 className={h2}>Que signifie une chaîne qui ne démarre pas du tout ?</h2>
      <p className={p}>
        Une chaîne qui reste noire ou affiche une erreur dès le lancement indique en général un accès
        refusé : abonnement expiré, identifiants modifiés ou chaîne retirée par le fournisseur. Vérifiez votre
        compte auprès de lui, puis relancez la synchronisation de la playlist. Si toute la liste est vide,
        rajoutez la source.
      </p>
      <p className={p}>
        Pour rajouter une source proprement, suivez le guide{" "}
        <Link href="/guides/ajouter-playlist-m3u-xtream-zuno" className={a}>ajouter une playlist M3U ou Xtream dans Zuno</Link>.
      </p>

      <h2 className={h2}>Le son, les sous-titres ou le guide TV manquent : est-ce un bug ?</h2>
      <p className={p}>
        Pas forcément. La fiche Google Play de Zuno précise que le guide TV, les pistes audio, les sous-titres
        et la qualité vidéo dépendent des médias fournis par vos sources. Si une chaîne n&apos;a qu&apos;une piste
        audio ou pas de programme, Zuno ne peut pas en créer. Comparez avec une autre chaîne de la même
        source.
      </p>

      <section id="faq" className="mt-14">
        <h2 className="text-2xl font-bold text-white">Questions fréquentes</h2>
        <p className="mt-3 text-sm text-white/50">Réponses tirées de la fiche Google Play de Zuno et des pages d&apos;aide citées.</p>
        <div className="mt-6 space-y-7">
          {FAQ.map((f) => (
            <div key={f.q}>
              <h3 className="text-lg font-semibold text-white">{f.q}</h3>
              <p className="mt-2 text-[15px] leading-relaxed text-white/70">{f.a}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="mt-14 rounded-xl border border-white/10 bg-white/[0.03] p-5 text-sm leading-relaxed text-white/55">
        <h2 className="text-base font-semibold text-white/80">Avertissement légal</h2>
        <p className="mt-2">
          Zuno est un lecteur multimédia. Il n&apos;héberge, ne vend et ne distribue aucun contenu
          audiovisuel. Utilisez uniquement des sources que vous avez le droit de regarder, auprès de
          fournisseurs titulaires des licences nécessaires. Les débits cités sont ceux que chaque service
          recommande pour ses propres vidéos. Cette page ne contient aucun lien affilié. Les marques citées
          (Netflix, YouTube, Google, Amazon, Prime Video, Fire TV, Android TV) appartiennent à leurs
          propriétaires ; Zuno n&apos;est affilié à aucun d&apos;entre eux.
        </p>
      </section>

      <section className="mt-8 text-sm text-white/50">
        <h2 className="text-base font-semibold text-white/80">Sources</h2>
        <ul className="mt-2 list-disc space-y-1 pl-5">
          {SOURCES.map((s) => (
            <li key={s.href}>
              <a href={s.href} target="_blank" rel="noopener noreferrer" className={a}>
                {s.label}
              </a>
            </li>
          ))}
        </ul>
        <p className="mt-4">
          Une question ?{" "}
          <a href={WA_HELP} target="_blank" rel="noopener noreferrer" className={a}>
            wa.me/447307410512
          </a>
        </p>
      </section>
    </article>
  );
}
