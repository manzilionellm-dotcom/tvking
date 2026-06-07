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
  'brand': { fr: 'BLACK7 ROYAL', en: 'BLACK7 ROYAL', ar: 'BLACK7 ROYAL' },
  'role.admin': { fr: 'Super Admin', en: 'Super Admin', ar: 'المشرف العام' },
  'role.reseller': { fr: 'Revendeur', en: 'Reseller', ar: 'موزّع' },
  'role.adminFull': { fr: 'Administrateur', en: 'Administrator', ar: 'مدير' },

  // --- Navigation ---
  'nav.dashboard': { fr: 'Tableau de bord', en: 'Dashboard', ar: 'لوحة التحكم' },
  'nav.activate': { fr: 'Activer un appareil', en: 'Activate a device', ar: 'تفعيل جهاز' },
  'nav.pushSource': { fr: 'Pousser une playlist', en: 'Push a playlist', ar: 'إرسال قائمة تشغيل' },
  'nav.controlCenter': { fr: 'Centre de contrôle', en: 'Control center', ar: 'مركز التحكم' },
  'nav.homeManager': { fr: 'Accueil', en: 'Home', ar: 'الرئيسية' },
  'nav.notifications': { fr: 'Annonces', en: 'Announcements', ar: 'الإعلانات' },
  'nav.resellers': { fr: 'Revendeurs', en: 'Resellers', ar: 'الموزّعون' },
  'nav.myResellers': { fr: 'Mes revendeurs', en: 'My resellers', ar: 'موزّعوني' },
  'nav.customers': { fr: 'Clients', en: 'Customers', ar: 'العملاء' },
  'nav.devices': { fr: 'Appareils', en: 'Devices', ar: 'الأجهزة' },
  'nav.myDevices': { fr: 'Mes appareils', en: 'My devices', ar: 'أجهزتي' },
  'nav.apps': { fr: 'Applications', en: 'Apps', ar: 'التطبيقات' },
  'nav.servers': { fr: 'Serveurs', en: 'Servers', ar: 'الخوادم' },
  'nav.activations': { fr: 'Activations', en: 'Activations', ar: 'التفعيلات' },
  'nav.myActivations': { fr: 'Mes activations', en: 'My activations', ar: 'تفعيلاتي' },
  'nav.account': { fr: 'Mon compte', en: 'My account', ar: 'حسابي' },

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
