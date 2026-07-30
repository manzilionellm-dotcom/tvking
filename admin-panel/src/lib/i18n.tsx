import {
  createContext, useCallback, useContext, useEffect, useState, type ReactNode,
} from 'react';

// =========================================================
//  i18n.tsx — Multilangue du panel (FR / EN / AR)
// =========================================================
//  Leger, sans dependance. La langue est memorisee en localStorage
//  (par appareil/navigateur). L'arabe bascule l'interface en
//  droite-a-gauche (dir=rtl) automatiquement.
// =========================================================

export type Lang = 'fr' | 'en' | 'ar';

export const LANGS: { code: Lang; label: string }[] = [
  { code: 'fr', label: 'Français' },
  { code: 'en', label: 'English' },
  { code: 'ar', label: 'العربية' },
];

const RTL: Lang[] = ['ar'];
const STORE_KEY = 'panel_lang';

// Dictionnaire : cle -> { fr, en, ar }
const STR: Record<string, Record<Lang, string>> = {
  // --- Marque / roles ---
  'brand': { fr: 'The Few', en: 'The Few', ar: 'The Few' },
  'role.admin': { fr: 'Super Admin', en: 'Super Admin', ar: 'المشرف العام' },
  'role.reseller': { fr: 'Revendeur', en: 'Reseller', ar: 'موزّع' },
  'role.adminFull': { fr: 'Administrateur', en: 'Administrator', ar: 'مدير' },

  // --- Navigation ---
  'nav.dashboard': { fr: 'Tableau de bord', en: 'Dashboard', ar: 'لوحة التحكم' },
  // Ancien dashboard KPI (clients, licences, revenu…), déplacé sur /stats
  // depuis que le « Tableau de bord » C22 est la page d'accueil.
  'nav.stats': { fr: 'Statistiques', en: 'Statistics', ar: 'الإحصاءات' },
  'nav.activate': { fr: 'Activer un appareil', en: 'Activate a device', ar: 'تفعيل جهاز' },
  'nav.pushSource': { fr: 'Pousser une playlist', en: 'Push a playlist', ar: 'إرسال قائمة تشغيل' },
  'nav.controlCenter': { fr: 'Centre de contrôle', en: 'Control center', ar: 'مركز التحكم' },
  'nav.forceUpdate': { fr: 'Mise à jour forcée', en: 'Force update', ar: 'تحديث إجباري' },
  'nav.online': { fr: 'En ligne', en: 'Online', ar: 'متصل' },
  'nav.featured': { fr: 'Favori du jour', en: 'Daily pick', ar: 'مختار اليوم' },
  'nav.theme': { fr: 'Thème', en: 'Theme', ar: 'السمة' },
  'nav.ad': { fr: 'Pub vidéo', en: 'Video ad', ar: 'إعلان فيديو' },
  'nav.pricing': { fr: 'Tarifs', en: 'Pricing', ar: 'الأسعار' },
  'nav.reviews': { fr: 'Avis clients', en: 'Reviews', ar: 'آراء العملاء' },
  'nav.homeManager': { fr: 'Accueil', en: 'Home', ar: 'الرئيسية' },
  'nav.notifications': { fr: 'Annonces', en: 'Announcements', ar: 'الإعلانات' },
  'nav.resellers': { fr: 'Revendeurs', en: 'Resellers', ar: 'الموزّعون' },
  'nav.myResellers': { fr: 'Mes revendeurs', en: 'My resellers', ar: 'موزّعوني' },
  'nav.customers': { fr: 'Clients', en: 'Customers', ar: 'العملاء' },
  'nav.devices': { fr: 'Appareils', en: 'Devices', ar: 'الأجهزة' },
  'nav.radar': { fr: 'Radar d’expiration', en: 'Expiry radar', ar: 'رادار الانتهاء' },
  'nav.gateway': { fr: 'Passerelle', en: 'Gateway', ar: 'البوابة' },
  'nav.credits': { fr: 'Crédits', en: 'Credits', ar: 'الأرصدة' },
  'nav.myDevices': { fr: 'Mes appareils', en: 'My devices', ar: 'أجهزتي' },
  'nav.apps': { fr: 'Applications', en: 'Apps', ar: 'التطبيقات' },
  'nav.servers': { fr: 'Serveurs', en: 'Servers', ar: 'الخوادم' },
  'nav.activations': { fr: 'Activations', en: 'Activations', ar: 'التفعيلات' },
  'nav.myActivations': { fr: 'Mes activations', en: 'My activations', ar: 'تفعيلاتي' },
  'nav.history': { fr: 'Historique', en: 'History', ar: 'السجل' },
  'nav.references': { fr: 'Références', en: 'References', ar: 'المراجع' },
  'nav.transfer': { fr: 'Transférer', en: 'Transfer', ar: 'نقل' },
  'nav.shares': { fr: 'Partages & prêts', en: 'Shares & loans', ar: 'المشاركات والإعارات' },
  'nav.masters': { fr: 'Comptes maîtres', en: 'Master accounts', ar: 'الحسابات الرئيسية' },
  'nav.adminMonitor': { fr: 'Admin Monitoring', en: 'Admin Monitoring', ar: 'مراقبة المشرف' },
  'nav.families': { fr: 'Famille', en: 'Family', ar: 'العائلة' },
  'nav.account': { fr: 'Mon compte', en: 'My account', ar: 'حسابي' },
  // Labo du Maître — visible ADMIN uniquement (jamais dans le menu revendeur).
  'nav.lab': { fr: '🔬 Labo du Maître', en: '🔬 Master Lab', ar: '🔬 مختبر المدير' },

  // --- Sections du menu (regroupement Sidebar) ---
  'navsec.pilot': { fr: 'Pilotage', en: 'Overview', ar: 'نظرة عامة' },
  'navsec.activation': { fr: 'Activation & abonnés', en: 'Activation & subscribers', ar: 'التفعيل والمشتركون' },
  'navsec.channels': { fr: 'Chaînes & sources', en: 'Channels & sources', ar: 'القنوات والمصادر' },
  'navsec.content': { fr: 'App & contenu', en: 'App & content', ar: 'التطبيق والمحتوى' },
  'navsec.system': { fr: 'Système', en: 'System', ar: 'النظام' },

  // --- Commun ---
  'common.credits': { fr: 'Crédits', en: 'Credits', ar: 'الأرصدة' },
  'common.logout': { fr: 'Se déconnecter', en: 'Sign out', ar: 'تسجيل الخروج' },
  'common.save': { fr: 'Enregistrer', en: 'Save', ar: 'حفظ' },
  'common.cancel': { fr: 'Annuler', en: 'Cancel', ar: 'إلغاء' },
  'common.close': { fr: 'Fermer', en: 'Close', ar: 'إغلاق' },
  'common.language': { fr: 'Langue', en: 'Language', ar: 'اللغة' },

  // --- Connexion ---
  'login.subtitleAdmin': { fr: 'Super Admin', en: 'Super Admin', ar: 'المشرف العام' },
  'login.subtitleReseller': { fr: 'Espace revendeur', en: 'Reseller area', ar: 'مساحة الموزّع' },
  'login.tabAdmin': { fr: 'Admin', en: 'Admin', ar: 'المشرف' },
  'login.tabReseller': { fr: 'Revendeur', en: 'Reseller', ar: 'موزّع' },
  'login.adminDesc': { fr: 'Propriétaire — accès total : revendeurs, apps, clients, serveurs.', en: 'Owner — full access: resellers, apps, customers, servers.', ar: 'المالك — وصول كامل: الموزّعون والتطبيقات والعملاء والخوادم.' },
  'login.resellerDesc': { fr: 'Revendeur — active tes clients avec tes crédits.', en: 'Reseller — activate your clients with your credits.', ar: 'الموزّع — فعّل عملاءك باستخدام رصيدك.' },
  'login.identifier': { fr: 'Identifiant', en: 'Username', ar: 'المعرّف' },
  'login.password': { fr: 'Mot de passe', en: 'Password', ar: 'كلمة المرور' },
  'login.signin': { fr: 'Se connecter', en: 'Sign in', ar: 'تسجيل الدخول' },
  'login.signing': { fr: 'Connexion…', en: 'Signing in…', ar: 'جارٍ الدخول…' },
  'login.fail': { fr: 'Connexion impossible. Réessaie.', en: 'Sign-in failed. Try again.', ar: 'تعذّر تسجيل الدخول. حاول مجددًا.' },
  'login.hintReseller': { fr: "Connecte-toi avec l'email et le mot de passe fournis par ton fournisseur.", en: 'Sign in with the email and password provided by your supplier.', ar: 'سجّل الدخول بالبريد وكلمة المرور المقدّمين من مزوّدك.' },

  // --- Dashboard ---
  'dash.subtitle': { fr: "Vue d'ensemble", en: 'Overview', ar: 'نظرة عامة' },
  'dash.clients': { fr: 'Clients', en: 'Clients', ar: 'العملاء' },
  'dash.devices': { fr: 'Appareils', en: 'Devices', ar: 'الأجهزة' },
  'dash.licenses': { fr: 'Licences', en: 'Licenses', ar: 'التراخيص' },
  'dash.active': { fr: 'Actives', en: 'Active', ar: 'نشِطة' },
  'dash.expired': { fr: 'Expirées', en: 'Expired', ar: 'منتهية' },
  'dash.apps': { fr: 'Apps gérées', en: 'Managed apps', ar: 'التطبيقات' },
  'dash.resellers': { fr: 'Revendeurs', en: 'Resellers', ar: 'الموزّعون' },
  'dash.revenue30': { fr: 'Revenu 30j', en: 'Revenue 30d', ar: 'إيراد 30 يوم' },
  'dash.myCredits': { fr: 'Mes crédits', en: 'My credits', ar: 'أرصدتي' },

  // --- Labo du Maître (admin uniquement — espace de test privé) ---
  'lab.title': { fr: 'Labo du Maître', en: 'Master Lab', ar: 'مختبر المدير' },
  'lab.subtitle': { fr: 'Espace de test privé', en: 'Private testing space', ar: 'مساحة اختبار خاصة' },
  'lab.banner': {
    fr: 'Tout ce qui vit ici est PRIVÉ : sources de test poussées uniquement sur tes appareils maîtres, invisibles des revendeurs et des clients, exclues des statistiques. Teste librement.',
    en: 'Everything here is PRIVATE: test sources pushed only to your master devices, invisible to resellers and customers, excluded from statistics. Test freely.',
    ar: 'كل ما هنا خاص: مصادر اختبار تُرسل فقط إلى أجهزتك الرئيسية، غير مرئية للموزّعين والعملاء، ومستثناة من الإحصاءات. اختبر بحرّية.',
  },
  'lab.addTitle': { fr: 'Ajouter une source de test', en: 'Add a test source', ar: 'إضافة مصدر اختبار' },
  'lab.name': { fr: 'Nom', en: 'Name', ar: 'الاسم' },
  'lab.namePh': { fr: 'Ex. : Test serveur Alpha', en: 'E.g.: Alpha server test', ar: 'مثال: اختبار خادم ألفا' },
  'lab.url': { fr: 'URL M3U / Xtream', en: 'M3U / Xtream URL', ar: 'رابط M3U / Xtream' },
  'lab.urlPh': { fr: 'http(s)://…', en: 'http(s)://…', ar: 'http(s)://…' },
  'lab.add': { fr: 'Ajouter au labo', en: 'Add to lab', ar: 'إضافة إلى المختبر' },
  'lab.adding': { fr: 'Ajout…', en: 'Adding…', ar: 'جارٍ الإضافة…' },
  'lab.nameRequired': { fr: 'Donne un nom à la source.', en: 'Give the source a name.', ar: 'أعطِ المصدر اسمًا.' },
  'lab.invalidUrl': {
    fr: 'URL invalide — elle doit commencer par http:// ou https://.',
    en: 'Invalid URL — it must start with http:// or https://.',
    ar: 'رابط غير صالح — يجب أن يبدأ بـ http:// أو https://.',
  },
  'lab.addedOk': {
    fr: 'Copiée automatiquement sur {n} appareil(s) maître(s).',
    en: 'Automatically copied to {n} master device(s).',
    ar: 'نُسخت تلقائيًا إلى {n} جهاز/أجهزة رئيسية.',
  },
  'lab.listTitle': { fr: 'Sources du labo', en: 'Lab sources', ar: 'مصادر المختبر' },
  'lab.masters': { fr: '{n} appareil(s) maître(s)', en: '{n} master device(s)', ar: '{n} جهاز/أجهزة رئيسية' },
  'lab.delete': { fr: 'Supprimer', en: 'Delete', ar: 'حذف' },
  'lab.deleting': { fr: 'Suppression…', en: 'Deleting…', ar: 'جارٍ الحذف…' },
  'lab.deleteConfirm': {
    fr: 'Supprimer « {name} » ? La source sera retirée de tes appareils maîtres.',
    en: 'Delete “{name}”? The source will be removed from your master devices.',
    ar: 'حذف «{name}»؟ سيُزال المصدر من أجهزتك الرئيسية.',
  },
  'lab.deletedOk': { fr: 'Source retirée du labo.', en: 'Source removed from the lab.', ar: 'أُزيل المصدر من المختبر.' },
  'lab.empty': {
    fr: 'Aucune source dans le labo. Ajoute ta première M3U de test ci-dessus.',
    en: 'No sources in the lab yet. Add your first test M3U above.',
    ar: 'لا مصادر في المختبر بعد. أضف أول M3U للاختبار أعلاه.',
  },
  'lab.soonTitle': { fr: 'Le Labo arrive bientôt', en: 'The Lab is coming soon', ar: 'المختبر قادم قريبًا' },
  'lab.soonMsg': {
    fr: "Le serveur n'expose pas encore le Labo du Maître (mise à jour du worker en cours de déploiement). Rien de cassé : réessaie dans quelques minutes.",
    en: 'The server does not expose the Master Lab yet (worker update being deployed). Nothing is broken: try again in a few minutes.',
    ar: 'الخادم لا يوفّر مختبر المدير بعد (تحديث الخادم قيد النشر). لا شيء معطّل: أعد المحاولة بعد دقائق.',
  },
  'lab.errorTitle': { fr: 'Impossible de charger le labo', en: 'Could not load the lab', ar: 'تعذّر تحميل المختبر' },
  'lab.errorAdd': { fr: "Impossible d'ajouter la source.", en: 'Could not add the source.', ar: 'تعذّرت إضافة المصدر.' },
  'lab.errorDelete': { fr: 'Impossible de supprimer la source.', en: 'Could not delete the source.', ar: 'تعذّر حذف المصدر.' },
  'lab.retry': { fr: '↻ Réessayer', en: '↻ Retry', ar: '↻ إعادة المحاولة' },

  // --- Tableau de bord : bandeau d'alertes proactives (Vague C25) ---
  // Le {n} est interpolé côté page (le t() ne gère pas les variables).
  'overview.alertsTitle': { fr: 'Alertes', en: 'Alerts', ar: 'التنبيهات' },
  'overview.alertExpiring': {
    fr: '⏰ {n} abonnement(s) expirent cette semaine',
    en: '⏰ {n} subscription(s) expiring this week',
    ar: '⏰ {n} اشتراك ينتهي هذا الأسبوع',
  },
  'overview.alertSilent': {
    fr: '🔇 {n} box(es) silencieuse(s) depuis 7 jours',
    en: '🔇 {n} box(es) silent for 7 days',
    ar: '🔇 {n} جهاز صامت منذ 7 أيام',
  },
  'overview.alertErrors': {
    fr: "⚠️ Pic d'erreurs — {n} sur 7 j",
    en: '⚠️ Error spike — {n} over 7 days',
    ar: '⚠️ ارتفاع في الأخطاء — {n} خلال 7 أيام',
  },
  'overview.alertAction': { fr: 'Voir', en: 'View', ar: 'عرض' },

  // --- Mon compte ---
  'account.identifier': { fr: 'Identifiant', en: 'Username', ar: 'المعرّف' },
  'account.role': { fr: 'Rôle', en: 'Role', ar: 'الدور' },
  'account.changePwd': { fr: 'Changer mon mot de passe', en: 'Change my password', ar: 'تغيير كلمة المرور' },
  'account.current': { fr: 'Mot de passe actuel', en: 'Current password', ar: 'كلمة المرور الحالية' },
  'account.new': { fr: 'Nouveau mot de passe', en: 'New password', ar: 'كلمة المرور الجديدة' },
  'account.confirm': { fr: 'Confirmer le nouveau', en: 'Confirm new', ar: 'تأكيد الجديدة' },
  'account.update': { fr: 'Mettre à jour', en: 'Update', ar: 'تحديث' },
  'account.updating': { fr: 'Modification…', en: 'Updating…', ar: 'جارٍ التحديث…' },
  'account.pwdOk': { fr: 'Mot de passe modifié ✔', en: 'Password changed ✔', ar: 'تم تغيير كلمة المرور ✔' },
  'account.pwdShort': { fr: 'Le mot de passe doit faire au moins 4 caractères.', en: 'Password must be at least 4 characters.', ar: 'يجب ألا تقل كلمة المرور عن 4 أحرف.' },
  'account.pwdMismatch': { fr: 'La confirmation ne correspond pas.', en: 'Confirmation does not match.', ar: 'التأكيد غير مطابق.' },
};

