import type { Metadata } from "next";
import Link from "next/link";
import { breadcrumbJsonLd, graph, jsonLdString, aio } from "../../../lib/aio";
import { canonicalFor, canonicalUrl } from "../../lib/seo";

const PATH = "/guides/installer-zuno";
const TITLE = "Installer Zuno sur Fire TV, Android TV, Smart TV et téléphone";
const DESCRIPTION =
  "Guide pas à pas : installer le lecteur IPTV Zuno sur Fire TV, Android TV / Google TV, Smart TV et téléphone, appareils compatibles et fonctionnement. Zuno ne fournit aucune chaîne.";
const PUBLISHED = "2026-11-03";
const WA_SETUP = `https://wa.me/447307410512?text=${encodeURIComponent(
  "Bonjour Zuno — j'ai une question sur l'installation de l'application.",
)}`;

const SOURCES = [
  {
    label: "Fiche Google Play « ZUNO - IPTV Player » (lue le 3 novembre 2026, mise à jour du 22 oct. 2026)",
    href: "https://play.google.com/store/apps/details?id=com.sevenmotion.tv.seven_tv",
  },
  {
    label: "Page Télécharger de Zuno (fichiers Android et Windows)",
    href: "https://zuno.7themotion.com/telecharger",
  },
  {
    label: "Forum Amazon : activer les options pour les développeurs sur Fire TV",
    href: "https://uk.amazonforum.com/s/question/0D56Q0000CxViuYSQS/developer-options-i-dont-have-this-on-my-firestick-so-i-cant-allow-unknown-u?language=en_US",
  },
  {
    label: "AFTVnews : autoriser les applis de sources inconnues sur Fire TV",
    href: "https://www.aftvnews.com/how-to-enable-apps-from-unknown-sources-on-an-amazon-fire-tv-or-fire-tv-stick/",
  },
];

const FAQ = [
  {
    q: "Zuno fournit-il des chaînes ?",
    a: "Non. Zuno est un lecteur : il ne fournit, n'héberge et ne vend aucune chaîne, aucune liste M3U ni aucun abonnement TV. Vous ajoutez votre propre source M3U ou Xtream, fournie par un service que vous avez le droit d'utiliser. Le site vend seulement la licence de l'application.",
  },
  {
    q: "Sur quels appareils installer Zuno ?",
    a: "La fiche Google Play cite les téléviseurs et box Android TV et Google TV, les projecteurs sous Android compatible, et les téléphones et tablettes Android en mode paysage. Le site propose aussi un fichier pour Fire TV et un installateur Windows 10/11 64 bits.",
  },
  {
    q: "Zuno fonctionne-t-il sur une Smart TV Samsung ou LG ?",
    a: "Aucune version Samsung (Tizen) ou LG (webOS) n'est listée par Zuno à ce jour. Sur ces téléviseurs, branchez une box Android TV, un appareil Google TV ou une clé Fire TV compatible sur un port HDMI, puis installez Zuno dessus.",
  },
  {
    q: "Pourquoi je ne trouve pas Downloader ou les options développeur sur ma Fire TV ?",
    a: "Les options développeur sont masquées par défaut : Paramètres, Ma Fire TV, À propos, puis appuyez sept fois sur le nom de l'appareil. Selon le forum Amazon, certains modèles récents comme la Fire TV Stick 4K Select n'autorisent pas l'installation hors Appstore.",
  },
  {
    q: "Comment activer Zuno après l'installation ?",
    a: "Zuno affiche un identifiant d'appareil (M2) dans Réglages puis Mon appareil. Après l'achat d'une licence de l'application, saisissez le S code reçu et ce M2 sur la page Activer du site. La licence concerne l'application seule, sans contenu. Le site indique une activation instantanée.",
  },
  {
    q: "Une question sur l'installation ?",
    a: "Écrivez au support Zuno sur WhatsApp au +44 7307 410512 (wa.me/447307410512). Indiquez votre appareil et l'étape où vous êtes bloqué. Le support aide pour l'installation et l'activation de l'application ; il ne fournit pas de chaînes. Une capture d'écran du message d'erreur aide à répondre plus vite.",
  },
];

