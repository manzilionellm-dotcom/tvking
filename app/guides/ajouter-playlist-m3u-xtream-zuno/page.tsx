import type { Metadata } from "next";
import Link from "next/link";
import { breadcrumbJsonLd, graph, jsonLdString, aio } from "../../../lib/aio";
import { canonicalFor, canonicalUrl } from "../../lib/seo";

/**
 * Guide Q&R : ajouter sa propre source (M3U ou Xtream) dans Zuno.
 * Fonctions décrites d'après la fiche Google Play de Zuno (lue le 3 nov. 2026).
 * Chiffres de débit relevés le 3 nov. 2026 sur les pages officielles listées dans SOURCES.
 * Zuno ne fournit aucune chaîne : ne jamais citer de fournisseur ni de liste.
 */

const PATH = "/guides/ajouter-playlist-m3u-xtream-zuno";
const TITLE = "Ajouter une playlist M3U ou un compte Xtream dans Zuno";
const DESCRIPTION =
  "Comment ajouter votre propre playlist M3U ou votre compte Xtream (serveur, identifiant, mot de passe) dans le lecteur Zuno, quel débit prévoir et que faire si la liste ne charge pas.";
const PUBLISHED = "2026-11-03";
const WA_HELP = `https://wa.me/447307410512?text=${encodeURIComponent(
  "Bonjour Zuno — j'ai une question sur l'ajout de ma playlist.",
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
    label: "Amazon — Regarder en 4K Ultra HD sur un appareil Fire TV (consulté le 3 novembre 2026)",
    href: "https://www.amazon.com/gp/help/customer/display.html?nodeId=201859000",
  },
];

const FAQ = [
  {
    q: "Zuno fournit-il une playlist ou des identifiants Xtream ?",
    a: "Non. Zuno est uniquement un lecteur : il ne fournit, ne vend et n'héberge aucune chaîne, aucune liste M3U et aucun compte Xtream. Vous ajoutez les accès remis par un service que vous avez le droit d'utiliser. La licence vendue sur ce site concerne seulement l'application, sans aucun contenu inclus.",
  },
  {
    q: "Peut-on ajouter plusieurs playlists dans Zuno ?",
    a: "Oui. La fiche Google Play de Zuno indique que vous pouvez ajouter et gérer plusieurs listes de lecture dans la même application. C'est pratique si vous avez une liste pour la télévision en direct et une autre pour la vidéo à la demande, fournies par des services que vous avez le droit d'utiliser.",
  },
  {
    q: "Pourquoi une playlist supprimée ne revient-elle pas ?",
    a: "C'est voulu. D'après la fiche Google Play, les suppressions de listes sont conservées lors des synchronisations et des redémarrages : une liste supprimée ne revient pas après une simple actualisation. Pour la récupérer, ajoutez-la de nouveau dans l'application avec son adresse M3U ou ses identifiants Xtream d'origine.",
  },
  {
    q: "Le guide TV (EPG) s'affiche-t-il automatiquement ?",
    a: "Seulement si votre source le fournit. La fiche Google Play précise que le guide des programmes est affiché lorsqu'il est disponible, et que le guide TV, les pistes audio, les sous-titres et la qualité vidéo dépendent des médias fournis par vos sources. Zuno ne crée pas de programmes manquants.",
  },
  {
    q: "Quel débit faut-il pour regarder une liste en HD ?",
    a: "Comptez au moins 5 Mbit/s par écran pour de la HD 1080p : c'est le chiffre donné par Netflix et par l'aide YouTube, consultés le 3 novembre 2026. Pour la 4K, Netflix recommande 15 Mbit/s et YouTube 20 Mbit/s. Additionnez ces débits si plusieurs écrans regardent en même temps.",
  },
  {
    q: "Une question sur l'ajout de votre playlist ?",
    a: "Écrivez au support Zuno sur WhatsApp au +44 7307 410512 (wa.me/447307410512). Précisez votre appareil, le format de votre source (M3U ou Xtream) et le message affiché. Ne partagez jamais votre mot de passe en clair. Le support aide pour l'application uniquement : il ne fournit ni chaîne ni liste.",
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
  const crumbs = breadcrumbJsonLd([{ name: "Ajouter une playlist dans Zuno", path: PATH }]);
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

export default function AjouterPlaylistZunoGuide() {
  return (
    <article className="zuno-page mx-auto max-w-3xl px-4 py-14 sm:px-6">
      <GuideJsonLd />
      <p className="text-xs uppercase tracking-wide text-white/40">
        Guide · Équipe éditoriale · publié le 3 novembre 2026
      </p>
      <h1 className="mt-2 text-3xl font-bold text-white sm:text-4xl">{TITLE}</h1>
      <p className="mt-5 text-base leading-relaxed text-white/80">
        <strong className="text-white">Réponse rapide :</strong> ouvrez Zuno, choisissez d&apos;ajouter une
        playlist, puis collez l&apos;adresse M3U ou M3U8 fournie par votre fournisseur, ou saisissez le
        serveur, l&apos;identifiant et le mot de passe de votre compte Xtream. Zuno charge ensuite les
        chaînes, films et séries de votre source. Le lecteur ne fournit aucune liste : utilisez un service
        sous licence.
      </p>
      <p className="mt-4 text-sm text-white/50">
        Une question ?{" "}
        <a href={WA_HELP} target="_blank" rel="noopener noreferrer" className={a}>
          wa.me/447307410512
        </a>
      </p>

      <h2 className={h2}>Que faut-il avant d&apos;ajouter une playlist dans Zuno ?</h2>
      <p className={p}>
        Il vous faut trois choses : Zuno installé et activé sur votre appareil, une connexion Internet
        stable, et les accès remis par un service que vous avez le droit d&apos;utiliser. Ces accès prennent
        la forme d&apos;une adresse M3U ou M3U8, ou d&apos;un trio serveur, identifiant et mot de passe pour un
        compte Xtream.
      </p>
      <ul className="mt-3 list-disc space-y-2 pl-6">
        <li className={li}>
          Zuno installé : voir le <Link href="/guides/installer-zuno" className={a}>guide d&apos;installation</Link>{" "}
          (Android TV, Google TV, Fire TV, téléphone, Windows).
        </li>
        <li className={li}>
          Zuno activé : la fiche Google Play précise que l&apos;accès à l&apos;application dépend de son
          activation (<Link href="/activer" className={a}>page Activer</Link>).
        </li>
        <li className={li}>Vos accès, copiés tels quels depuis l&apos;e-mail ou l&apos;espace client de votre fournisseur.</li>
      </ul>

      <h2 className={h2}>Quelle différence entre une playlist M3U et un compte Xtream ?</h2>
      <p className={p}>
        Une playlist M3U est une seule adresse web qui contient la liste des flux, alors qu&apos;un compte
        Xtream se compose d&apos;une adresse de serveur, d&apos;un identifiant et d&apos;un mot de passe. La fiche
        Google Play de Zuno cite les deux formats. Votre fournisseur indique lequel utiliser ; en cas de
        doute, demandez-lui.
      </p>
      <div className="mt-5 overflow-x-auto rounded-xl border border-white/10">
        <table className="w-full text-left text-sm text-white/70">
          <thead className="bg-white/[0.04] text-white">
            <tr>
              <th className={th}>Format</th>
              <th className={th}>Ce que vous saisissez</th>
              <th className={th}>Forme attendue</th>
              <th className={th}>Bon à savoir</th>
            </tr>
          </thead>
          <tbody>
            <tr className="border-t border-white/10">
              <td className={td}>M3U / M3U8</td>
              <td className={td}>Une adresse complète</td>
              <td className={td}>Commence par http:// ou https://</td>
              <td className={td}>Le guide TV (EPG) dépend de votre source</td>
            </tr>
            <tr className="border-t border-white/10">
              <td className={td}>Xtream</td>
              <td className={td}>Serveur + identifiant + mot de passe</td>
              <td className={td}>Serveur du type http://adresse:port</td>
              <td className={td}>Donne souvent accès au direct, aux films et aux séries</td>
            </tr>
          </tbody>
        </table>
      </div>

      <h2 className={h2}>Comment ajouter une playlist M3U dans Zuno ?</h2>
      <p className={p}>
        Collez l&apos;adresse complète de la liste dans l&apos;écran d&apos;ajout de playlist de Zuno. Elle doit
        commencer par http:// ou https:// et vous est remise par votre fournisseur. Donnez un nom à la liste
        pour la retrouver facilement, validez, puis patientez pendant le chargement des chaînes, des films et
        des séries.
      </p>
      <ol className="mt-3 list-decimal space-y-2 pl-6">
        <li className={li}>Ouvrez Zuno et allez dans la gestion des playlists, puis choisissez d&apos;ajouter une playlist.</li>
        <li className={li}>Choisissez le format M3U (adresse URL).</li>
        <li className={li}>Collez l&apos;adresse sans espace avant ni après, et donnez un nom à la liste.</li>
        <li className={li}>Validez. Les catégories de votre source apparaissent à la fin du chargement.</li>
      </ol>
      <p className={p}>
        Sur Android TV ou Fire TV, la saisie à la télécommande est longue : copiez l&apos;adresse sans erreur,
        une seule lettre fausse suffit à bloquer le chargement. Les intitulés exacts des menus peuvent varier
        selon la version de l&apos;application.
      </p>

      <h2 className={h2}>Comment se connecter avec un compte Xtream dans Zuno ?</h2>
      <p className={p}>
        Choisissez le format Xtream dans l&apos;écran d&apos;ajout, puis saisissez l&apos;adresse du serveur, votre
        identifiant et votre mot de passe exactement comme votre fournisseur les a écrits. Le serveur a
        généralement la forme http://adresse:port. Après validation, Zuno charge le direct et, si votre
        abonnement les inclut, les films et les séries.
      </p>
      <ol className="mt-3 list-decimal space-y-2 pl-6">
        <li className={li}>Dans la gestion des playlists, choisissez d&apos;ajouter une source au format Xtream.</li>
        <li className={li}>Saisissez le serveur avec son port s&apos;il y en a un (par exemple :8080).</li>
        <li className={li}>Saisissez l&apos;identifiant puis le mot de passe, en respectant majuscules et minuscules.</li>
        <li className={li}>Validez et attendez la fin de la synchronisation.</li>
      </ol>

      <h2 className={h2}>Quel débit Internet prévoir pour lire votre liste ?</h2>
      <p className={p}>
        Prévoyez au moins 5 Mbit/s par écran pour la HD 1080p et 15 à 20 Mbit/s pour la 4K. Netflix
        recommande 3 Mbit/s en 720p, 5 Mbit/s en 1080p et 15 Mbit/s en 4K ; l&apos;aide YouTube donne 20 Mbit/s
        pour la 4K. Ces chiffres ont été relevés le 3 novembre 2026.
      </p>
      <div className="mt-5 overflow-x-auto rounded-xl border border-white/10">
        <table className="w-full text-left text-sm text-white/70">
          <thead className="bg-white/[0.04] text-white">
            <tr>
              <th className={th}>Qualité</th>
              <th className={th}>Netflix</th>
              <th className={th}>YouTube</th>
              <th className={th}>Amazon Fire TV</th>
            </tr>
          </thead>
          <tbody>
            <tr className="border-t border-white/10">
              <td className={td}>HD 720p</td>
              <td className={td}>3 Mbit/s</td>
              <td className={td}>2,5 Mbit/s</td>
              <td className={td}>—</td>
            </tr>
            <tr className="border-t border-white/10">
              <td className={td}>HD 1080p</td>
              <td className={td}>5 Mbit/s</td>
              <td className={td}>5 Mbit/s</td>
              <td className={td}>—</td>
            </tr>
            <tr className="border-t border-white/10">
              <td className={td}>4K Ultra HD</td>
              <td className={td}>15 Mbit/s</td>
              <td className={td}>20 Mbit/s</td>
              <td className={td}>15 Mbit/s minimum</td>
            </tr>
          </tbody>
        </table>
      </div>
      <p className="mt-3 text-xs text-white/45">
        Débits recommandés par chaque service pour ses propres vidéos, relevés le 3 novembre 2026. Votre
        source peut demander plus ou moins selon son encodage.
      </p>

      <h2 className={h2}>Que faire si la playlist ne charge pas dans Zuno ?</h2>
      <p className={p}>
        Vérifiez d&apos;abord l&apos;adresse ou les identifiants, car une faute de frappe est la cause la plus
        fréquente. Testez ensuite votre connexion, puis demandez à votre fournisseur si votre abonnement est
        actif et si le format choisi est le bon. Une liste qui affiche zéro chaîne vient presque toujours de
        la source, pas du lecteur.
      </p>
      <ol className="mt-3 list-decimal space-y-2 pl-6">
        <li className={li}>Recopiez l&apos;adresse ou les identifiants, sans espace en trop.</li>
        <li className={li}>Vérifiez que l&apos;adresse commence bien par http:// ou https://.</li>
        <li className={li}>Essayez l&apos;autre format si votre fournisseur propose M3U et Xtream.</li>
        <li className={li}>Redémarrez l&apos;appareil et la box Internet, puis relancez la synchronisation.</li>
        <li className={li}>
          Toujours bloqué ? Consultez le guide{" "}
          <Link href="/guides/zuno-coupures-erreurs-lecture" className={a}>coupures et erreurs de lecture</Link>.
        </li>
      </ol>

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
          audiovisuel, aucune liste et aucun compte. N&apos;ajoutez que des sources que vous avez le droit de
          regarder, auprès de fournisseurs titulaires des licences nécessaires ; vous restez responsable des
          contenus lus. Cette page ne contient aucun lien affilié. Les marques citées (Netflix, YouTube,
          Google, Amazon, Fire TV, Android TV) appartiennent à leurs propriétaires ; Zuno n&apos;est affilié à
          aucun d&apos;entre eux.
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