function applyDir(lang: Lang) {
  if (typeof document === 'undefined') return;
  document.documentElement.dir = RTL.includes(lang) ? 'rtl' : 'ltr';
  document.documentElement.lang = lang;
}

export function getLang(): Lang {
  try {
    const v = localStorage.getItem(STORE_KEY) as Lang | null;
    if (v && LANGS.some((l) => l.code === v)) return v;
  } catch { /* ignore */ }
  return 'fr';
}

interface I18nCtx { lang: Lang; setLang: (l: Lang) => void; t: (k: string) => string; }
const Ctx = createContext<I18nCtx>({ lang: 'fr', setLang: () => {}, t: (k) => k });

export function LangProvider({ children }: { children: ReactNode }) {
  const [lang, setLangState] = useState<Lang>(getLang());

  useEffect(() => { applyDir(lang); }, [lang]);

  const setLang = useCallback((l: Lang) => {
    try { localStorage.setItem(STORE_KEY, l); } catch { /* ignore */ }
    setLangState(l);
  }, []);

  const t = useCallback(
    (k: string) => {
      const e = STR[k];
      if (!e) return k;
      return e[lang] || e.fr || k;
    },
    [lang],
  );

  return <Ctx.Provider value={{ lang, setLang, t }}>{children}</Ctx.Provider>;
}

export function useI18n(): I18nCtx { return useContext(Ctx); }
export function useT(): (k: string) => string { return useContext(Ctx).t; }

/// Petit selecteur de langue reutilisable (login, mon compte…).
export function LangSelect({ className }: { className?: string }) {
  const { lang, setLang } = useI18n();
  return (
    <select
      value={lang}
      onChange={(e) => setLang(e.target.value as Lang)}
      aria-label="Language"
      className={
        className ||
        'rounded-md border border-white/10 bg-slate px-2 py-1.5 text-xs text-ink-secondary outline-none focus:ring-1 focus:ring-accent'
      }
    >
      {LANGS.map((l) => (
        <option key={l.code} value={l.code}>{l.label}</option>
      ))}
    </select>
  );
}
