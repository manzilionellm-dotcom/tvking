#!/usr/bin/env python3
# =========================================================
#  add_tv_l10n.py — Injecte les cles de traduction de The Few TV
#  dans les 8 fichiers app_<code>.arb (fr/en/es/sv/da/nb/ar/sw).
#  Idempotent : ne re-ecrit que les cles manquantes.
# =========================================================
import json, os, collections

ARB_DIR = os.path.join(os.path.dirname(__file__), '..', 'lib', 'l10n')
LANGS = ['fr', 'en', 'es', 'sv', 'da', 'nb', 'ar', 'sw']

# key -> {lang: value}
T = {
 'tvActivationTagline': {
   'fr': "Accès complet, à vie. Un seul paiement.",
   'en': "Full access, for life. One single payment.",
   'es': "Acceso completo, de por vida. Un solo pago.",
   'sv': "Full åtkomst, för livet. En enda betalning.",
   'da': "Fuld adgang, for livet. Én enkelt betaling.",
   'nb': "Full tilgang, for livet. Én enkelt betaling.",
   'ar': "وصول كامل، مدى الحياة. دفعة واحدة فقط.",
   'sw': "Ufikiaji kamili, wa maisha. Malipo moja tu."},
 'tvLifetime': {
   'fr': "À vie", 'en': "Lifetime", 'es': "De por vida", 'sv': "Livstid",
   'da': "Livstid", 'nb': "Livstid", 'ar': "مدى الحياة", 'sw': "Maisha"},
 'tvActivationCodeLabel': {
   'fr': "Ton code d'activation", 'en': "Your activation code",
   'es': "Tu código de activación", 'sv': "Din aktiveringskod",
   'da': "Din aktiveringskode", 'nb': "Din aktiveringskode",
   'ar': "رمز التفعيل الخاص بك", 'sw': "Msimbo wako wa kuwasha"},
 'tvActivationCodeHelp': {
   'fr': "Donne ce code à ton revendeur pour activer. Il reste le même, même après une réinstallation.",
   'en': "Give this code to your reseller to activate. It stays the same, even after a reinstall.",
   'es': "Dale este código a tu vendedor para activar. No cambia, ni siquiera tras reinstalar.",
   'sv': "Ge den här koden till din återförsäljare för att aktivera. Den är densamma även efter en ominstallation.",
   'da': "Giv denne kode til din forhandler for at aktivere. Den forbliver den samme, også efter en geninstallation.",
   'nb': "Gi denne koden til forhandleren din for å aktivere. Den forblir den samme, også etter ny installasjon.",
   'ar': "أعطِ هذا الرمز لبائعك للتفعيل. يبقى كما هو حتى بعد إعادة التثبيت.",
   'sw': "Mpe muuzaji wako msimbo huu ili kuwasha. Hubaki vivyo hivyo hata baada ya kusakinisha upya."},
 'tvPaidCheck': {
   'fr': "J'ai payé — Vérifier", 'en': "I've paid — Verify",
   'es': "He pagado — Verificar", 'sv': "Jag har betalat — Verifiera",
   'da': "Jeg har betalt — Bekræft", 'nb': "Jeg har betalt — Bekreft",
   'ar': "لقد دفعت — تحقّق", 'sw': "Nimelipa — Thibitisha"},
 'tvChecking': {
   'fr': "Vérification…", 'en': "Checking…", 'es': "Comprobando…",
   'sv': "Kontrollerar…", 'da': "Kontrollerer…", 'nb': "Sjekker…",
   'ar': "جارٍ التحقق…", 'sw': "Inakagua…"},
 'tvAddOwnList': {
   'fr': "J'ajoute ma propre liste (Xtream)", 'en': "Add my own list (Xtream)",
   'es': "Añado mi propia lista (Xtream)", 'sv': "Lägg till min egen lista (Xtream)",
   'da': "Tilføj min egen liste (Xtream)", 'nb': "Legg til min egen liste (Xtream)",
   'ar': "أضيف قائمتي الخاصة (Xtream)", 'sw': "Ongeza orodha yangu (Xtream)"},
 'tvActivationFooter': {
   'fr': "Paiement vérifié · Activation instantanée",
   'en': "Payment verified · Instant activation",
   'es': "Pago verificado · Activación instantánea",
   'sv': "Betalning verifierad · Direkt aktivering",
   'da': "Betaling bekræftet · Øjeblikkelig aktivering",
   'nb': "Betaling bekreftet · Umiddelbar aktivering",
   'ar': "تم التحقق من الدفع · تفعيل فوري",
   'sw': "Malipo yamethibitishwa · Kuwasha papo hapo"},
 'tvScanToActivate': {
   'fr': "Scanne-moi pour activer", 'en': "Scan me to activate",
   'es': "Escanéame para activar", 'sv': "Skanna mig för att aktivera",
   'da': "Scan mig for at aktivere", 'nb': "Skann meg for å aktivere",
   'ar': "امسحني للتفعيل", 'sw': "Niskani ili kuwasha"},
 'tvScanHelp': {
   'fr': "Ouvre l'appareil photo de ton téléphone et vise ce code. Ça ouvre WhatsApp avec ton code déjà prêt.",
   'en': "Open your phone camera and point it at this code. It opens WhatsApp with your code ready.",
   'es': "Abre la cámara de tu teléfono y apunta a este código. Abre WhatsApp con tu código listo.",
   'sv': "Öppna telefonens kamera och rikta den mot koden. WhatsApp öppnas med din kod klar.",
   'da': "Åbn telefonens kamera, og ret den mod koden. WhatsApp åbner med din kode klar.",
   'nb': "Åpne kameraet på telefonen og rett det mot koden. WhatsApp åpnes med koden din klar.",
   'ar': "افتح كاميرا هاتفك ووجّهها نحو هذا الرمز. سيفتح واتساب ومعه رمزك جاهز.",
   'sw': "Fungua kamera ya simu yako na uielekeze kwenye msimbo huu. Itafungua WhatsApp na msimbo wako tayari."},
 'tvNavLive': {
   'fr': "Direct", 'en': "Live", 'es': "En directo", 'sv': "Direkt",
   'da': "Direkte", 'nb': "Direkte", 'ar': "مباشر", 'sw': "Moja kwa moja"},
 'tvNavFilms': {
   'fr': "Films", 'en': "Movies", 'es': "Películas", 'sv': "Filmer",
   'da': "Film", 'nb': "Filmer", 'ar': "أفلام", 'sw': "Filamu"},
 'tvNavSeries': {
   'fr': "Séries", 'en': "Series", 'es': "Series", 'sv': "Serier",
   'da': "Serier", 'nb': "Serier", 'ar': "مسلسلات", 'sw': "Mfululizo"},
 'tvNavGuide': {
   'fr': "Guide", 'en': "Guide", 'es': "Guía", 'sv': "Guide",
   'da': "Guide", 'nb': "Guide", 'ar': "الدليل", 'sw': "Mwongozo"},
 'tvNavSearch': {
   'fr': "Recherche", 'en': "Search", 'es': "Buscar", 'sv': "Sök",
   'da': "Søg", 'nb': "Søk", 'ar': "بحث", 'sw': "Tafuta"},
 'tvNavSettings': {
   'fr': "Réglages", 'en': "Settings", 'es': "Ajustes", 'sv': "Inställningar",
   'da': "Indstillinger", 'nb': "Innstillinger", 'ar': "الإعدادات", 'sw': "Mipangilio"},
 'tvComingSoon': {
   'fr': "Bientôt disponible. Cette section arrive très vite.",
   'en': "Coming soon. This section is on its way.",
   'es': "Próximamente. Esta sección llega muy pronto.",
   'sv': "Kommer snart. Den här delen är på väg.",
   'da': "Kommer snart. Denne sektion er på vej.",
   'nb': "Kommer snart. Denne delen er på vei.",
   'ar': "قريبًا. هذا القسم في الطريق.",
   'sw': "Inakuja hivi karibuni. Sehemu hii inakuja."},
 'tvHello': {
   'fr': "Bonjour", 'en': "Hello", 'es': "Hola", 'sv': "Hej",
   'da': "Hej", 'nb': "Hei", 'ar': "مرحبًا", 'sw': "Habari"},
 'tvNoChannels': {
   'fr': "Aucune chaîne pour l'instant", 'en': "No channels yet",
   'es': "Aún no hay canales", 'sv': "Inga kanaler ännu",
   'da': "Ingen kanaler endnu", 'nb': "Ingen kanaler ennå",
   'ar': "لا توجد قنوات بعد", 'sw': "Hakuna vituo bado"},
 'tvNoChannelsHelp': {
   'fr': "Active cet appareil dans ton panel, puis pousse-lui une source. Les chaînes apparaîtront ici automatiquement.",
   'en': "Activate this device in your panel, then push it a source. Channels will appear here automatically.",
   'es': "Activa este dispositivo en tu panel y envíale una fuente. Los canales aparecerán aquí automáticamente.",
   'sv': "Aktivera den här enheten i din panel och skicka en källa. Kanalerna visas här automatiskt.",
   'da': "Aktivér denne enhed i dit panel, og send en kilde. Kanalerne vises her automatisk.",
   'nb': "Aktiver denne enheten i panelet ditt, og send en kilde. Kanalene vises her automatisk.",
   'ar': "فعّل هذا الجهاز في لوحتك ثم ادفع له مصدرًا. ستظهر القنوات هنا تلقائيًا.",
   'sw': "Washa kifaa hiki kwenye paneli yako, kisha mtumie chanzo. Vituo vitaonekana hapa kiotomatiki."},
 'tvContinueWatching': {
   'fr': "CONTINUER À REGARDER", 'en': "CONTINUE WATCHING",
   'es': "SEGUIR VIENDO", 'sv': "FORTSÄTT TITTA", 'da': "FORTSÆT MED AT SE",
   'nb': "FORTSETT Å SE", 'ar': "متابعة المشاهدة", 'sw': "ENDELEA KUTAZAMA"},
 'tvNoChannelInCategory': {
   'fr': "Aucune chaîne dans cette catégorie.", 'en': "No channels in this category.",
   'es': "No hay canales en esta categoría.", 'sv': "Inga kanaler i den här kategorin.",
   'da': "Ingen kanaler i denne kategori.", 'nb': "Ingen kanaler i denne kategorien.",
   'ar': "لا توجد قنوات في هذه الفئة.", 'sw': "Hakuna vituo katika kundi hili."},
 'tvOthers': {
   'fr': "Autres", 'en': "Others", 'es': "Otros", 'sv': "Övriga",
   'da': "Andre", 'nb': "Andre", 'ar': "أخرى", 'sw': "Nyingine"},
 'tvSearchHint': {
   'fr': "Tape pour rechercher…", 'en': "Type to search…",
   'es': "Escribe para buscar…", 'sv': "Skriv för att söka…",
   'da': "Skriv for at søge…", 'nb': "Skriv for å søke…",
   'ar': "اكتب للبحث…", 'sw': "Andika ili kutafuta…"},
 'tvNoResult': {
   'fr': "Aucun résultat.", 'en': "No results.", 'es': "Sin resultados.",
   'sv': "Inga resultat.", 'da': "Ingen resultater.", 'nb': "Ingen resultater.",
   'ar': "لا نتائج.", 'sw': "Hakuna matokeo."},
 'tvDeviceAddress': {
   'fr': "Adresse de cet appareil (MAC)", 'en': "This device's address (MAC)",
   'es': "Dirección de este dispositivo (MAC)", 'sv': "Den här enhetens adress (MAC)",
   'da': "Denne enheds adresse (MAC)", 'nb': "Denne enhetens adresse (MAC)",
   'ar': "عنوان هذا الجهاز (MAC)", 'sw': "Anwani ya kifaa hiki (MAC)"},
 'tvDeviceAddressHelp': {
   'fr': "Donne cette adresse à ton revendeur pour activer The Few TV.",
   'en': "Give this address to your reseller to activate The Few TV.",
   'es': "Dale esta dirección a tu vendedor para activar The Few TV.",
   'sv': "Ge den här adressen till din återförsäljare för att aktivera The Few TV.",
   'da': "Giv denne adresse til din forhandler for at aktivere The Few TV.",
   'nb': "Gi denne adressen til forhandleren din for å aktivere The Few TV.",
   'ar': "أعطِ هذا العنوان لبائعك لتفعيل The Few TV.",
   'sw': "Mpe muuzaji wako anwani hii ili kuwasha The Few TV."},
 'tvStatus': {
   'fr': "Statut", 'en': "Status", 'es': "Estado", 'sv': "Status",
   'da': "Status", 'nb': "Status", 'ar': "الحالة", 'sw': "Hali"},
 'tvStatusPaid': {
   'fr': "Abonnement actif", 'en': "Subscription active",
   'es': "Suscripción activa", 'sv': "Abonnemang aktivt",
   'da': "Abonnement aktivt", 'nb': "Abonnement aktivt",
   'ar': "الاشتراك نشط", 'sw': "Usajili upo hai"},
 'tvStatusTrial': {
   'fr': "Essai — {days} jour(s) restants", 'en': "Trial — {days} day(s) left",
   'es': "Prueba — {days} día(s) restantes", 'sv': "Provperiod — {days} dag(ar) kvar",
   'da': "Prøveperiode — {days} dag(e) tilbage", 'nb': "Prøveperiode — {days} dag(er) igjen",
   'ar': "تجربة — {days} يوم متبقٍ", 'sw': "Jaribio — siku {days} zilizobaki"},
 'tvStatusTrialExpired': {
   'fr': "Essai terminé — à activer", 'en': "Trial ended — activate",
   'es': "Prueba finalizada — activa", 'sv': "Provperiod slut — aktivera",
   'da': "Prøveperiode slut — aktivér", 'nb': "Prøveperiode slutt — aktiver",
   'ar': "انتهت التجربة — فعّل", 'sw': "Jaribio limeisha — washa"},
 'tvStatusFrozen': {
   'fr': "Compte gelé", 'en': "Account frozen", 'es': "Cuenta congelada",
   'sv': "Konto fryst", 'da': "Konto frosset", 'nb': "Konto fryst",
   'ar': "الحساب مجمَّد", 'sw': "Akaunti imegandishwa"},
 'tvStatusBanned': {
   'fr': "Compte banni", 'en': "Account banned", 'es': "Cuenta bloqueada",
   'sv': "Konto bannlyst", 'da': "Konto bortvist", 'nb': "Konto utestengt",
   'ar': "الحساب محظور", 'sw': "Akaunti imepigwa marufuku"},
 'tvStatusUnknown': {
   'fr': "Non activé", 'en': "Not activated", 'es': "No activado",
   'sv': "Inte aktiverad", 'da': "Ikke aktiveret", 'nb': "Ikke aktivert",
   'ar': "غير مُفعّل", 'sw': "Haijawashwa"},
 'tvRefreshStatus': {
   'fr': "Rafraîchir le statut", 'en': "Refresh status",
   'es': "Actualizar estado", 'sv': "Uppdatera status",
   'da': "Opdater status", 'nb': "Oppdater status",
   'ar': "تحديث الحالة", 'sw': "Onyesha upya hali"},
 'tvLiveBadge': {
   'fr': "DIRECT", 'en': "LIVE", 'es': "EN VIVO", 'sv': "DIREKT",
   'da': "DIREKTE", 'nb': "DIREKTE", 'ar': "مباشر", 'sw': "MOJA KWA MOJA"},
 'tvZapHint': {
   'fr': "Haut/Bas pour zapper", 'en': "Up/Down to change channel",
   'es': "Arriba/Abajo para cambiar", 'sv': "Upp/Ner för att byta kanal",
   'da': "Op/Ned for at skifte kanal", 'nb': "Opp/Ned for å bytte kanal",
   'ar': "أعلى/أسفل لتغيير القناة", 'sw': "Juu/Chini kubadilisha kituo"},
 'tvAddListTitle': {
   'fr': "Ajouter ma liste", 'en': "Add my list", 'es': "Añadir mi lista",
   'sv': "Lägg till min lista", 'da': "Tilføj min liste",
   'nb': "Legg til min liste", 'ar': "إضافة قائمتي", 'sw': "Ongeza orodha yangu"},
 'tvAddListSubtitle': {
   'fr': "Code Xtream — apporte ta propre playlist.",
   'en': "Xtream code — bring your own playlist.",
   'es': "Código Xtream — trae tu propia lista.",
   'sv': "Xtream-kod — ta med din egen spellista.",
   'da': "Xtream-kode — medbring din egen playliste.",
   'nb': "Xtream-kode — ta med din egen spilleliste.",
   'ar': "رمز Xtream — أحضر قائمتك الخاصة.",
   'sw': "Msimbo wa Xtream — leta orodha yako mwenyewe."},
 'tvFieldServer': {
   'fr': "Serveur", 'en': "Server", 'es': "Servidor", 'sv': "Server",
   'da': "Server", 'nb': "Server", 'ar': "الخادم", 'sw': "Seva"},
 'tvFieldUser': {
   'fr': "Identifiant", 'en': "Username", 'es': "Usuario", 'sv': "Användarnamn",
   'da': "Brugernavn", 'nb': "Brukernavn", 'ar': "اسم المستخدم", 'sw': "Jina la mtumiaji"},
 'tvFieldPass': {
   'fr': "Mot de passe", 'en': "Password", 'es': "Contraseña", 'sv': "Lösenord",
   'da': "Adgangskode", 'nb': "Passord", 'ar': "كلمة المرور", 'sw': "Nenosiri"},
 'tvAddListError': {
   'fr': "Remplis le serveur, l'identifiant et le mot de passe.",
   'en': "Fill in the server, username and password.",
   'es': "Rellena el servidor, el usuario y la contraseña.",
   'sv': "Fyll i server, användarnamn och lösenord.",
   'da': "Udfyld server, brugernavn og adgangskode.",
   'nb': "Fyll inn server, brukernavn og passord.",
   'ar': "املأ الخادم واسم المستخدم وكلمة المرور.",
   'sw': "Jaza seva, jina la mtumiaji na nenosiri."},
 'tvConnectError': {
   'fr': "Connexion impossible. Vérifie les infos.",
   'en': "Can't connect. Check your details.",
   'es': "No se puede conectar. Revisa los datos.",
   'sv': "Kan inte ansluta. Kontrollera uppgifterna.",
   'da': "Kan ikke oprette forbindelse. Tjek oplysningerne.",
   'nb': "Får ikke kontakt. Sjekk opplysningene.",
   'ar': "تعذّر الاتصال. تحقّق من البيانات.",
   'sw': "Imeshindwa kuunganisha. Angalia taarifa."},
 'tvConnecting': {
   'fr': "Connexion…", 'en': "Connecting…", 'es': "Conectando…",
   'sv': "Ansluter…", 'da': "Opretter forbindelse…", 'nb': "Kobler til…",
   'ar': "جارٍ الاتصال…", 'sw': "Inaunganisha…"},
 'tvAddListValidate': {
   'fr': "Valider et charger ma liste", 'en': "Confirm and load my list",
   'es': "Confirmar y cargar mi lista", 'sv': "Bekräfta och ladda min lista",
   'da': "Bekræft og indlæs min liste", 'nb': "Bekreft og last inn listen min",
   'ar': "تأكيد وتحميل قائمتي", 'sw': "Thibitisha na upakie orodha yangu"},
}

# Cles avec placeholder (metadata @ ajoutee uniquement au template fr).
PLACEHOLDERS = {
  'tvStatusTrial': {'days': {'type': 'int'}},
}

added_report = {}
for lang in LANGS:
    path = os.path.join(ARB_DIR, f'app_{lang}.arb')
    with open(path, encoding='utf-8') as f:
        data = json.load(f, object_pairs_hook=collections.OrderedDict)
    added = 0
    for key, vals in T.items():
        if key in data:
            continue
        data[key] = vals[lang]
        added += 1
        # Metadata @ pour les placeholders : seulement dans le template fr.
        if lang == 'fr' and key in PLACEHOLDERS:
            data['@' + key] = {'placeholders': PLACEHOLDERS[key]}
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')
    added_report[lang] = added

print('Cles ajoutees par langue :', dict(added_report))
print('Total cles TV definies :', len(T))