export const metadata: Metadata = {
  title: TITLE,
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
  const crumbs = breadcrumbJsonLd([{ name: "Installer Zuno", path: PATH }]);
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

export default function InstallerZunoGuide() {
  return (
    <article className="zuno-page mx-auto max-w-3xl px-4 py-14 sm:px-6">
      <GuideJsonLd />
      <p className="text-xs uppercase tracking-wide text-white/40">
        Guide · Équipe éditoriale · publié le 3 novembre 2026
      </p>
      <h1 className="mt-2 text-3xl font-bold text-white sm:text-4xl">{TITLE}</h1>
      <p className="mt-5 text-base leading-relaxed text-white/80">
        <strong className="text-white">Réponse rapide :</strong> sur Android TV et Google TV, installez
        « ZUNO - IPTV Player » depuis Google Play. Sur Fire TV, installez Downloader, autorisez-le
        dans les options développeur, puis ouvrez l&apos;adresse zuno.7themotion.com/apk. Sur téléphone
        Android, passez par Google Play. Zuno est un lecteur : il n&apos;inclut aucune chaîne, vous
        ajoutez votre propre source légale.
      </p>
      <p className="mt-4 text-sm text-white/50">
        Une question sur l&apos;installation ?{" "}
        <a href={WA_SETUP} target="_blank" rel="noopener noreferrer" className={a}>
          Écrivez au support sur WhatsApp
        </a>
        .
      </p>

      <h2 className={h2}>Quels appareils sont compatibles avec Zuno ?</h2>
      <p className={p}>
        Zuno fonctionne sur Android TV, Google TV, Fire TV (Fire OS), les téléphones et tablettes
        Android, et Windows 10/11 en 64 bits. La fiche Google Play cite les téléviseurs, box et
        projecteurs Android TV ou Google TV, ainsi que les téléphones en mode paysage. Fire TV et
        Windows passent par la page Télécharger du site.
      </p>
      <div className="mt-5 overflow-x-auto rounded-xl border border-white/10">
        <table className="w-full text-left text-sm text-white/70">
          <thead className="bg-white/[0.04] text-white">
            <tr>
              <th className="px-4 py-3 font-semibold">Appareil</th>
              <th className="px-4 py-3 font-semibold">Méthode d&apos;installation</th>
              <th className="px-4 py-3 font-semibold">Source</th>
            </tr>
          </thead>
          <tbody>
            <tr className="border-t border-white/10">
              <td className="px-4 py-3">Android TV, Google TV, projecteur Android</td>
              <td className="px-4 py-3">Google Play : « ZUNO - IPTV Player »</td>
              <td className="px-4 py-3">Fiche Google Play</td>
            </tr>
            <tr className="border-t border-white/10">
              <td className="px-4 py-3">Fire TV (Fire OS)</td>
              <td className="px-4 py-3">Downloader → zuno.7themotion.com/apk</td>
              <td className="px-4 py-3">Page Télécharger</td>
            </tr>
            <tr className="border-t border-white/10">
              <td className="px-4 py-3">Téléphone ou tablette Android</td>
              <td className="px-4 py-3">Google Play (affichage en paysage)</td>
              <td className="px-4 py-3">Fiche Google Play</td>
            </tr>
            <tr className="border-t border-white/10">
              <td className="px-4 py-3">PC Windows 10/11 64 bits</td>
              <td className="px-4 py-3">Zuno-Setup.exe ou archive ZIP</td>
              <td className="px-4 py-3">Page Télécharger</td>
            </tr>
            <tr className="border-t border-white/10">
              <td className="px-4 py-3">Smart TV Samsung (Tizen), LG (webOS), iPhone</td>
              <td className="px-4 py-3">Aucune version listée : passez par une box ou clé HDMI</td>
              <td className="px-4 py-3">—</td>
            </tr>
          </tbody>
        </table>
      </div>

      <h2 className={h2}>Comment installer Zuno sur Android TV ou Google TV ?</h2>
      <p className={p}>
        Installez Zuno depuis le Google Play Store du téléviseur ou de la box : c&apos;est la méthode la
        plus simple, sans fichier à télécharger à la main. L&apos;application est publiée sous le nom
        « ZUNO - IPTV Player », développeur 7 MOTION, et se pilote entièrement à la télécommande
        Android TV ou Google TV.
      </p>
      <ol className="mt-3 list-decimal space-y-2 pl-6">
        <li className={li}>Ouvrez le Google Play Store sur votre Android TV ou votre appareil Google TV.</li>
        <li className={li}>Recherchez « ZUNO - IPTV Player » et vérifiez que le développeur affiché est 7 MOTION.</li>
        <li className={li}>Sélectionnez Installer, puis Ouvrir.</li>
        <li className={li}>
          Notez le M2 affiché dans Réglages puis Mon appareil : il sert à l&apos;
          <Link href="/activer" className={a}>activation</Link>.
        </li>
      </ol>
      <p className={p}>
        Lien direct :{" "}
        <a href={SOURCES[0].href} target="_blank" rel="noopener noreferrer" className={a}>
          ZUNO - IPTV Player sur Google Play
        </a>
        . Google Play indique, appareil par appareil, si l&apos;application est disponible.
      </p>

      <h2 className={h2}>Comment installer Zuno sur Fire TV (Firestick) ?</h2>
      <p className={p}>
        Sur Fire TV, Zuno s&apos;installe avec l&apos;application Downloader, depuis l&apos;adresse officielle
        zuno.7themotion.com/apk, qui renvoie vers le fichier officiel zuno-tv.apk. Il faut d&apos;abord
        autoriser Downloader à installer des applications inconnues dans les options développeur de la
        Fire TV. Comptez quelques minutes.
      </p>
      <ol className="mt-3 list-decimal space-y-2 pl-6">
        <li className={li}>Dans l&apos;Appstore Amazon, recherchez et installez l&apos;application Downloader.</li>
        <li className={li}>
          Ouvrez Paramètres, Ma Fire TV, puis Options pour les développeurs. Si le menu est absent,
          allez dans Ma Fire TV, À propos, et appuyez sept fois sur le nom de l&apos;appareil.
        </li>
        <li className={li}>
          Choisissez Installer des applis inconnues et activez Downloader. Sur les anciennes versions,
          l&apos;option s&apos;appelle Applis de sources inconnues : activez-la.
        </li>
        <li className={li}>Ouvrez Downloader, tapez zuno.7themotion.com/apk et validez.</li>
        <li className={li}>À la fin du téléchargement, sélectionnez Installer, puis Ouvrir.</li>
      </ol>
      <p className={p}>
        Selon le forum Amazon, certains modèles récents, comme la Fire TV Stick 4K Select, ne
        permettent pas d&apos;installer d&apos;applications hors Appstore. Sur ces modèles, utilisez plutôt un
        appareil Android TV ou Google TV. N&apos;installez Zuno qu&apos;à partir de l&apos;adresse officielle
        ci-dessus.
      </p>

      <h2 className={h2}>Comment utiliser Zuno sur une Smart TV ?</h2>
      <p className={p}>
        Si votre Smart TV tourne sous Android TV ou Google TV (c&apos;est le cas de nombreux modèles), suivez
        la méthode Google Play ci-dessus. Pour une Smart TV Samsung ou LG, aucune version Zuno n&apos;est
        listée : branchez une box Android TV, un appareil Google TV ou une clé Fire TV compatible sur
        un port HDMI, puis installez Zuno dessus.
      </p>

      <h2 className={h2}>Comment installer Zuno sur un téléphone ou une tablette ?</h2>
      <p className={p}>
        Sur téléphone ou tablette Android, installez « ZUNO - IPTV Player » depuis Google Play. La
        fiche indique un usage en mode paysage sur les appareils compatibles. Aucune version iPhone ou
        iPad n&apos;est listée à ce jour. Sur PC, utilisez l&apos;installateur Windows de la{" "}
        <Link href="/telecharger" className={a}>page Télécharger</Link>.
      </p>

      <h2 className={h2}>Comment fonctionne le lecteur Zuno ?</h2>
      <p className={p}>
        Zuno lit les sources que vous ajoutez vous-même : listes M3U ou comptes Xtream fournis par un
        service que vous avez le droit d&apos;utiliser. Le lecteur ne crée aucun contenu, il affiche celui
        de votre source dans une interface pensée pour la télécommande. D&apos;après la fiche Google Play,
        l&apos;application organise ensuite :
      </p>
      <ul className="mt-3 list-disc space-y-2 pl-6">
        <li className={li}>plusieurs listes de lecture dans une même application ;</li>
        <li className={li}>les chaînes en direct, films et séries présents dans vos sources ;</li>
        <li className={li}>le guide des programmes (EPG), quand votre source le fournit ;</li>
        <li className={li}>les favoris, l&apos;historique et la reprise de lecture ;</li>
        <li className={li}>les pistes audio et sous-titres présents dans le flux, et le format d&apos;image.</li>
      </ul>
      <p className={p}>
        La qualité d&apos;image, le guide TV et les sous-titres dépendent de votre source, pas de Zuno.
      </p>

      <h2 className={h2}>Zuno inclut-il des chaînes ou un abonnement ?</h2>
      <p className={p}>
        Non. Zuno ne fournit aucune chaîne, aucune liste M3U et aucun abonnement TV. Le site vend
        uniquement une licence de l&apos;application (voir les{" "}
        <Link href="/forfaits" className={a}>forfaits</Link>). Vous apportez votre propre fournisseur,
        légal et sous licence, et vous restez responsable des contenus que vous lisez.
      </p>

      <section id="faq" className="mt-14">
        <h2 className="text-2xl font-bold text-white">Questions fréquentes</h2>
        <p className="mt-3 text-sm text-white/50">Réponses tirées de la fiche Google Play et des pages du site Zuno.</p>
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
          fournisseurs titulaires des licences nécessaires. Cette page ne contient aucun lien affilié.
          Les marques citées (Amazon, Fire TV, Google, Android TV, Samsung, LG) appartiennent à leurs
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
          Une question sur l&apos;installation ?{" "}
          <a href={WA_SETUP} target="_blank" rel="noopener noreferrer" className={a}>
            WhatsApp +44 7307 410512
          </a>
        </p>
      </section>
    </article>
  );
}
