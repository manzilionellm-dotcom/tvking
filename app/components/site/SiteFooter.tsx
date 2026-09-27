import Link from "next/link";

export default function SiteFooter() {
  return (
    <footer className="mt-auto border-t border-white/8 bg-[#070709]">
      <div className="mx-auto grid max-w-6xl gap-8 px-4 py-12 sm:px-6 md:grid-cols-3">
        <div>
          <p className="text-lg font-bold text-white">Zuno</p>
          <p className="mt-1 text-sm text-white/45">TV King — lecteur multi-appareils</p>
          <p className="mt-4 text-xs leading-relaxed text-white/35">
            7 Few, LLC — 131 Continental Dr Suite 305, Newark, DE 19713, United States
          </p>
        </div>
        <div className="flex flex-col gap-2 text-sm">
          <p className="mb-1 font-semibold text-white/70">Parcours</p>
          <Link href="/forfaits" className="text-white/45 hover:text-white">Forfaits</Link>
          <Link href="/activer" className="text-white/45 hover:text-white">Activer</Link>
          <Link href="/telecharger" className="text-white/45 hover:text-white">Télécharger</Link>
          <Link href="/revendeur" className="text-white/45 hover:text-white">Devenir revendeur</Link>
        </div>
        <div className="flex flex-col gap-2 text-sm">
          <p className="mb-1 font-semibold text-white/70">Infos</p>
          <Link href="/faq" className="text-white/45 hover:text-white">FAQ</Link>
          <Link href="/legal" className="text-white/45 hover:text-white">Mentions légales</Link>
          <Link href="/connexion" className="text-white/45 hover:text-white">Connexion</Link>
        </div>
      </div>
      <div className="border-t border-white/5 py-4 text-center text-xs text-white/30">
        © {new Date().getFullYear()} 7 Few, LLC · Zuno
      </div>
    </footer>
  );
}
