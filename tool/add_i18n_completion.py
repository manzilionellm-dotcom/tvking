#!/usr/bin/env python3
# =========================================================
#  add_i18n_completion.py — Campagne « zéro texte en dur »
#  (juillet 2026). Injecte dans les 8 app_<code>.arb toutes les
#  clés de la migration des écrans TV / partagés / couche data.
#  Même pattern que add_tv_l10n.py. Idempotent : n'écrit que les
#  clés manquantes. Vérifié par test/core/i18n_no_hardcoded_french_test.dart.
# =========================================================
import json, os, collections

ARB_DIR = os.path.join(os.path.dirname(__file__), '..', 'lib', 'l10n')
LANGS = ['fr', 'en', 'es', 'sv', 'da', 'nb', 'ar', 'sw']

T = {
 "tvSourcesTitle": {
  "fr": "Mes sources",
  "en": "My sources",
  "es": "Mis fuentes",
  "sv": "Mina källor",
  "da": "Mine kilder",
  "nb": "Mine kilder",
  "ar": "مصادري",
  "sw": "Vyanzo vyangu"
 },
 "tvSourcesAddXtream": {
  "fr": "Ajouter Xtream",
  "en": "Add Xtream",
  "es": "Añadir Xtream",
  "sv": "Lägg till Xtream",
  "da": "Tilføj Xtream",
  "nb": "Legg til Xtream",
  "ar": "إضافة Xtream",
  "sw": "Ongeza Xtream"
 },
 "tvSourcesAddM3u": {
  "fr": "Ajouter M3U",
  "en": "Add M3U",
  "es": "Añadir M3U",
  "sv": "Lägg till M3U",
  "da": "Tilføj M3U",
  "nb": "Legg til M3U",
  "ar": "إضافة M3U",
  "sw": "Ongeza M3U"
 },
 "tvSourcesEmpty": {
  "fr": "Aucune source pour le moment.\nAjoute ta liste Xtream ou M3U ci-dessus.",
  "en": "No sources yet.\nAdd your Xtream or M3U list above.",
  "es": "Aún no hay fuentes.\nAñade tu lista Xtream o M3U arriba.",
  "sv": "Inga källor ännu.\nLägg till din Xtream- eller M3U-lista ovan.",
  "da": "Ingen kilder endnu.\nTilføj din Xtream- eller M3U-liste ovenfor.",
  "nb": "Ingen kilder ennå.\nLegg til Xtream- eller M3U-listen din ovenfor.",
  "ar": "لا توجد مصادر بعد.\nأضِف قائمة Xtream أو M3U أعلاه.",
  "sw": "Hakuna vyanzo bado.\nOngeza orodha yako ya Xtream au M3U hapo juu."
 },
 "tvSourcesDeleteTitle": {
  "fr": "Supprimer ?",
  "en": "Delete?",
  "es": "¿Eliminar?",
  "sv": "Ta bort?",
  "da": "Slet?",
  "nb": "Slette?",
  "ar": "حذف؟",
  "sw": "Ufute?"
 },
 "tvSourcesDeleteConfirm": {
  "fr": "Supprimer la source « {name} » ?",
  "en": "Delete the source “{name}”?",
  "es": "¿Eliminar la fuente «{name}»?",
  "sv": "Ta bort källan ”{name}”?",
  "da": "Slet kilden ”{name}”?",
  "nb": "Slette kilden «{name}»?",
  "ar": "حذف المصدر «{name}»؟",
  "sw": "Ufute chanzo “{name}”?"
 },
 "tvSourcesActiveLabel": {
  "fr": "active",
  "en": "active",
  "es": "activa",
  "sv": "aktiv",
  "da": "aktiv",
  "nb": "aktiv",
  "ar": "نشط",
  "sw": "hai"
 },
 "tvSourcesActivate": {
  "fr": "Activer",
  "en": "Activate",
  "es": "Activar",
  "sv": "Aktivera",
  "da": "Aktivér",
  "nb": "Aktiver",
  "ar": "تفعيل",
  "sw": "Washa"
 },
 "tvAddM3uTitle": {
  "fr": "Ajouter une liste M3U",
  "en": "Add an M3U list",
  "es": "Añadir una lista M3U",
  "sv": "Lägg till en M3U-lista",
  "da": "Tilføj en M3U-liste",
  "nb": "Legg til en M3U-liste",
  "ar": "إضافة قائمة M3U",
  "sw": "Ongeza orodha ya M3U"
 },
 "tvAddM3uSubtitle": {
  "fr": "Colle l'URL de ton fichier .m3u (et l'EPG si tu en as une).",
  "en": "Paste the URL of your .m3u file (and the EPG if you have one).",
  "es": "Pega la URL de tu archivo .m3u (y la EPG si tienes una).",
  "sv": "Klistra in URL:en till din .m3u-fil (och EPG om du har en).",
  "da": "Indsæt URL'en til din .m3u-fil (og EPG hvis du har en).",
  "nb": "Lim inn URL-en til .m3u-filen din (og EPG hvis du har en).",
  "ar": "الصق رابط ملف ‎.m3u الخاص بك (وEPG إن وُجد).",
  "sw": "Bandika URL ya faili lako la .m3u (na EPG ukiwa nayo)."
 },
 "tvAddM3uNameLabel": {
  "fr": "Nom (optionnel)",
  "en": "Name (optional)",
  "es": "Nombre (opcional)",
  "sv": "Namn (valfritt)",
  "da": "Navn (valgfrit)",
  "nb": "Navn (valgfritt)",
  "ar": "الاسم (اختياري)",
  "sw": "Jina (hiari)"
 },
 "tvAddM3uNameHint": {
  "fr": "Ma liste",
  "en": "My list",
  "es": "Mi lista",
  "sv": "Min lista",
  "da": "Min liste",
  "nb": "Min liste",
  "ar": "قائمتي",
  "sw": "Orodha yangu"
 },
 "tvAddM3uUrlLabel": {
  "fr": "URL M3U",
  "en": "M3U URL",
  "es": "URL M3U",
  "sv": "M3U-URL",
  "da": "M3U-URL",
  "nb": "M3U-URL",
  "ar": "رابط M3U",
  "sw": "URL ya M3U"
 },
 "tvAddM3uEpgLabel": {
  "fr": "URL EPG (optionnel)",
  "en": "EPG URL (optional)",
  "es": "URL EPG (opcional)",
  "sv": "EPG-URL (valfritt)",
  "da": "EPG-URL (valgfrit)",
  "nb": "EPG-URL (valgfritt)",
  "ar": "رابط EPG (اختياري)",
  "sw": "URL ya EPG (hiari)"
 },
 "tvAddM3uInvalidUrl": {
  "fr": "Entre une URL M3U valide.",
  "en": "Enter a valid M3U URL.",
  "es": "Introduce una URL M3U válida.",
  "sv": "Ange en giltig M3U-URL.",
  "da": "Indtast en gyldig M3U-URL.",
  "nb": "Skriv inn en gyldig M3U-URL.",
  "ar": "أدخل رابط M3U صالحًا.",
  "sw": "Weka URL sahihi ya M3U."
 },
 "tvAddM3uDefaultName": {
  "fr": "Ma liste M3U",
  "en": "My M3U list",
  "es": "Mi lista M3U",
  "sv": "Min M3U-lista",
  "da": "Min M3U-liste",
  "nb": "Min M3U-liste",
  "ar": "قائمة M3U الخاصة بي",
  "sw": "Orodha yangu ya M3U"
 },
 "tvAddM3uLoadFailed": {
  "fr": "Échec : liste injoignable ou vide.",
  "en": "Failed: list unreachable or empty.",
  "es": "Error: lista inaccesible o vacía.",
  "sv": "Misslyckades: listan onåbar eller tom.",
  "da": "Mislykkedes: listen er utilgængelig eller tom.",
  "nb": "Mislyktes: listen er utilgjengelig eller tom.",
  "ar": "فشل: القائمة غير متاحة أو فارغة.",
  "sw": "Imeshindikana: orodha haipatikani au ni tupu."
 },
 "tvAddM3uAdding": {
  "fr": "Ajout…",
  "en": "Adding…",
  "es": "Añadiendo…",
  "sv": "Lägger till…",
  "da": "Tilføjer…",
  "nb": "Legger til…",
  "ar": "جارٍ الإضافة…",
  "sw": "Inaongeza…"
 },
 "tvAddM3uSubmit": {
  "fr": "Ajouter la liste",
  "en": "Add the list",
  "es": "Añadir la lista",
  "sv": "Lägg till listan",
  "da": "Tilføj listen",
  "nb": "Legg til listen",
  "ar": "إضافة القائمة",
  "sw": "Ongeza orodha"
 },
 "tvAboutTitle": {
  "fr": "À propos",
  "en": "About",
  "es": "Acerca de",
  "sv": "Om",
  "da": "Om",
  "nb": "Om",
  "ar": "حول",
  "sw": "Kuhusu"
 },
 "tvAboutVersion": {
  "fr": "Version",
  "en": "Version",
  "es": "Versión",
  "sv": "Version",
  "da": "Version",
  "nb": "Versjon",
  "ar": "الإصدار",
  "sw": "Toleo"
 },
 "tvAboutSystem": {
  "fr": "Système",
  "en": "System",
  "es": "Sistema",
  "sv": "System",
  "da": "System",
  "nb": "System",
  "ar": "النظام",
  "sw": "Mfumo"
 },
 "tvAboutRam": {
  "fr": "Mémoire (RAM)",
  "en": "Memory (RAM)",
  "es": "Memoria (RAM)",
  "sv": "Minne (RAM)",
  "da": "Hukommelse (RAM)",
  "nb": "Minne (RAM)",
  "ar": "الذاكرة (RAM)",
  "sw": "Kumbukumbu (RAM)"
 },
 "tvAboutChannelCap": {
  "fr": "Capacité chaînes",
  "en": "Channel capacity",
  "es": "Capacidad de canales",
  "sv": "Kanalkapacitet",
  "da": "Kanalkapacitet",
  "nb": "Kanalkapasitet",
  "ar": "سعة القنوات",
  "sw": "Uwezo wa vituo"
 },
 "tvAboutRamUnknown": {
  "fr": "inconnue",
  "en": "unknown",
  "es": "desconocida",
  "sv": "okänt",
  "da": "ukendt",
  "nb": "ukjent",
  "ar": "غير معروفة",
  "sw": "haijulikani"
 },
 "tvAboutRamLow": {
  "fr": "faible",
  "en": "low",
  "es": "baja",
  "sv": "lågt",
  "da": "lav",
  "nb": "lavt",
  "ar": "منخفضة",
  "sw": "ndogo"
 },
 "tvAboutRamGb": {
  "fr": "{gb} Go",
  "en": "{gb} GB",
  "es": "{gb} GB",
  "sv": "{gb} GB",
  "da": "{gb} GB",
  "nb": "{gb} GB",
  "ar": "{gb} ج.ب",
  "sw": "GB {gb}"
 },
 "tvAboutClearCache": {
  "fr": "Vider le cache (libère de la mémoire)",
  "en": "Clear cache (frees up memory)",
  "es": "Vaciar caché (libera memoria)",
  "sv": "Töm cache (frigör minne)",
  "da": "Ryd cache (frigør hukommelse)",
  "nb": "Tøm hurtigbuffer (frigjør minne)",
  "ar": "مسح الذاكرة المؤقتة (يحرّر الذاكرة)",
  "sw": "Futa akiba (huachilia kumbukumbu)"
 },
 "tvAboutCacheCleared": {
  "fr": "Cache image vidé ✓  ({mb} Mo libérés)",
  "en": "Image cache cleared ✓  ({mb} MB freed)",
  "es": "Caché de imágenes vaciada ✓  ({mb} MB liberados)",
  "sv": "Bildcache tömd ✓  ({mb} MB frigjorda)",
  "da": "Billedcache ryddet ✓  ({mb} MB frigivet)",
  "nb": "Bildebuffer tømt ✓  ({mb} MB frigjort)",
  "ar": "تم مسح ذاكرة الصور ✓  (تحرّر {mb} م.ب)",
  "sw": "Akiba ya picha imefutwa ✓  (MB {mb} zimeachiliwa)"
 },
 "castStageValidating": {
  "fr": "Vérification du flux…",
  "en": "Checking the stream…",
  "es": "Verificando el flujo…",
  "sv": "Kontrollerar flödet…",
  "da": "Kontrollerer streamen…",
  "nb": "Sjekker strømmen…",
  "ar": "جارٍ فحص البث…",
  "sw": "Inakagua mtiririko…"
 },
 "castStageDetecting": {
  "fr": "Détection de la TV…",
  "en": "Detecting the TV…",
  "es": "Detectando el televisor…",
  "sv": "Söker efter TV:n…",
  "da": "Finder TV'et…",
  "nb": "Finner TV-en…",
  "ar": "جارٍ اكتشاف التلفاز…",
  "sw": "Inatafuta TV…"
 },
 "castStageRelayStarting": {
  "fr": "Préparation du relais…",
  "en": "Preparing the relay…",
  "es": "Preparando el relé…",
  "sv": "Förbereder reläet…",
  "da": "Forbereder relæet…",
  "nb": "Forbereder releet…",
  "ar": "جارٍ تجهيز المرحّل…",
  "sw": "Inaandaa upitishaji…"
 },
 "castStageConnecting": {
  "fr": "Connexion à la TV…",
  "en": "Connecting to the TV…",
  "es": "Conectando con el televisor…",
  "sv": "Ansluter till TV:n…",
  "da": "Opretter forbindelse til TV'et…",
  "nb": "Kobler til TV-en…",
  "ar": "جارٍ الاتصال بالتلفاز…",
  "sw": "Inaunganisha na TV…"
 },
 "castStageConnectingAttempt": {
  "fr": "Connexion à la TV ({attempt}/{total})…",
  "en": "Connecting to the TV ({attempt}/{total})…",
  "es": "Conectando con el televisor ({attempt}/{total})…",
  "sv": "Ansluter till TV:n ({attempt}/{total})…",
  "da": "Opretter forbindelse til TV'et ({attempt}/{total})…",
  "nb": "Kobler til TV-en ({attempt}/{total})…",
  "ar": "جارٍ الاتصال بالتلفاز ({attempt}/{total})…",
  "sw": "Inaunganisha na TV ({attempt}/{total})…"
 },
 "castStageRetrying": {
  "fr": "Nouvel essai en mode compatible ({attempt}/{total})…",
  "en": "Retrying in compatibility mode ({attempt}/{total})…",
  "es": "Reintentando en modo compatible ({attempt}/{total})…",
  "sv": "Försöker igen i kompatibelt läge ({attempt}/{total})…",
  "da": "Prøver igen i kompatibel tilstand ({attempt}/{total})…",
  "nb": "Prøver igjen i kompatibel modus ({attempt}/{total})…",
  "ar": "محاولة جديدة في الوضع المتوافق ({attempt}/{total})…",
  "sw": "Inajaribu tena katika hali oanifu ({attempt}/{total})…"
 },
 "castStageWebFallback": {
  "fr": "Passage en mode universel (QR code)…",
  "en": "Switching to universal mode (QR code)…",
  "es": "Cambiando al modo universal (código QR)…",
  "sv": "Byter till universellt läge (QR-kod)…",
  "da": "Skifter til universel tilstand (QR-kode)…",
  "nb": "Bytter til universell modus (QR-kode)…",
  "ar": "التبديل إلى الوضع الشامل (رمز QR)…",
  "sw": "Inahamia hali ya wote (msimbo wa QR)…"
 },
 "castStageLive": {
  "fr": "Diffusion en cours sur la TV",
  "en": "Now playing on the TV",
  "es": "Reproduciendo en el televisor",
  "sv": "Spelas nu på TV:n",
  "da": "Afspilles nu på TV'et",
  "nb": "Spilles nå på TV-en",
  "ar": "يُعرض الآن على التلفاز",
  "sw": "Inacheza sasa kwenye TV"
 },
 "castStagePaused": {
  "fr": "Pause",
  "en": "Paused",
  "es": "En pausa",
  "sv": "Pausad",
  "da": "På pause",
  "nb": "Pauset",
  "ar": "إيقاف مؤقت",
  "sw": "Imesimamishwa"
 },
 "commonClose": {
  "fr": "Fermer",
  "en": "Close",
  "es": "Cerrar",
  "sv": "Stäng",
  "da": "Luk",
  "nb": "Lukk",
  "ar": "إغلاق",
  "sw": "Funga"
 },
 "moviesOfflineCategory": {
  "fr": "Téléchargé",
  "en": "Downloaded",
  "es": "Descargado",
  "sv": "Nedladdad",
  "da": "Downloadet",
  "nb": "Nedlastet",
  "ar": "تم التنزيل",
  "sw": "Imepakuliwa"
 },
 "guideReminderSet": {
  "fr": "🔔 Rappel programmé · {title} ({start})",
  "en": "🔔 Reminder set · {title} ({start})",
  "es": "🔔 Recordatorio programado · {title} ({start})",
  "sv": "🔔 Påminnelse inställd · {title} ({start})",
  "da": "🔔 Påmindelse sat · {title} ({start})",
  "nb": "🔔 Påminnelse satt · {title} ({start})",
  "ar": "🔔 تم ضبط التذكير · {title} ({start})",
  "sw": "🔔 Kikumbusho kimewekwa · {title} ({start})"
 },
 "guideStartsAt": {
  "fr": "{title} · démarre à {start}",
  "en": "{title} · starts at {start}",
  "es": "{title} · empieza a las {start}",
  "sv": "{title} · börjar kl. {start}",
  "da": "{title} · starter kl. {start}",
  "nb": "{title} · starter kl. {start}",
  "ar": "{title} · يبدأ في {start}",
  "sw": "{title} · inaanza saa {start}"
 },
 "settingsLockTitle": {
  "fr": "Verrouiller à l'ouverture",
  "en": "Lock on launch",
  "es": "Bloquear al abrir",
  "sv": "Lås vid start",
  "da": "Lås ved åbning",
  "nb": "Lås ved oppstart",
  "ar": "قفل عند الفتح",
  "sw": "Funga wakati wa kufungua"
 },
 "settingsLockSubtitle": {
  "fr": "Demande l'empreinte ou PIN au démarrage de l'app. Pas de re-verrouillage si tu reviens du multitâche.",
  "en": "Asks for fingerprint or PIN when the app starts. No re-lock when you come back from multitasking.",
  "es": "Pide la huella o el PIN al iniciar la app. No se vuelve a bloquear al volver de la multitarea.",
  "sv": "Ber om fingeravtryck eller PIN när appen startar. Ingen omlåsning när du kommer tillbaka från multitasking.",
  "da": "Beder om fingeraftryk eller PIN, når appen starter. Ingen genlåsning, når du vender tilbage fra multitasking.",
  "nb": "Ber om fingeravtrykk eller PIN når appen starter. Ingen ny låsing når du kommer tilbake fra multitasking.",
  "ar": "يطلب البصمة أو رمز PIN عند تشغيل التطبيق. لا يُعاد القفل عند العودة من تعدد المهام.",
  "sw": "Huomba alama ya kidole au PIN wakati programu inaanza. Haifungi tena ukirudi kutoka kwa kazi nyingi."
 },
 "settingsLockConfirmReason": {
  "fr": "Confirme avec ton empreinte ou PIN pour activer le verrouillage",
  "en": "Confirm with your fingerprint or PIN to enable the lock",
  "es": "Confirma con tu huella o PIN para activar el bloqueo",
  "sv": "Bekräfta med fingeravtryck eller PIN för att aktivera låset",
  "da": "Bekræft med fingeraftryk eller PIN for at aktivere låsen",
  "nb": "Bekreft med fingeravtrykk eller PIN for å aktivere låsen",
  "ar": "أكّد ببصمتك أو رمز PIN لتفعيل القفل",
  "sw": "Thibitisha kwa alama ya kidole au PIN ili kuwasha kufuli"
 },
 "settingsLockActivationFailed": {
  "fr": "Verrouillage non activé — auth échouée ou pas d'empreinte / PIN configurés sur ce téléphone.",
  "en": "Lock not enabled — auth failed or no fingerprint / PIN set up on this phone.",
  "es": "Bloqueo no activado: autenticación fallida o sin huella / PIN configurados en este teléfono.",
  "sv": "Låset aktiverades inte — autentisering misslyckades eller inget fingeravtryck/PIN inställt på telefonen.",
  "da": "Låsen blev ikke aktiveret — godkendelse mislykkedes, eller der er ikke sat fingeraftryk/PIN op på telefonen.",
  "nb": "Låsen ble ikke aktivert — autentisering mislyktes eller ingen fingeravtrykk/PIN er satt opp på telefonen.",
  "ar": "لم يُفعَّل القفل — فشلت المصادقة أو لا توجد بصمة/رمز PIN مضبوطة على هذا الهاتف.",
  "sw": "Kufuli hakikuwashwa — uthibitisho umeshindikana au hakuna alama ya kidole/PIN kwenye simu hii."
 },
 "tvSettingsLanguage": {
  "fr": "Langue de l'application",
  "en": "App language",
  "es": "Idioma de la aplicación",
  "sv": "Appens språk",
  "da": "Appens sprog",
  "nb": "Appspråk",
  "ar": "لغة التطبيق",
  "sw": "Lugha ya programu"
 },
 "tvLanguageTitle": {
  "fr": "Langue",
  "en": "Language",
  "es": "Idioma",
  "sv": "Språk",
  "da": "Sprog",
  "nb": "Språk",
  "ar": "اللغة",
  "sw": "Lugha"
 },
 "tvLanguageSubtitle": {
  "fr": "Par défaut, l'app suit la langue de la TV. Tu peux forcer une langue ici.",
  "en": "By default, the app follows the TV's language. You can force a language here.",
  "es": "Por defecto, la app sigue el idioma del televisor. Aquí puedes forzar un idioma.",
  "sv": "Som standard följer appen TV:ns språk. Här kan du tvinga ett språk.",
  "da": "Som standard følger appen TV'ets sprog. Her kan du gennemtvinge et sprog.",
  "nb": "Som standard følger appen TV-ens språk. Her kan du tvinge et språk.",
  "ar": "افتراضيًا يتبع التطبيق لغة التلفاز. يمكنك فرض لغة هنا.",
  "sw": "Kwa chaguo-msingi, programu hufuata lugha ya TV. Unaweza kulazimisha lugha hapa."
 },
 "tvLanguageSystem": {
  "fr": "Système — suit la langue de la TV",
  "en": "System — follows the TV's language",
  "es": "Sistema — sigue el idioma del televisor",
  "sv": "System — följer TV:ns språk",
  "da": "System — følger TV'ets sprog",
  "nb": "System — følger TV-ens språk",
  "ar": "النظام — يتبع لغة التلفاز",
  "sw": "Mfumo — hufuata lugha ya TV"
 },
 "adminErrSecretRefusedSetup": {
  "fr": "Secret admin refusé par le serveur. Vérifie que tu as bien collé le bon mot de passe que tu as défini avec `wrangler secret put ADMIN_SECRET`.",
  "en": "Admin secret refused by the server. Check that you pasted the exact password you set with `wrangler secret put ADMIN_SECRET`.",
  "es": "Secreto de administrador rechazado por el servidor. Comprueba que pegaste la contraseña exacta definida con `wrangler secret put ADMIN_SECRET`.",
  "sv": "Adminhemligheten avvisades av servern. Kontrollera att du klistrade in exakt det lösenord du satte med `wrangler secret put ADMIN_SECRET`.",
  "da": "Adminhemmeligheden blev afvist af serveren. Tjek, at du indsatte præcis den adgangskode, du satte med `wrangler secret put ADMIN_SECRET`.",
  "nb": "Adminhemmeligheten ble avvist av serveren. Sjekk at du limte inn nøyaktig passordet du satte med `wrangler secret put ADMIN_SECRET`.",
  "ar": "رفض الخادم سرّ المشرف. تأكد أنك لصقت كلمة المرور نفسها التي عيّنتها عبر `wrangler secret put ADMIN_SECRET`.",
  "sw": "Seva imekataa siri ya msimamizi. Hakikisha ulibandika nenosiri lile lile uliloweka kwa `wrangler secret put ADMIN_SECRET`."
 },
 "adminErrUrlNotFound": {
  "fr": "URL du serveur introuvable. Vérifie que tu as bien collé l'URL complète de ton Worker (https://....workers.dev).",
  "en": "Server URL not found. Check that you pasted your Worker's full URL (https://....workers.dev).",
  "es": "URL del servidor no encontrada. Comprueba que pegaste la URL completa de tu Worker (https://....workers.dev).",
  "sv": "Serverns URL hittades inte. Kontrollera att du klistrade in Workerns fullständiga URL (https://....workers.dev).",
  "da": "Serverens URL blev ikke fundet. Tjek, at du indsatte din Workers fulde URL (https://....workers.dev).",
  "nb": "Fant ikke serverens URL. Sjekk at du limte inn Workerens fullstendige URL (https://....workers.dev).",
  "ar": "لم يُعثر على عنوان الخادم. تأكد أنك لصقت العنوان الكامل لـ Worker الخاص بك ‏(https://....workers.dev).",
  "sw": "URL ya seva haipatikani. Hakikisha ulibandika URL kamili ya Worker yako (https://....workers.dev)."
 },
 "adminErrHttp": {
  "fr": "Erreur serveur HTTP {code}. Réponse : {body}",
  "en": "Server error HTTP {code}. Response: {body}",
  "es": "Error del servidor HTTP {code}. Respuesta: {body}",
  "sv": "Serverfel HTTP {code}. Svar: {body}",
  "da": "Serverfejl HTTP {code}. Svar: {body}",
  "nb": "Serverfeil HTTP {code}. Svar: {body}",
  "ar": "خطأ في الخادم HTTP {code}. الرد: {body}",
  "sw": "Hitilafu ya seva HTTP {code}. Jibu: {body}"
 },
 "adminErrUnreadableResponse": {
  "fr": "Réponse serveur illisible : {error}",
  "en": "Unreadable server response: {error}",
  "es": "Respuesta del servidor ilegible: {error}",
  "sv": "Oläsbart serversvar: {error}",
  "da": "Ulæseligt serversvar: {error}",
  "nb": "Uleselig serversvar: {error}",
  "ar": "استجابة الخادم غير قابلة للقراءة: {error}",
  "sw": "Jibu la seva halisomeki: {error}"
 },
 "adminErrSecretRefused": {
  "fr": "Secret admin refusé.",
  "en": "Admin secret refused.",
  "es": "Secreto de administrador rechazado.",
  "sv": "Adminhemligheten avvisades.",
  "da": "Adminhemmeligheden blev afvist.",
  "nb": "Adminhemmeligheten ble avvist.",
  "ar": "رُفض سرّ المشرف.",
  "sw": "Siri ya msimamizi imekataliwa."
 },
 "adminErrDetail": {
  "fr": "Détail : {detail}",
  "en": "Detail: {detail}",
  "es": "Detalle: {detail}",
  "sv": "Detalj: {detail}",
  "da": "Detalje: {detail}",
  "nb": "Detalj: {detail}",
  "ar": "التفاصيل: {detail}",
  "sw": "Maelezo: {detail}"
 },
 "adminErrSaveFailed": {
  "fr": "Échec de l'enregistrement (HTTP {code}).",
  "en": "Save failed (HTTP {code}).",
  "es": "Error al guardar (HTTP {code}).",
  "sv": "Det gick inte att spara (HTTP {code}).",
  "da": "Kunne ikke gemme (HTTP {code}).",
  "nb": "Kunne ikke lagre (HTTP {code}).",
  "ar": "فشل الحفظ (HTTP {code}).",
  "sw": "Imeshindwa kuhifadhi (HTTP {code})."
 },
 "adminErrDeleteFailed": {
  "fr": "Échec de la suppression (HTTP {code}).",
  "en": "Delete failed (HTTP {code}).",
  "es": "Error al eliminar (HTTP {code}).",
  "sv": "Det gick inte att ta bort (HTTP {code}).",
  "da": "Kunne ikke slette (HTTP {code}).",
  "nb": "Kunne ikke slette (HTTP {code}).",
  "ar": "فشل الحذف (HTTP {code}).",
  "sw": "Imeshindwa kufuta (HTTP {code})."
 },
 "adminErrServerUnreachable": {
  "fr": "Impossible de joindre le serveur : {error}",
  "en": "Can't reach the server: {error}",
  "es": "No se puede contactar con el servidor: {error}",
  "sv": "Kan inte nå servern: {error}",
  "da": "Kan ikke nå serveren: {error}",
  "nb": "Får ikke kontakt med serveren: {error}",
  "ar": "تعذّر الوصول إلى الخادم: {error}",
  "sw": "Haiwezi kufikia seva: {error}"
 },
 "tvProfilesTitle": {
  "fr": "Profils",
  "en": "Profiles",
  "es": "Perfiles",
  "sv": "Profiler",
  "da": "Profiler",
  "nb": "Profiler",
  "ar": "الملفات الشخصية",
  "sw": "Wasifu"
 },
 "tvProfilesSubtitle": {
  "fr": "Chacun son univers : derniers films vus, recherches et collections sont propres à chaque profil. Les favoris restent partagés par la famille.",
  "en": "Everyone gets their own space: recently watched, searches and collections belong to each profile. Favorites stay shared by the whole family.",
  "es": "Cada uno con su universo: lo último visto, las búsquedas y las colecciones son propias de cada perfil. Los favoritos siguen compartidos por la familia.",
  "sv": "Var och en har sitt eget: senast sedda, sökningar och samlingar hör till varje profil. Favoriterna delas fortfarande av hela familjen.",
  "da": "Alle har deres eget univers: senest sete, søgninger og samlinger hører til hver profil. Favoritter deles stadig af hele familien.",
  "nb": "Alle har sitt eget univers: sist sette, søk og samlinger hører til hver profil. Favoritter deles fortsatt av hele familien.",
  "ar": "لكلٍّ عالمه الخاص: آخر ما شوهد وعمليات البحث والمجموعات خاصة بكل ملف شخصي. تبقى المفضلة مشتركة بين العائلة.",
  "sw": "Kila mtu na ulimwengu wake: vilivyotazamwa hivi karibuni, utafutaji na mikusanyo ni vya kila wasifu. Vipendwa vinabaki kushirikiwa na familia."
 },
 "tvProfilesActive": {
  "fr": "Actif",
  "en": "Active",
  "es": "Activo",
  "sv": "Aktiv",
  "da": "Aktiv",
  "nb": "Aktiv",
  "ar": "نشط",
  "sw": "Inatumika"
 },
 "tvProfilesConfirmDelete": {
  "fr": "Confirmer ?",
  "en": "Confirm?",
  "es": "¿Confirmar?",
  "sv": "Bekräfta?",
  "da": "Bekræft?",
  "nb": "Bekreft?",
  "ar": "تأكيد؟",
  "sw": "Thibitisha?"
 },
 "tvProfilesAddSection": {
  "fr": "AJOUTER UN PROFIL",
  "en": "ADD A PROFILE",
  "es": "AÑADIR UN PERFIL",
  "sv": "LÄGG TILL EN PROFIL",
  "da": "TILFØJ EN PROFIL",
  "nb": "LEGG TIL EN PROFIL",
  "ar": "إضافة ملف شخصي",
  "sw": "ONGEZA WASIFU"
 },
 "tvProfilesPresetDad": {
  "fr": "Papa",
  "en": "Dad",
  "es": "Papá",
  "sv": "Pappa",
  "da": "Far",
  "nb": "Pappa",
  "ar": "بابا",
  "sw": "Baba"
 },
 "tvProfilesPresetMom": {
  "fr": "Maman",
  "en": "Mom",
  "es": "Mamá",
  "sv": "Mamma",
  "da": "Mor",
  "nb": "Mamma",
  "ar": "ماما",
  "sw": "Mama"
 },
 "tvProfilesPresetTeen": {
  "fr": "Ado",
  "en": "Teen",
  "es": "Adolescente",
  "sv": "Tonåring",
  "da": "Teenager",
  "nb": "Tenåring",
  "ar": "مراهق",
  "sw": "Kijana"
 },
 "tvCollectionsTitle": {
  "fr": "Mes collections",
  "en": "My collections",
  "es": "Mis colecciones",
  "sv": "Mina samlingar",
  "da": "Mine samlinger",
  "nb": "Mine samlinger",
  "ar": "مجموعاتي",
  "sw": "Mikusanyo yangu"
 },
 "tvCollectionsSubtitle": {
  "fr": "Range tes chaînes favorites par thème. Une collection = une liste que tu ouvres en un clic.",
  "en": "Sort your favorite channels by theme. One collection = one list you open in a single click.",
  "es": "Ordena tus canales favoritos por tema. Una colección = una lista que abres con un clic.",
  "sv": "Sortera dina favoritkanaler efter tema. En samling = en lista du öppnar med ett klick.",
  "da": "Sortér dine favoritkanaler efter tema. En samling = en liste, du åbner med ét klik.",
  "nb": "Sorter favorittkanalene dine etter tema. En samling = en liste du åpner med ett klikk.",
  "ar": "رتّب قنواتك المفضلة حسب الموضوع. المجموعة = قائمة تفتحها بنقرة واحدة.",
  "sw": "Panga vituo unavyovipenda kwa mada. Mkusanyo mmoja = orodha unayofungua kwa mbofyo mmoja."
 },
 "tvCollectionsEmpty": {
  "fr": "Aucune collection pour l'instant — crée la première ci-dessous. 👇",
  "en": "No collections yet — create the first one below. 👇",
  "es": "Ninguna colección por ahora — crea la primera aquí abajo. 👇",
  "sv": "Inga samlingar än — skapa den första här nedanför. 👇",
  "da": "Ingen samlinger endnu — opret den første herunder. 👇",
  "nb": "Ingen samlinger ennå — opprett den første nedenfor. 👇",
  "ar": "لا توجد مجموعات بعد — أنشئ الأولى أدناه. 👇",
  "sw": "Hakuna mkusanyo bado — unda wa kwanza hapa chini. 👇"
 },
 "tvCollectionsCreateSection": {
  "fr": "CRÉER UNE COLLECTION",
  "en": "CREATE A COLLECTION",
  "es": "CREAR UNA COLECCIÓN",
  "sv": "SKAPA EN SAMLING",
  "da": "OPRET EN SAMLING",
  "nb": "OPPRETT EN SAMLING",
  "ar": "إنشاء مجموعة",
  "sw": "UNDA MKUSANYO"
 },
 "tvCollectionsConfirmDelete": {
  "fr": "Confirmer ?",
  "en": "Confirm?",
  "es": "¿Confirmar?",
  "sv": "Bekräfta?",
  "da": "Bekræft?",
  "nb": "Bekreft?",
  "ar": "تأكيد؟",
  "sw": "Thibitisha?"
 },
 "tvCollectionsInCollection": {
  "fr": "DANS LA COLLECTION ({count})",
  "en": "IN THE COLLECTION ({count})",
  "es": "EN LA COLECCIÓN ({count})",
  "sv": "I SAMLINGEN ({count})",
  "da": "I SAMLINGEN ({count})",
  "nb": "I SAMLINGEN ({count})",
  "ar": "في المجموعة ({count})",
  "sw": "KWENYE MKUSANYO ({count})"
 },
 "tvCollectionsEmptyDetail": {
  "fr": "Vide. Ajoute des chaînes depuis tes favoris ci-dessous. 👇",
  "en": "Empty. Add channels from your favorites below. 👇",
  "es": "Vacía. Añade canales desde tus favoritos aquí abajo. 👇",
  "sv": "Tom. Lägg till kanaler från dina favoriter nedan. 👇",
  "da": "Tom. Tilføj kanaler fra dine favoritter herunder. 👇",
  "nb": "Tom. Legg til kanaler fra favorittene dine nedenfor. 👇",
  "ar": "فارغة. أضف قنوات من مفضلتك أدناه. 👇",
  "sw": "Tupu. Ongeza vituo kutoka kwa vipendwa vyako hapa chini. 👇"
 },
 "tvCollectionsFavsSection": {
  "fr": "MES FAVORIS — OK pour ajouter/retirer",
  "en": "MY FAVORITES — OK to add/remove",
  "es": "MIS FAVORITOS — OK para añadir/quitar",
  "sv": "MINA FAVORITER — OK för att lägga till/ta bort",
  "da": "MINE FAVORITTER — OK for at tilføje/fjerne",
  "nb": "MINE FAVORITTER — OK for å legge til/fjerne",
  "ar": "مفضلتي — اضغط OK للإضافة أو الإزالة",
  "sw": "VIPENDWA VYANGU — OK kuongeza/kuondoa"
 },
 "tvCollectionsNoFavorites": {
  "fr": "Aucun favori pour l'instant. Mets des chaînes en favori (appui long sur OK dans le Direct), puis reviens ici.",
  "en": "No favorites yet. Mark channels as favorites (long-press OK in Live TV), then come back here.",
  "es": "Ningún favorito por ahora. Marca canales como favoritos (mantén pulsado OK en el Directo) y vuelve aquí.",
  "sv": "Inga favoriter än. Gör kanaler till favoriter (håll in OK i Direkt) och kom sedan tillbaka hit.",
  "da": "Ingen favoritter endnu. Gør kanaler til favoritter (hold OK nede i Direkte), og kom så tilbage hertil.",
  "nb": "Ingen favoritter ennå. Gjør kanaler til favoritter (hold inne OK i Direkte), og kom tilbake hit.",
  "ar": "لا توجد مفضلات بعد. أضف قنوات إلى المفضلة (اضغط مطولًا على OK في البث المباشر) ثم عد إلى هنا.",
  "sw": "Hakuna vipendwa bado. Weka vituo kwenye vipendwa (bonyeza OK kwa muda mrefu kwenye Moja kwa Moja), kisha urudi hapa."
 },
 "tvCollectionsPresetNews": {
  "fr": "Actus",
  "en": "News",
  "es": "Noticias",
  "sv": "Nyheter",
  "da": "Nyheder",
  "nb": "Nyheter",
  "ar": "أخبار",
  "sw": "Habari"
 },
 "tvCollectionsPresetCustom1": {
  "fr": "Perso 1",
  "en": "Custom 1",
  "es": "Personal 1",
  "sv": "Egen 1",
  "da": "Egen 1",
  "nb": "Egen 1",
  "ar": "خاص 1",
  "sw": "Binafsi 1"
 },
 "tvCollectionsPresetCustom2": {
  "fr": "Perso 2",
  "en": "Custom 2",
  "es": "Personal 2",
  "sv": "Egen 2",
  "da": "Egen 2",
  "nb": "Egen 2",
  "ar": "خاص 2",
  "sw": "Binafsi 2"
 },
 "tvRecPlayerNotFoundTitle": {
  "fr": "Enregistrement introuvable",
  "en": "Recording not found",
  "es": "Grabación no encontrada",
  "sv": "Inspelningen hittades inte",
  "da": "Optagelsen blev ikke fundet",
  "nb": "Fant ikke opptaket",
  "ar": "التسجيل غير موجود",
  "sw": "Rekodi haipatikani"
 },
 "tvRecPlayerNotFoundBody": {
  "fr": "Le fichier de cet enregistrement est introuvable ou vide.",
  "en": "The file for this recording is missing or empty.",
  "es": "El archivo de esta grabación no existe o está vacío.",
  "sv": "Filen för den här inspelningen saknas eller är tom.",
  "da": "Filen til denne optagelse mangler eller er tom.",
  "nb": "Filen for dette opptaket mangler eller er tom.",
  "ar": "ملف هذا التسجيل مفقود أو فارغ.",
  "sw": "Faili la rekodi hii halipo au ni tupu."
 },
 "tvRecPlayerErrorTitle": {
  "fr": "Lecture impossible",
  "en": "Can't play this file",
  "es": "No se puede reproducir",
  "sv": "Kan inte spela upp",
  "da": "Kan ikke afspille",
  "nb": "Kan ikke spille av",
  "ar": "تعذّر التشغيل",
  "sw": "Haiwezi kuchezwa"
 },
 "tvRecPlayerErrorBody": {
  "fr": "Ce fichier n'a pas pu être décodé.",
  "en": "This file could not be decoded.",
  "es": "No se pudo decodificar este archivo.",
  "sv": "Filen kunde inte avkodas.",
  "da": "Filen kunne ikke afkodes.",
  "nb": "Filen kunne ikke dekodes.",
  "ar": "تعذّر فك ترميز هذا الملف.",
  "sw": "Faili hili halikuweza kusomwa."
 },
 "tvRecPlayerEndedTitle": {
  "fr": "Lecture terminée",
  "en": "Playback finished",
  "es": "Reproducción terminada",
  "sv": "Uppspelningen är klar",
  "da": "Afspilning færdig",
  "nb": "Avspillingen er ferdig",
  "ar": "انتهى التشغيل",
  "sw": "Uchezaji umekamilika"
 },
 "tvRecPlayerEndedBody": {
  "fr": "Appuie sur Retour pour revenir à tes enregistrements.",
  "en": "Press Back to return to your recordings.",
  "es": "Pulsa Atrás para volver a tus grabaciones.",
  "sv": "Tryck på Tillbaka för att gå till dina inspelningar.",
  "da": "Tryk på Tilbage for at vende tilbage til dine optagelser.",
  "nb": "Trykk på Tilbake for å gå tilbake til opptakene dine.",
  "ar": "اضغط على زر الرجوع للعودة إلى تسجيلاتك.",
  "sw": "Bonyeza Rudi kurejea kwenye rekodi zako."
 },
 "tvSleepTitle": {
  "fr": "Minuterie de veille",
  "en": "Sleep timer",
  "es": "Temporizador de apagado",
  "sv": "Insomningstimer",
  "da": "Sleeptimer",
  "nb": "Sovetimer",
  "ar": "مؤقت النوم",
  "sw": "Kipima muda cha usingizi"
 },
 "tvSleepSubtitle": {
  "fr": "L'application se ferme toute seule à la fin du minuteur (le flux s'arrête). Pratique le soir.",
  "en": "The app closes by itself when the timer ends (the stream stops). Handy at night.",
  "es": "La aplicación se cierra sola cuando termina el temporizador (el flujo se detiene). Práctico por la noche.",
  "sv": "Appen stängs av sig själv när timern går ut (strömmen stoppas). Praktiskt på kvällen.",
  "da": "Appen lukker af sig selv, når timeren udløber (streamen stopper). Praktisk om aftenen.",
  "nb": "Appen lukker seg selv når tidtakeren går ut (strømmen stopper). Praktisk om kvelden.",
  "ar": "يُغلق التطبيق نفسه عند انتهاء المؤقت (يتوقف البث). مفيد في المساء.",
  "sw": "Programu hujifunga yenyewe kipima muda kinapoisha (mtiririko husimama). Inafaa usiku."
 },
 "tvSleepCountdown": {
  "fr": "Extinction dans {remaining}",
  "en": "Turning off in {remaining}",
  "es": "Apagado en {remaining}",
  "sv": "Stängs av om {remaining}",
  "da": "Slukker om {remaining}",
  "nb": "Slår av om {remaining}",
  "ar": "الإيقاف بعد {remaining}",
  "sw": "Itazimika baada ya {remaining}"
 },
 "tvComponentsWaGreeting": {
  "fr": "Bonjour, je souhaite activer The Few TV.",
  "en": "Hello, I'd like to activate The Few TV.",
  "es": "Hola, quiero activar The Few TV.",
  "sv": "Hej, jag vill aktivera The Few TV.",
  "da": "Hej, jeg vil gerne aktivere The Few TV.",
  "nb": "Hei, jeg vil gjerne aktivere The Few TV.",
  "ar": "مرحبًا، أريد تفعيل The Few TV.",
  "sw": "Habari, ningependa kuwasha The Few TV."
 },
 "tvComponentsWaMyCode": {
  "fr": "Mon code : {code}",
  "en": "My code: {code}",
  "es": "Mi código: {code}",
  "sv": "Min kod: {code}",
  "da": "Min kode: {code}",
  "nb": "Min kode: {code}",
  "ar": "رمزي: {code}",
  "sw": "Msimbo wangu: {code}"
 },
 "tvFamilyTitle": {
  "fr": "Abonnement Famille",
  "en": "Family subscription",
  "es": "Suscripción Familiar",
  "sv": "Familjeabonnemang",
  "da": "Familieabonnement",
  "nb": "Familieabonnement",
  "ar": "اشتراك العائلة",
  "sw": "Usajili wa familia"
 },
 "tvFamilySubtitle": {
  "fr": "Partage ton abonnement avec 4 proches (5 appareils au total, comme Netflix). Tu génères un code, ton proche le tape sur son appareil — c'est tout.",
  "en": "Share your subscription with 4 loved ones (5 devices total, like Netflix). You generate a code, they type it on their device — that's it.",
  "es": "Comparte tu suscripción con 4 personas (5 dispositivos en total, como Netflix). Generas un código, tu familiar lo escribe en su dispositivo, y listo.",
  "sv": "Dela ditt abonnemang med 4 närstående (5 enheter totalt, som Netflix). Du skapar en kod, din närstående skriver in den på sin enhet — klart.",
  "da": "Del dit abonnement med 4 af dine nærmeste (5 enheder i alt, ligesom Netflix). Du laver en kode, din nærmeste taster den på sin enhed — så er det klaret.",
  "nb": "Del abonnementet ditt med 4 nære (5 enheter totalt, som Netflix). Du lager en kode, den andre taster den på sin enhet — det er alt.",
  "ar": "شارك اشتراكك مع 4 من أحبّائك (5 أجهزة كحدّ أقصى، مثل نتفليكس). أنشئ رمزًا، وليكتبه قريبك على جهازه — هذا كل شيء.",
  "sw": "Shiriki usajili wako na wapendwa 4 (jumla ya vifaa 5, kama Netflix). Unatengeneza msimbo, mpendwa wako anauandika kwenye kifaa chake — ndivyo tu."
 },
 "tvFamilyConnectionError": {
  "fr": "Connexion impossible. Réessaie plus tard.",
  "en": "Can't connect. Try again later.",
  "es": "No se pudo conectar. Inténtalo más tarde.",
  "sv": "Det gick inte att ansluta. Försök igen senare.",
  "da": "Kunne ikke oprette forbindelse. Prøv igen senere.",
  "nb": "Fikk ikke koblet til. Prøv igjen senere.",
  "ar": "تعذّر الاتصال. حاول لاحقًا.",
  "sw": "Imeshindwa kuunganisha. Jaribu tena baadaye."
 },
 "tvFamilyErrorNotPaid": {
  "fr": "Réservé aux abonnements ACTIFS (payés). Active d'abord cet appareil.",
  "en": "Only for ACTIVE (paid) subscriptions. Activate this device first.",
  "es": "Solo para suscripciones ACTIVAS (pagadas). Activa primero este dispositivo.",
  "sv": "Endast för AKTIVA (betalda) abonnemang. Aktivera den här enheten först.",
  "da": "Kun for AKTIVE (betalte) abonnementer. Aktivér denne enhed først.",
  "nb": "Kun for AKTIVE (betalte) abonnementer. Aktiver denne enheten først.",
  "ar": "متاح فقط للاشتراكات النشطة (المدفوعة). فعّل هذا الجهاز أولًا.",
  "sw": "Kwa usajili ULIO HAI (uliolipiwa) tu. Washa kifaa hiki kwanza."
 },
 "tvFamilyErrorIsMember": {
  "fr": "Cet appareil est déjà rattaché à une famille — il ne peut pas inviter.",
  "en": "This device is already attached to a family — it can't invite.",
  "es": "Este dispositivo ya está vinculado a una familia; no puede invitar.",
  "sv": "Den här enheten är redan kopplad till en familj — den kan inte bjuda in.",
  "da": "Denne enhed er allerede knyttet til en familie — den kan ikke invitere.",
  "nb": "Denne enheten er allerede knyttet til en familie — den kan ikke invitere.",
  "ar": "هذا الجهاز مرتبط بعائلة بالفعل — لا يمكنه إرسال دعوات.",
  "sw": "Kifaa hiki tayari kimeunganishwa na familia — hakiwezi kualika."
 },
 "tvFamilyErrorFull": {
  "fr": "Famille complète (limite du plan atteinte).",
  "en": "Family is full (plan limit reached).",
  "es": "Familia completa (límite del plan alcanzado).",
  "sv": "Familjen är full (planens gräns nådd).",
  "da": "Familien er fuld (planens grænse er nået).",
  "nb": "Familien er full (grensen for planen er nådd).",
  "ar": "العائلة مكتملة (تم بلوغ حدّ الخطة).",
  "sw": "Familia imejaa (kikomo cha mpango kimefikiwa)."
 },
 "tvFamilyErrorPlanRequired": {
  "fr": "Le PLAN FAMILLE est une option de ton abonnement. Demande à ton vendeur de l'activer. 👑",
  "en": "The FAMILY PLAN is an add-on to your subscription. Ask your seller to enable it. 👑",
  "es": "El PLAN FAMILIA es una opción de tu suscripción. Pide a tu vendedor que la active. 👑",
  "sv": "FAMILJEPLANEN är ett tillval till ditt abonnemang. Be din säljare aktivera den. 👑",
  "da": "FAMILIEPLANEN er et tilvalg til dit abonnement. Bed din forhandler om at aktivere den. 👑",
  "nb": "FAMILIEPLANEN er et tillegg til abonnementet ditt. Be selgeren din aktivere den. 👑",
  "ar": "خطة العائلة خيار إضافي في اشتراكك. اطلب من البائع تفعيلها. 👑",
  "sw": "MPANGO WA FAMILIA ni chaguo la ziada la usajili wako. Mwombe muuzaji wako aliwashe. 👑"
 },
 "tvFamilyErrorGeneric": {
  "fr": "Impossible pour le moment. Réessaie plus tard.",
  "en": "Not possible right now. Try again later.",
  "es": "No es posible por ahora. Inténtalo más tarde.",
  "sv": "Det går inte just nu. Försök igen senare.",
  "da": "Det er ikke muligt lige nu. Prøv igen senere.",
  "nb": "Ikke mulig akkurat nå. Prøv igjen senere.",
  "ar": "غير ممكن حاليًا. حاول لاحقًا.",
  "sw": "Haiwezekani kwa sasa. Jaribu tena baadaye."
 },
 "tvFamilyAttachedTo": {
  "fr": "Cet appareil est rattaché à l'abonnement famille {owner}.",
  "en": "This device is attached to the family subscription {owner}.",
  "es": "Este dispositivo está vinculado a la suscripción familiar {owner}.",
  "sv": "Den här enheten är kopplad till familjeabonnemanget {owner}.",
  "da": "Denne enhed er knyttet til familieabonnementet {owner}.",
  "nb": "Denne enheten er knyttet til familieabonnementet {owner}.",
  "ar": "هذا الجهاز مرتبط باشتراك العائلة {owner}.",
  "sw": "Kifaa hiki kimeunganishwa na usajili wa familia {owner}."
 },
 "tvFamilyOneMoment": {
  "fr": "Un instant…",
  "en": "One moment…",
  "es": "Un momento…",
  "sv": "Ett ögonblick…",
  "da": "Et øjeblik…",
  "nb": "Et øyeblikk…",
  "ar": "لحظة…",
  "sw": "Subiri kidogo…"
 },
 "tvFamilyLeaveButton": {
  "fr": "Quitter la famille",
  "en": "Leave the family",
  "es": "Salir de la familia",
  "sv": "Lämna familjen",
  "da": "Forlad familien",
  "nb": "Forlat familien",
  "ar": "مغادرة العائلة",
  "sw": "Ondoka kwenye familia"
 },
 "tvFamilyPlanBadge": {
  "fr": "👨‍👩‍👧  PLAN FAMILLE",
  "en": "👨‍👩‍👧  FAMILY PLAN",
  "es": "👨‍👩‍👧  PLAN FAMILIA",
  "sv": "👨‍👩‍👧  FAMILJEPLAN",
  "da": "👨‍👩‍👧  FAMILIEPLAN",
  "nb": "👨‍👩‍👧  FAMILIEPLAN",
  "ar": "👨‍👩‍👧  خطة العائلة",
  "sw": "👨‍👩‍👧  MPANGO WA FAMILIA"
 },
 "tvFamilyPlanPitch": {
  "fr": "Partage ton abonnement avec tes proches (jusqu'à 5 appareils, comme Netflix) : chacun son appareil, un seul abonnement.\n\nCette option n'est pas encore activée sur ton compte — contacte ton vendeur pour l'ajouter. 👑",
  "en": "Share your subscription with your loved ones (up to 5 devices, like Netflix): everyone gets their own device, one single subscription.\n\nThis option isn't enabled on your account yet — contact your seller to add it. 👑",
  "es": "Comparte tu suscripción con los tuyos (hasta 5 dispositivos, como Netflix): cada uno su dispositivo, una sola suscripción.\n\nEsta opción aún no está activada en tu cuenta; contacta a tu vendedor para añadirla. 👑",
  "sv": "Dela ditt abonnemang med dina närstående (upp till 5 enheter, som Netflix): var sin enhet, ett enda abonnemang.\n\nDet här tillvalet är inte aktiverat på ditt konto ännu — kontakta din säljare för att lägga till det. 👑",
  "da": "Del dit abonnement med dine nærmeste (op til 5 enheder, ligesom Netflix): hver sin enhed, ét samlet abonnement.\n\nDette tilvalg er endnu ikke aktiveret på din konto — kontakt din forhandler for at tilføje det. 👑",
  "nb": "Del abonnementet ditt med dine nære (opptil 5 enheter, som Netflix): hver sin enhet, ett eneste abonnement.\n\nDette tillegget er ikke aktivert på kontoen din ennå — kontakt selgeren din for å legge det til. 👑",
  "ar": "شارك اشتراكك مع أحبّائك (حتى 5 أجهزة، مثل نتفليكس): لكل واحد جهازه، واشتراك واحد فقط.\n\nهذا الخيار غير مفعّل بعد على حسابك — تواصل مع البائع لإضافته. 👑",
  "sw": "Shiriki usajili wako na wapendwa wako (hadi vifaa 5, kama Netflix): kila mtu na kifaa chake, usajili mmoja tu.\n\nChaguo hili bado halijawashwa kwenye akaunti yako — wasiliana na muuzaji wako ili aliongeze. 👑"
 },
 "tvFamilyPlanCheckButton": {
  "fr": "J'ai activé l'option — Vérifier",
  "en": "I've enabled the option — Check",
  "es": "Ya activé la opción — Verificar",
  "sv": "Jag har aktiverat tillvalet — Kontrollera",
  "da": "Jeg har aktiveret tilvalget — Tjek",
  "nb": "Jeg har aktivert tillegget — Sjekk",
  "ar": "فعّلت الخيار — تحقّق",
  "sw": "Nimewasha chaguo — Kagua"
 },
 "tvFamilyInviteCodeLabel": {
  "fr": "CODE D'INVITATION (valable 48 h)",
  "en": "INVITE CODE (valid 48 h)",
  "es": "CÓDIGO DE INVITACIÓN (válido 48 h)",
  "sv": "INBJUDNINGSKOD (giltig i 48 h)",
  "da": "INVITATIONSKODE (gyldig i 48 t)",
  "nb": "INVITASJONSKODE (gyldig i 48 t)",
  "ar": "رمز الدعوة (صالح لمدة 48 ساعة)",
  "sw": "MSIMBO WA MWALIKO (unafaa kwa saa 48)"
 },
 "tvFamilyInviteCodeHelp": {
  "fr": "Sur l'appareil de ton proche : écran d'activation → « J'ai un code famille » → taper ce code.",
  "en": "On your loved one's device: activation screen → \"I have a family code\" → type this code.",
  "es": "En el dispositivo de tu familiar: pantalla de activación → «Tengo un código familia» → escribir este código.",
  "sv": "På din närståendes enhet: aktiveringsskärmen → ”Jag har en familjekod” → skriv in den här koden.",
  "da": "På din nærmestes enhed: aktiveringsskærmen → ”Jeg har en familiekode” → tast denne kode.",
  "nb": "På enheten til den andre: aktiveringsskjermen → «Jeg har en familiekode» → tast inn denne koden.",
  "ar": "على جهاز قريبك: شاشة التفعيل ← «لديّ رمز عائلة» ← اكتب هذا الرمز.",
  "sw": "Kwenye kifaa cha mpendwa wako: skrini ya kuwasha → « Nina msimbo wa familia » → andika msimbo huu."
 },
 "tvFamilyGenerateCode": {
  "fr": "Générer un code d'invitation",
  "en": "Generate an invite code",
  "es": "Generar un código de invitación",
  "sv": "Skapa en inbjudningskod",
  "da": "Opret en invitationskode",
  "nb": "Lag en invitasjonskode",
  "ar": "إنشاء رمز دعوة",
  "sw": "Tengeneza msimbo wa mwaliko"
 },
 "tvFamilyGenerateNewCode": {
  "fr": "Générer un NOUVEAU code",
  "en": "Generate a NEW code",
  "es": "Generar un código NUEVO",
  "sv": "Skapa en NY kod",
  "da": "Opret en NY kode",
  "nb": "Lag en NY kode",
  "ar": "إنشاء رمز جديد",
  "sw": "Tengeneza msimbo MPYA"
 },
 "tvFamilyMembersHeader": {
  "fr": "MA FAMILLE ({count}/{max} proches + cet appareil)",
  "en": "MY FAMILY ({count}/{max} members + this device)",
  "es": "MI FAMILIA ({count}/{max} miembros + este dispositivo)",
  "sv": "MIN FAMILJ ({count}/{max} närstående + den här enheten)",
  "da": "MIN FAMILIE ({count}/{max} nærmeste + denne enhed)",
  "nb": "MIN FAMILIE ({count}/{max} nære + denne enheten)",
  "ar": "عائلتي ({count}/{max} من الأقارب + هذا الجهاز)",
  "sw": "FAMILIA YANGU (wapendwa {count}/{max} + kifaa hiki)"
 },
 "tvFamilyNoMembers": {
  "fr": "Aucun appareil rattaché pour l'instant.",
  "en": "No device attached yet.",
  "es": "Ningún dispositivo vinculado por ahora.",
  "sv": "Ingen enhet kopplad ännu.",
  "da": "Ingen enhed tilknyttet endnu.",
  "nb": "Ingen enhet knyttet til ennå.",
  "ar": "لا يوجد جهاز مرتبط حتى الآن.",
  "sw": "Hakuna kifaa kilichounganishwa bado."
 },
 "tvFamilyConfirmRemove": {
  "fr": "Confirmer ?",
  "en": "Confirm?",
  "es": "¿Confirmar?",
  "sv": "Bekräfta?",
  "da": "Bekræft?",
  "nb": "Bekreft?",
  "ar": "تأكيد؟",
  "sw": "Thibitisha?"
 },
 "tvFamilySimultaneousNote": {
  "fr": "ℹ️ Le nombre d'appareils qui regardent EN MÊME TEMPS dépend de ton abonnement (connexions simultanées de la ligne).",
  "en": "ℹ️ How many devices can watch AT THE SAME TIME depends on your subscription (the line's simultaneous connections).",
  "es": "ℹ️ El número de dispositivos que ven AL MISMO TIEMPO depende de tu suscripción (conexiones simultáneas de la línea).",
  "sv": "ℹ️ Hur många enheter som kan titta SAMTIDIGT beror på ditt abonnemang (linjens samtidiga anslutningar).",
  "da": "ℹ️ Hvor mange enheder der kan se SAMTIDIGT afhænger af dit abonnement (linjens samtidige forbindelser).",
  "nb": "ℹ️ Hvor mange enheter som kan se SAMTIDIG avhenger av abonnementet ditt (linjens samtidige tilkoblinger).",
  "ar": "ℹ️ عدد الأجهزة التي تشاهد في الوقت نفسه يعتمد على اشتراكك (الاتصالات المتزامنة للخط).",
  "sw": "ℹ️ Idadi ya vifaa vinavyotazama KWA WAKATI MMOJA inategemea usajili wako (miunganisho ya wakati mmoja ya laini)."
 },
 "tvFamilyNameDad": {
  "fr": "Papa",
  "en": "Dad",
  "es": "Papá",
  "sv": "Pappa",
  "da": "Far",
  "nb": "Pappa",
  "ar": "بابا",
  "sw": "Baba"
 },
 "tvFamilyNameMom": {
  "fr": "Maman",
  "en": "Mom",
  "es": "Mamá",
  "sv": "Mamma",
  "da": "Mor",
  "nb": "Mamma",
  "ar": "ماما",
  "sw": "Mama"
 },
 "tvFamilyNameChild1": {
  "fr": "Enfant 1",
  "en": "Kid 1",
  "es": "Niño 1",
  "sv": "Barn 1",
  "da": "Barn 1",
  "nb": "Barn 1",
  "ar": "طفل 1",
  "sw": "Mtoto 1"
 },
 "tvFamilyNameChild2": {
  "fr": "Enfant 2",
  "en": "Kid 2",
  "es": "Niño 2",
  "sv": "Barn 2",
  "da": "Barn 2",
  "nb": "Barn 2",
  "ar": "طفل 2",
  "sw": "Mtoto 2"
 },
 "tvFamilyNameTeen": {
  "fr": "Ado",
  "en": "Teen",
  "es": "Adolescente",
  "sv": "Tonåring",
  "da": "Teenager",
  "nb": "Tenåring",
  "ar": "مراهق",
  "sw": "Kijana"
 },
 "tvFamilyNameLivingRoom": {
  "fr": "Salon",
  "en": "Living room",
  "es": "Salón",
  "sv": "Vardagsrum",
  "da": "Stue",
  "nb": "Stue",
  "ar": "غرفة الجلوس",
  "sw": "Sebule"
 },
 "tvFamilyNameBedroom": {
  "fr": "Chambre",
  "en": "Bedroom",
  "es": "Dormitorio",
  "sv": "Sovrum",
  "da": "Soveværelse",
  "nb": "Soverom",
  "ar": "غرفة النوم",
  "sw": "Chumba cha kulala"
 },
 "tvFamilyJoinTitle": {
  "fr": "J'ai un code famille",
  "en": "I have a family code",
  "es": "Tengo un código familia",
  "sv": "Jag har en familjekod",
  "da": "Jeg har en familiekode",
  "nb": "Jeg har en familiekode",
  "ar": "لديّ رمز عائلة",
  "sw": "Nina msimbo wa familia"
 },
 "tvFamilyJoinSubtitle": {
  "fr": "Tape le code à 6 chiffres affiché sur l'appareil de ton proche (Réglages → Abonnement Famille).",
  "en": "Type the 6-digit code shown on your loved one's device (Settings → Family subscription).",
  "es": "Escribe el código de 6 dígitos que aparece en el dispositivo de tu familiar (Ajustes → Suscripción Familiar).",
  "sv": "Skriv in den 6-siffriga koden som visas på din närståendes enhet (Inställningar → Familjeabonnemang).",
  "da": "Tast den 6-cifrede kode, der vises på din nærmestes enhed (Indstillinger → Familieabonnement).",
  "nb": "Tast inn den 6-sifrede koden som vises på enheten til den andre (Innstillinger → Familieabonnement).",
  "ar": "اكتب الرمز المكوّن من 6 أرقام الظاهر على جهاز قريبك (الإعدادات ← اشتراك العائلة).",
  "sw": "Andika msimbo wa tarakimu 6 unaoonekana kwenye kifaa cha mpendwa wako (Mipangilio → Usajili wa familia)."
 },
 "tvFamilyJoinNetworkError": {
  "fr": "Connexion impossible. Vérifie le réseau et réessaie.",
  "en": "Can't connect. Check your network and try again.",
  "es": "No se pudo conectar. Revisa la red e inténtalo de nuevo.",
  "sv": "Det gick inte att ansluta. Kontrollera nätverket och försök igen.",
  "da": "Kunne ikke oprette forbindelse. Tjek netværket og prøv igen.",
  "nb": "Fikk ikke koblet til. Sjekk nettverket og prøv igjen.",
  "ar": "تعذّر الاتصال. تحقّق من الشبكة وحاول مجددًا.",
  "sw": "Imeshindwa kuunganisha. Kagua mtandao kisha ujaribu tena."
 },
 "tvFamilyJoinSuccess": {
  "fr": "🎉 C'est fait ! Cet appareil est rattaché à l'abonnement famille {owner}. L'app se débloque dans quelques secondes…",
  "en": "🎉 Done! This device is attached to the family subscription {owner}. The app will unlock in a few seconds…",
  "es": "🎉 ¡Listo! Este dispositivo está vinculado a la suscripción familiar {owner}. La app se desbloqueará en unos segundos…",
  "sv": "🎉 Klart! Den här enheten är kopplad till familjeabonnemanget {owner}. Appen låses upp om några sekunder…",
  "da": "🎉 Færdig! Denne enhed er knyttet til familieabonnementet {owner}. Appen låses op om få sekunder…",
  "nb": "🎉 Ferdig! Denne enheten er knyttet til familieabonnementet {owner}. Appen låses opp om noen sekunder…",
  "ar": "🎉 تمّ! هذا الجهاز أصبح مرتبطًا باشتراك العائلة {owner}. سيُفتح التطبيق خلال ثوانٍ…",
  "sw": "🎉 Imekamilika! Kifaa hiki kimeunganishwa na usajili wa familia {owner}. Programu itafunguka baada ya sekunde chache…"
 },
 "tvFamilyJoinCodeInvalid": {
  "fr": "Code invalide ou expiré. Redemande un code.",
  "en": "Invalid or expired code. Ask for a new one.",
  "es": "Código no válido o caducado. Pide otro código.",
  "sv": "Ogiltig eller utgången kod. Be om en ny kod.",
  "da": "Ugyldig eller udløbet kode. Bed om en ny kode.",
  "nb": "Ugyldig eller utløpt kode. Be om en ny kode.",
  "ar": "رمز غير صالح أو منتهي الصلاحية. اطلب رمزًا جديدًا.",
  "sw": "Msimbo si sahihi au umekwisha muda. Omba msimbo mpya."
 },
 "tvFamilyJoinFull": {
  "fr": "Cette famille est complète (limite du plan atteinte).",
  "en": "This family is full (plan limit reached).",
  "es": "Esta familia está completa (límite del plan alcanzado).",
  "sv": "Den här familjen är full (planens gräns nådd).",
  "da": "Denne familie er fuld (planens grænse er nået).",
  "nb": "Denne familien er full (grensen for planen er nådd).",
  "ar": "هذه العائلة مكتملة (تم بلوغ حدّ الخطة).",
  "sw": "Familia hii imejaa (kikomo cha mpango kimefikiwa)."
 },
 "tvFamilyJoinOwnerNotPaid": {
  "fr": "L'abonnement du propriétaire n'est plus actif.",
  "en": "The owner's subscription is no longer active.",
  "es": "La suscripción del propietario ya no está activa.",
  "sv": "Ägarens abonnemang är inte längre aktivt.",
  "da": "Ejerens abonnement er ikke længere aktivt.",
  "nb": "Eierens abonnement er ikke lenger aktivt.",
  "ar": "اشتراك المالك لم يعد نشطًا.",
  "sw": "Usajili wa mmiliki haupo hai tena."
 },
 "tvFamilyJoinPlanRequired": {
  "fr": "Le propriétaire n'a pas l'option PLAN FAMILLE — il doit la demander à son vendeur.",
  "en": "The owner doesn't have the FAMILY PLAN option — they need to ask their seller for it.",
  "es": "El propietario no tiene la opción PLAN FAMILIA; debe pedirla a su vendedor.",
  "sv": "Ägaren har inte tillvalet FAMILJEPLAN — hen måste be sin säljare om det.",
  "da": "Ejeren har ikke tilvalget FAMILIEPLAN — vedkommende skal bede sin forhandler om det.",
  "nb": "Eieren har ikke tillegget FAMILIEPLAN — vedkommende må be selgeren sin om det.",
  "ar": "المالك لا يملك خيار خطة العائلة — عليه طلبه من البائع.",
  "sw": "Mmiliki hana chaguo la MPANGO WA FAMILIA — anapaswa kuliomba kwa muuzaji wake."
 },
 "tvFamilyJoinOwnCode": {
  "fr": "C'est ton propre code 🙂 — il est pour tes proches.",
  "en": "That's your own code 🙂 — it's meant for your loved ones.",
  "es": "Es tu propio código 🙂; es para los tuyos.",
  "sv": "Det är din egen kod 🙂 — den är till dina närstående.",
  "da": "Det er din egen kode 🙂 — den er til dine nærmeste.",
  "nb": "Det er din egen kode 🙂 — den er til dine nære.",
  "ar": "هذا رمزك أنت 🙂 — إنه مخصّص لأحبّائك.",
  "sw": "Huu ni msimbo wako mwenyewe 🙂 — ni wa wapendwa wako."
 },
 "tvActivationFamilyCodeButton": {
  "fr": "👨‍👩‍👧  J'ai un code famille",
  "en": "👨‍👩‍👧  I have a family code",
  "es": "👨‍👩‍👧  Tengo un código familia",
  "sv": "👨‍👩‍👧  Jag har en familjekod",
  "da": "👨‍👩‍👧  Jeg har en familiekode",
  "nb": "👨‍👩‍👧  Jeg har en familiekode",
  "ar": "👨‍👩‍👧  لديّ رمز عائلة",
  "sw": "👨‍👩‍👧  Nina msimbo wa familia"
 },
 "tvActivationLegalNotice": {
  "fr": "Lecteur multimédia — ne vend ni ne fournit aucune chaîne ni lien M3U. Le contenu est apporté par l'utilisateur. Conditions : app.7themotion.com/terms",
  "en": "Media player — does not sell or provide any channels or M3U links. Content is supplied by the user. Terms: app.7themotion.com/terms",
  "es": "Reproductor multimedia: no vende ni proporciona canales ni enlaces M3U. El contenido lo aporta el usuario. Condiciones: app.7themotion.com/terms",
  "sv": "Mediaspelare — säljer eller tillhandahåller inga kanaler eller M3U-länkar. Innehållet tillhandahålls av användaren. Villkor: app.7themotion.com/terms",
  "da": "Medieafspiller — sælger eller leverer ingen kanaler eller M3U-links. Indholdet leveres af brugeren. Vilkår: app.7themotion.com/terms",
  "nb": "Mediespiller — selger eller leverer ingen kanaler eller M3U-lenker. Innholdet leveres av brukeren. Vilkår: app.7themotion.com/terms",
  "ar": "مشغّل وسائط — لا يبيع ولا يوفّر أي قنوات أو روابط M3U. المحتوى يوفّره المستخدم. الشروط: app.7themotion.com/terms",
  "sw": "Kichezaji cha media — hakiuzi wala kutoa chaneli au viungo vya M3U. Maudhui huletwa na mtumiaji. Masharti: app.7themotion.com/terms"
 },
 "tvTeamPickerNotFound": {
  "fr": "« {name} » introuvable — essaie la recherche.",
  "en": "\"{name}\" not found — try the search.",
  "es": "«{name}» no se encontró; prueba la búsqueda.",
  "sv": "”{name}” hittades inte — testa sökningen.",
  "da": "”{name}” blev ikke fundet — prøv søgningen.",
  "nb": "«{name}» ble ikke funnet — prøv søket.",
  "ar": "لم يتم العثور على «{name}» — جرّب البحث.",
  "sw": "« {name} » haikupatikana — jaribu utafutaji."
 },
 "tvTeamPickerSportFootball": {
  "fr": "Football",
  "en": "Football",
  "es": "Fútbol",
  "sv": "Fotboll",
  "da": "Fodbold",
  "nb": "Fotball",
  "ar": "كرة القدم",
  "sw": "Soka"
 },
 "tvTeamPickerSportBasketball": {
  "fr": "Basket (NBA)",
  "en": "Basketball (NBA)",
  "es": "Baloncesto (NBA)",
  "sv": "Basket (NBA)",
  "da": "Basketball (NBA)",
  "nb": "Basketball (NBA)",
  "ar": "كرة السلة (NBA)",
  "sw": "Mpira wa kikapu (NBA)"
 },
 "tvTeamPickerSportRugby": {
  "fr": "Rugby",
  "en": "Rugby",
  "es": "Rugby",
  "sv": "Rugby",
  "da": "Rugby",
  "nb": "Rugby",
  "ar": "الرغبي",
  "sw": "Ragbi"
 },
 "tvSportsEmptyHelp": {
  "fr": "Tu verras leurs scores et leurs prochains matchs, un bandeau d'actu qui défile, et une alarme ~1 h avant chaque match.",
  "en": "You'll see their scores and upcoming matches, a scrolling news ticker, and an alert ~1 h before each match.",
  "es": "Verás sus marcadores y próximos partidos, una cinta de noticias y una alarma ~1 h antes de cada partido.",
  "sv": "Du ser deras resultat och kommande matcher, ett rullande nyhetsband och ett larm ca 1 h före varje match.",
  "da": "Du ser deres resultater og kommende kampe, et rullende nyhedsbånd og en alarm ca. 1 t før hver kamp.",
  "nb": "Du ser resultatene og kommende kamper, et rullende nyhetsbånd og en alarm ca. 1 t før hver kamp.",
  "ar": "سترى نتائجها ومبارياتها القادمة، وشريط أخبار متحرّكًا، وتنبيهًا قبل كل مباراة بساعة تقريبًا.",
  "sw": "Utaona matokeo yao na mechi zijazo, utepe wa habari unaosogea, na kengele ~saa 1 kabla ya kila mechi."
 },
 "tvSportsLastMatch": {
  "fr": "Dernier match",
  "en": "Last match",
  "es": "Último partido",
  "sv": "Senaste matchen",
  "da": "Seneste kamp",
  "nb": "Siste kamp",
  "ar": "آخر مباراة",
  "sw": "Mechi iliyopita"
 },
 "tvSportsNextMatch": {
  "fr": "Prochain match",
  "en": "Next match",
  "es": "Próximo partido",
  "sv": "Nästa match",
  "da": "Næste kamp",
  "nb": "Neste kamp",
  "ar": "المباراة القادمة",
  "sw": "Mechi ijayo"
 },
 "tvSportsTickerLabel": {
  "fr": "ACTU",
  "en": "NEWS",
  "es": "ACTUALIDAD",
  "sv": "NYTT",
  "da": "NYT",
  "nb": "NYTT",
  "ar": "الأخبار",
  "sw": "HABARI"
 },
 "tvSportsVersus": {
  "fr": "vs",
  "en": "vs",
  "es": "vs",
  "sv": "vs",
  "da": "vs",
  "nb": "vs",
  "ar": "ضد",
  "sw": "vs"
 },
 "tvDiagTitle": {
  "fr": "DIAGNOSTIC ON-DEVICE — DeFew TV",
  "en": "ON-DEVICE DIAGNOSTIC — DeFew TV",
  "es": "DIAGNÓSTICO EN EL DISPOSITIVO — DeFew TV",
  "sv": "DIAGNOSTIK PÅ ENHETEN — DeFew TV",
  "da": "DIAGNOSTIK PÅ ENHEDEN — DeFew TV",
  "nb": "DIAGNOSTIKK PÅ ENHETEN — DeFew TV",
  "ar": "تشخيص على الجهاز — DeFew TV",
  "sw": "UCHUNGUZI KWENYE KIFAA — DeFew TV"
 },
 "tvDiagSubtitle": {
  "fr": "Teste si la box peut jouer le flux depuis sa propre IP.",
  "en": "Tests whether the box can play the stream from its own IP.",
  "es": "Comprueba si la caja puede reproducir el flujo desde su propia IP.",
  "sv": "Testar om boxen kan spela upp strömmen från sin egen IP.",
  "da": "Tester om boksen kan afspille streamen fra sin egen IP.",
  "nb": "Tester om boksen kan spille av strømmen fra sin egen IP.",
  "ar": "يختبر ما إذا كان الجهاز يستطيع تشغيل البث من عنوان IP الخاص به.",
  "sw": "Hujaribu kama kisanduku kinaweza kucheza mtiririko kutoka kwa IP yake yenyewe."
 },
 "tvDiagExitHint": {
  "fr": "RETOUR pour quitter",
  "en": "BACK to exit",
  "es": "ATRÁS para salir",
  "sv": "TILLBAKA för att avsluta",
  "da": "TILBAGE for at afslutte",
  "nb": "TILBAKE for å avslutte",
  "ar": "زر الرجوع للخروج",
  "sw": "RUDI ili kutoka"
 },
 "tvDiagCheckCaptive": {
  "fr": "1. Portail captif (204)",
  "en": "1. Captive portal (204)",
  "es": "1. Portal cautivo (204)",
  "sv": "1. Captive portal (204)",
  "da": "1. Captive portal (204)",
  "nb": "1. Captive portal (204)",
  "ar": "1. بوابة أسيرة (204)",
  "sw": "1. Captive portal (204)"
 },
 "tvDiagCheckDns": {
  "fr": "2. Résolution DNS hôte IPTV",
  "en": "2. IPTV host DNS resolution",
  "es": "2. Resolución DNS del host IPTV",
  "sv": "2. DNS-uppslag för IPTV-värd",
  "da": "2. DNS-opslag for IPTV-vært",
  "nb": "2. DNS-oppslag for IPTV-vert",
  "ar": "2. تحليل DNS لمضيف IPTV",
  "sw": "2. Utatuzi wa DNS wa seva pangishi ya IPTV"
 },
 "tvDiagCheckStream": {
  "fr": "3. Joignabilité flux (HTTP / 456)",
  "en": "3. Stream reachability (HTTP / 456)",
  "es": "3. Accesibilidad del flujo (HTTP / 456)",
  "sv": "3. Strömmens nåbarhet (HTTP / 456)",
  "da": "3. Streamens tilgængelighed (HTTP / 456)",
  "nb": "3. Strømmens tilgjengelighet (HTTP / 456)",
  "ar": "3. إمكانية الوصول إلى البث (HTTP / 456)",
  "sw": "3. Ufikivu wa mtiririko (HTTP / 456)"
 },
 "tvDiagCheckSource": {
  "fr": "4. Source poussée (device-source)",
  "en": "4. Pushed source (device-source)",
  "es": "4. Fuente asignada (device-source)",
  "sv": "4. Tilldelad källa (device-source)",
  "da": "4. Tildelt kilde (device-source)",
  "nb": "4. Tildelt kilde (device-source)",
  "ar": "4. المصدر المرسل (device-source)",
  "sw": "4. Chanzo kilichotumwa (device-source)"
 },
 "tvDiagCheckPlayer": {
  "fr": "5. Sonde ExoPlayer / Media3",
  "en": "5. ExoPlayer / Media3 probe",
  "es": "5. Sonda ExoPlayer / Media3",
  "sv": "5. ExoPlayer / Media3-sond",
  "da": "5. ExoPlayer / Media3-sonde",
  "nb": "5. ExoPlayer / Media3-sonde",
  "ar": "5. مسبار ExoPlayer / Media3",
  "sw": "5. Kichunguzi cha ExoPlayer / Media3"
 },
 "tvDiagCaptiveRunning": {
  "fr": "requête generate_204…",
  "en": "requesting generate_204…",
  "es": "solicitud generate_204…",
  "sv": "begäran generate_204…",
  "da": "forespørgsel generate_204…",
  "nb": "forespørsel generate_204…",
  "ar": "طلب generate_204…",
  "sw": "ombi la generate_204…"
 },
 "tvDiagCaptiveOk": {
  "fr": "HTTP 204 (sortie Internet libre)",
  "en": "HTTP 204 (open Internet access)",
  "es": "HTTP 204 (salida a Internet libre)",
  "sv": "HTTP 204 (fri internetåtkomst)",
  "da": "HTTP 204 (fri internetadgang)",
  "nb": "HTTP 204 (fri internettilgang)",
  "ar": "HTTP 204 (اتصال إنترنت حر)",
  "sw": "HTTP 204 (mtandao huru)"
 },
 "tvDiagCaptiveFail": {
  "fr": "HTTP {code} corps={bytes}o → portail captif probable",
  "en": "HTTP {code} body={bytes}B → captive portal likely",
  "es": "HTTP {code} cuerpo={bytes}o → probable portal cautivo",
  "sv": "HTTP {code} innehåll={bytes}B → troligen captive portal",
  "da": "HTTP {code} indhold={bytes}B → sandsynligvis captive portal",
  "nb": "HTTP {code} innhold={bytes}B → sannsynligvis captive portal",
  "ar": "HTTP {code} حجم={bytes} بايت ← بوابة أسيرة محتملة",
  "sw": "HTTP {code} mwili={bytes}B → huenda kuna captive portal"
 },
 "tvDiagNoReply": {
  "fr": "pas de réponse en 8 s",
  "en": "no response within 8 s",
  "es": "sin respuesta en 8 s",
  "sv": "inget svar inom 8 s",
  "da": "intet svar inden for 8 s",
  "nb": "ikke noe svar innen 8 s",
  "ar": "لا استجابة خلال 8 ثوانٍ",
  "sw": "hakuna jibu ndani ya sekunde 8"
 },
 "tvDiagNoChannelHost": {
  "fr": "aucune chaîne chargée → hôte INCONNU",
  "en": "no channel loaded → host UNKNOWN",
  "es": "ningún canal cargado → host DESCONOCIDO",
  "sv": "ingen kanal laddad → värd OKÄND",
  "da": "ingen kanal indlæst → vært UKENDT",
  "nb": "ingen kanal lastet → vert UKJENT",
  "ar": "لا توجد قناة محمّلة ← المضيف غير معروف",
  "sw": "hakuna kituo kilichopakiwa → seva pangishi HAIJULIKANI"
 },
 "tvDiagDnsLookup": {
  "fr": "lookup {host}…",
  "en": "lookup {host}…",
  "es": "búsqueda de {host}…",
  "sv": "slår upp {host}…",
  "da": "opslag af {host}…",
  "nb": "slår opp {host}…",
  "ar": "جارٍ البحث عن {host}…",
  "sw": "inatafuta {host}…"
 },
 "tvDiagDnsNoIp": {
  "fr": "{host} → aucune IP",
  "en": "{host} → no IP",
  "es": "{host} → ninguna IP",
  "sv": "{host} → ingen IP",
  "da": "{host} → ingen IP",
  "nb": "{host} → ingen IP",
  "ar": "{host} ← لا يوجد عنوان IP",
  "sw": "{host} → hakuna IP"
 },
 "tvDiagDnsTimeout": {
  "fr": "{host} : pas de réponse DNS en 8 s",
  "en": "{host}: no DNS response within 8 s",
  "es": "{host}: sin respuesta DNS en 8 s",
  "sv": "{host}: inget DNS-svar inom 8 s",
  "da": "{host}: intet DNS-svar inden for 8 s",
  "nb": "{host}: ikke noe DNS-svar innen 8 s",
  "ar": "{host}: لا استجابة DNS خلال 8 ثوانٍ",
  "sw": "{host}: hakuna jibu la DNS ndani ya sekunde 8"
 },
 "tvDiagNoChannelUrl": {
  "fr": "aucune chaîne chargée → URL INCONNUE",
  "en": "no channel loaded → URL UNKNOWN",
  "es": "ningún canal cargado → URL DESCONOCIDA",
  "sv": "ingen kanal laddad → URL OKÄND",
  "da": "ingen kanal indlæst → URL UKENDT",
  "nb": "ingen kanal lastet → URL UKJENT",
  "ar": "لا توجد قناة محمّلة ← عنوان URL غير معروف",
  "sw": "hakuna kituo kilichopakiwa → URL HAIJULIKANI"
 },
 "tvDiagStreamHead": {
  "fr": "HEAD du flux…",
  "en": "HEAD request on the stream…",
  "es": "HEAD del flujo…",
  "sv": "HEAD på strömmen…",
  "da": "HEAD på streamen…",
  "nb": "HEAD på strømmen…",
  "ar": "طلب HEAD للبث…",
  "sw": "HEAD ya mtiririko…"
 },
 "tvDiagStream456": {
  "fr": "HTTP 456 — fournisseur bloque cette IP",
  "en": "HTTP 456 — provider blocks this IP",
  "es": "HTTP 456 — el proveedor bloquea esta IP",
  "sv": "HTTP 456 — leverantören blockerar denna IP",
  "da": "HTTP 456 — udbyderen blokerer denne IP",
  "nb": "HTTP 456 — leverandøren blokkerer denne IP-en",
  "ar": "HTTP 456 — المزوّد يحظر عنوان IP هذا",
  "sw": "HTTP 456 — mtoa huduma amezuia IP hii"
 },
 "tvDiagStreamOk": {
  "fr": "HTTP {code} (flux joignable)",
  "en": "HTTP {code} (stream reachable)",
  "es": "HTTP {code} (flujo accesible)",
  "sv": "HTTP {code} (strömmen nåbar)",
  "da": "HTTP {code} (stream tilgængelig)",
  "nb": "HTTP {code} (strøm tilgjengelig)",
  "ar": "HTTP {code} (يمكن الوصول إلى البث)",
  "sw": "HTTP {code} (mtiririko unafikika)"
 },
 "tvDiagSourceReadingMac": {
  "fr": "lecture MAC…",
  "en": "reading MAC…",
  "es": "leyendo MAC…",
  "sv": "läser MAC…",
  "da": "læser MAC…",
  "nb": "leser MAC…",
  "ar": "قراءة عنوان MAC…",
  "sw": "inasoma MAC…"
 },
 "tvDiagSourceMacUnknown": {
  "fr": "MAC INCONNUE ({mac})",
  "en": "MAC UNKNOWN ({mac})",
  "es": "MAC DESCONOCIDA ({mac})",
  "sv": "MAC OKÄND ({mac})",
  "da": "MAC UKENDT ({mac})",
  "nb": "MAC UKJENT ({mac})",
  "ar": "عنوان MAC غير معروف ({mac})",
  "sw": "MAC HAIJULIKANI ({mac})"
 },
 "tvDiagSourceAssigned": {
  "fr": "HTTP 200 — source assignée",
  "en": "HTTP 200 — source assigned",
  "es": "HTTP 200 — fuente asignada",
  "sv": "HTTP 200 — källa tilldelad",
  "da": "HTTP 200 — kilde tildelt",
  "nb": "HTTP 200 — kilde tildelt",
  "ar": "HTTP 200 — تم تعيين مصدر",
  "sw": "HTTP 200 — chanzo kimewekwa"
 },
 "tvDiagSourceNone": {
  "fr": "HTTP 200 — aucune source assignée",
  "en": "HTTP 200 — no source assigned",
  "es": "HTTP 200 — ninguna fuente asignada",
  "sv": "HTTP 200 — ingen källa tilldelad",
  "da": "HTTP 200 — ingen kilde tildelt",
  "nb": "HTTP 200 — ingen kilde tildelt",
  "ar": "HTTP 200 — لم يتم تعيين أي مصدر",
  "sw": "HTTP 200 — hakuna chanzo kilichowekwa"
 },
 "tvDiagPlayerOpening": {
  "fr": "ouverture sonde ExoPlayer…",
  "en": "opening ExoPlayer probe…",
  "es": "abriendo sonda ExoPlayer…",
  "sv": "öppnar ExoPlayer-sond…",
  "da": "åbner ExoPlayer-sonde…",
  "nb": "åpner ExoPlayer-sonde…",
  "ar": "فتح مسبار ExoPlayer…",
  "sw": "inafungua kichunguzi cha ExoPlayer…"
 },
 "tvDiagPlayerFirstFrame": {
  "fr": "1re image décodée et affichée",
  "en": "first frame decoded and displayed",
  "es": "primer fotograma decodificado y mostrado",
  "sv": "första bildrutan avkodad och visad",
  "da": "første billede afkodet og vist",
  "nb": "første bilde dekodet og vist",
  "ar": "تم فك ترميز أول إطار وعرضه",
  "sw": "fremu ya kwanza imesimbuliwa na kuonyeshwa"
 },
 "tvDiagPlayerError": {
  "fr": "ExoPlayer a renvoyé une erreur",
  "en": "ExoPlayer returned an error",
  "es": "ExoPlayer devolvió un error",
  "sv": "ExoPlayer returnerade ett fel",
  "da": "ExoPlayer returnerede en fejl",
  "nb": "ExoPlayer returnerte en feil",
  "ar": "أعاد ExoPlayer خطأ",
  "sw": "ExoPlayer ilirudisha hitilafu"
 },
 "tvDiagPlayerNoFrame": {
  "fr": "aucune image en 8 s",
  "en": "no frame within 8 s",
  "es": "ninguna imagen en 8 s",
  "sv": "ingen bild inom 8 s",
  "da": "intet billede inden for 8 s",
  "nb": "ikke noe bilde innen 8 s",
  "ar": "لا صورة خلال 8 ثوانٍ",
  "sw": "hakuna picha ndani ya sekunde 8"
 },
 "tvDiagVerdictRunning": {
  "fr": "DIAGNOSTIC EN COURS…",
  "en": "DIAGNOSTIC RUNNING…",
  "es": "DIAGNÓSTICO EN CURSO…",
  "sv": "DIAGNOSTIK PÅGÅR…",
  "da": "DIAGNOSTIK I GANG…",
  "nb": "DIAGNOSTIKK PÅGÅR…",
  "ar": "التشخيص جارٍ…",
  "sw": "UCHUNGUZI UNAENDELEA…"
 },
 "tvDiagVerdictPivotOk": {
  "fr": "PIVOT ON-DEVICE VALIDÉ",
  "en": "ON-DEVICE PIVOT VALIDATED",
  "es": "PIVOTE EN EL DISPOSITIVO VALIDADO",
  "sv": "PIVOT PÅ ENHETEN GODKÄND",
  "da": "PIVOT PÅ ENHEDEN GODKENDT",
  "nb": "PIVOT PÅ ENHETEN GODKJENT",
  "ar": "تم التحقق من التشغيل على الجهاز",
  "sw": "UCHEZAJI KWENYE KIFAA UMETHIBITISHWA"
 },
 "tvDiagVerdictNetworkBlock": {
  "fr": "BLOCAGE CÔTÉ RÉSEAU",
  "en": "NETWORK-SIDE BLOCK",
  "es": "BLOQUEO EN LA RED",
  "sv": "BLOCKERING PÅ NÄTVERKSSIDAN",
  "da": "BLOKERING PÅ NETVÆRKSSIDEN",
  "nb": "BLOKKERING PÅ NETTVERKSSIDEN",
  "ar": "حظر من جهة الشبكة",
  "sw": "KIZUIZI UPANDE WA MTANDAO"
 },
 "tvDiagVerdictPlayerBug": {
  "fr": "BUG PLAYER",
  "en": "PLAYER BUG",
  "es": "ERROR DEL REPRODUCTOR",
  "sv": "SPELARBUGG",
  "da": "AFSPILLERFEJL",
  "nb": "AVSPILLERFEIL",
  "ar": "خلل في المشغّل",
  "sw": "HITILAFU YA KICHEZAJI"
 },
 "tvDiagVerdictPartial": {
  "fr": "DIAGNOSTIC PARTIEL",
  "en": "PARTIAL DIAGNOSTIC",
  "es": "DIAGNÓSTICO PARCIAL",
  "sv": "OFULLSTÄNDIG DIAGNOSTIK",
  "da": "DELVIS DIAGNOSTIK",
  "nb": "DELVIS DIAGNOSTIKK",
  "ar": "تشخيص جزئي",
  "sw": "UCHUNGUZI WA SEHEMU"
 },
 "tvLegalTitle": {
  "fr": "Mentions légales & Conditions",
  "en": "Legal notice & Terms",
  "es": "Aviso legal y Condiciones",
  "sv": "Juridisk information & Villkor",
  "da": "Juridisk meddelelse & Vilkår",
  "nb": "Juridisk merknad & Vilkår",
  "ar": "الإشعار القانوني والشروط",
  "sw": "Taarifa za kisheria na Masharti"
 },
 "tvLegalIntro": {
  "fr": "Cette application est un lecteur. Elle ne vend ni ne fournit aucune chaîne ni lien. Haut/Bas pour faire défiler, Retour pour quitter.",
  "en": "This application is a player. It neither sells nor provides any channel or link. Up/Down to scroll, Back to exit.",
  "es": "Esta aplicación es un reproductor. No vende ni proporciona ningún canal ni enlace. Arriba/Abajo para desplazarte, Atrás para salir.",
  "sv": "Den här applikationen är en spelare. Den varken säljer eller tillhandahåller några kanaler eller länkar. Upp/Ner för att bläddra, Tillbaka för att avsluta.",
  "da": "Denne applikation er en afspiller. Den hverken sælger eller leverer kanaler eller links. Op/Ned for at rulle, Tilbage for at afslutte.",
  "nb": "Denne applikasjonen er en avspiller. Den verken selger eller leverer kanaler eller lenker. Opp/Ned for å bla, Tilbake for å avslutte.",
  "ar": "هذا التطبيق مشغّل. وهو لا يبيع ولا يوفر أي قناة أو رابط. الأعلى/الأسفل للتمرير، والرجوع للخروج.",
  "sw": "Programu hii ni kichezaji. Haiuzi wala haitoi kituo au kiungo chochote. Juu/Chini kusogeza, Rudi kutoka."
 },
 "tvLegalSection1Title": {
  "fr": "1. Nature de l'application — un LECTEUR, rien d'autre",
  "en": "1. Nature of the application — a PLAYER, nothing more",
  "es": "1. Naturaleza de la aplicación — un REPRODUCTOR, nada más",
  "sv": "1. Applikationens natur — en SPELARE, inget annat",
  "da": "1. Applikationens karakter — en AFSPILLER, intet andet",
  "nb": "1. Applikasjonens art — en AVSPILLER, ikke noe annet",
  "ar": "1. طبيعة التطبيق — مشغّل فقط، لا غير",
  "sw": "1. Asili ya programu — KICHEZAJI tu, hakuna kingine"
 },
 "tvLegalSection1Body": {
  "fr": "Cette application est un LECTEUR multimédia (player) permettant de lire des flux audio/vidéo fournis par l'utilisateur. Elle NE FOURNIT PAS, NE VEND PAS, N'HÉBERGE PAS, NE DIFFUSE PAS et N'INDEXE AUCUNE chaîne de télévision, flux, contenu audiovisuel, ni liste de lecture (M3U) ou identifiants de portail (Xtream). Aucun contenu n'est inclus, préchargé ou commercialisé avec l'application.",
  "en": "This application is a multimedia PLAYER used to play audio/video streams supplied by the user. It DOES NOT PROVIDE, SELL, HOST, BROADCAST or INDEX ANY television channel, stream, audiovisual content, playlist (M3U) or portal credentials (Xtream). No content is included, preloaded or sold with the application.",
  "es": "Esta aplicación es un REPRODUCTOR multimedia que permite reproducir flujos de audio/vídeo proporcionados por el usuario. NO PROPORCIONA, NO VENDE, NO ALOJA, NO DIFUNDE NI INDEXA NINGÚN canal de televisión, flujo, contenido audiovisual, lista de reproducción (M3U) ni credenciales de portal (Xtream). Ningún contenido se incluye, precarga o comercializa con la aplicación.",
  "sv": "Den här applikationen är en multimediaSPELARE som spelar upp ljud-/videoströmmar som tillhandahålls av användaren. Den TILLHANDAHÅLLER, SÄLJER, LAGRAR, SÄNDER eller INDEXERAR INGA tv-kanaler, strömmar, audiovisuellt innehåll, spellistor (M3U) eller portaluppgifter (Xtream). Inget innehåll ingår, är förinstallerat eller säljs med applikationen.",
  "da": "Denne applikation er en multimedieAFSPILLER, der afspiller lyd-/videostreams leveret af brugeren. Den LEVERER, SÆLGER, HOSTER, UDSENDER eller INDEKSERER INGEN tv-kanaler, streams, audiovisuelt indhold, afspilningslister (M3U) eller portaloplysninger (Xtream). Intet indhold er inkluderet, forudindlæst eller markedsført med applikationen.",
  "nb": "Denne applikasjonen er en multimedieAVSPILLER som spiller av lyd-/videostrømmer levert av brukeren. Den LEVERER, SELGER, LAGRER, KRINGKASTER eller INDEKSERER INGEN tv-kanaler, strømmer, audiovisuelt innhold, spillelister (M3U) eller portalopplysninger (Xtream). Ikke noe innhold følger med, er forhåndslastet eller selges med applikasjonen.",
  "ar": "هذا التطبيق مشغّل وسائط متعددة يتيح تشغيل بثوث صوتية/مرئية يوفرها المستخدم بنفسه. وهو لا يوفّر ولا يبيع ولا يستضيف ولا يبث ولا يفهرس أي قناة تلفزيونية أو بث أو محتوى سمعي بصري أو قائمة تشغيل (M3U) أو بيانات اعتماد بوابة (Xtream). لا يتضمن التطبيق أي محتوى مضمّن أو محمّل مسبقًا أو مسوّق معه.",
  "sw": "Programu hii ni KICHEZAJI cha medianuwai kinachocheza mitiririko ya sauti/video inayotolewa na mtumiaji. HAITOI, HAIUZI, HAIHIFADHI, HAITANGAZI wala HAIORODHESHI kituo chochote cha televisheni, mtiririko, maudhui ya sauti na picha, orodha ya kucheza (M3U) au vitambulisho vya lango (Xtream). Hakuna maudhui yaliyojumuishwa, yaliyopakiwa awali au yanayouzwa pamoja na programu."
 },
 "tvLegalSection2Title": {
  "fr": "2. Contenu fourni par l'utilisateur",
  "en": "2. User-supplied content",
  "es": "2. Contenido proporcionado por el usuario",
  "sv": "2. Innehåll som tillhandahålls av användaren",
  "da": "2. Indhold leveret af brugeren",
  "nb": "2. Innhold levert av brukeren",
  "ar": "2. المحتوى المقدَّم من المستخدم",
  "sw": "2. Maudhui yanayotolewa na mtumiaji"
 },
 "tvLegalSection2Body": {
  "fr": "L'utilisateur fournit lui-même ses propres sources (lien M3U / identifiants Xtream), obtenues auprès de son propre fournisseur. L'utilisateur est SEUL responsable des contenus qu'il ajoute, lit ou diffuse, ainsi que de la détention des droits, licences et abonnements nécessaires.",
  "en": "The user supplies their own sources (M3U link / Xtream credentials), obtained from their own provider. The user is SOLELY responsible for the content they add, play or broadcast, and for holding the necessary rights, licences and subscriptions.",
  "es": "El usuario proporciona por sí mismo sus propias fuentes (enlace M3U / credenciales Xtream), obtenidas de su propio proveedor. El usuario es el ÚNICO responsable de los contenidos que añade, reproduce o difunde, así como de poseer los derechos, licencias y suscripciones necesarios.",
  "sv": "Användaren tillhandahåller själv sina egna källor (M3U-länk / Xtream-uppgifter), som erhållits från användarens egen leverantör. Användaren är ENSAM ansvarig för det innehåll som läggs till, spelas upp eller sänds, samt för att inneha nödvändiga rättigheter, licenser och abonnemang.",
  "da": "Brugeren leverer selv sine egne kilder (M3U-link / Xtream-oplysninger), som er anskaffet hos brugerens egen udbyder. Brugeren er ENEANSVARLIG for det indhold, vedkommende tilføjer, afspiller eller udsender, samt for at besidde de nødvendige rettigheder, licenser og abonnementer.",
  "nb": "Brukeren leverer selv sine egne kilder (M3U-lenke / Xtream-opplysninger), anskaffet hos brukerens egen leverandør. Brukeren er ALENE ansvarlig for innholdet som legges til, spilles av eller kringkastes, samt for å inneha nødvendige rettigheter, lisenser og abonnementer.",
  "ar": "يوفّر المستخدم بنفسه مصادره الخاصة (رابط M3U / بيانات اعتماد Xtream) التي حصل عليها من مزوّده الخاص. والمستخدم وحده مسؤول عن المحتويات التي يضيفها أو يشغّلها أو يبثها، وعن امتلاك الحقوق والتراخيص والاشتراكات اللازمة.",
  "sw": "Mtumiaji hutoa mwenyewe vyanzo vyake (kiungo cha M3U / vitambulisho vya Xtream), vilivyopatikana kutoka kwa mtoa huduma wake mwenyewe. Mtumiaji PEKEE ndiye anayewajibika kwa maudhui anayoongeza, kucheza au kutangaza, na kwa kumiliki haki, leseni na usajili unaohitajika."
 },
 "tvLegalSection3Title": {
  "fr": "3. Abonnement = le LOGICIEL, pas le contenu",
  "en": "3. Subscription = the SOFTWARE, not the content",
  "es": "3. Suscripción = el SOFTWARE, no el contenido",
  "sv": "3. Abonnemang = PROGRAMVARAN, inte innehållet",
  "da": "3. Abonnement = SOFTWAREN, ikke indholdet",
  "nb": "3. Abonnement = PROGRAMVAREN, ikke innholdet",
  "ar": "3. الاشتراك = البرنامج، لا المحتوى",
  "sw": "3. Usajili = PROGRAMU, si maudhui"
 },
 "tvLegalSection3Body": {
  "fr": "Tout paiement ou abonnement éventuel rémunère UNIQUEMENT l'utilisation de l'application (le lecteur et ses fonctionnalités : interface, favoris, enregistrement local, EPG…). Il ne constitue EN AUCUN CAS l'achat, la vente, la location ou la fourniture de chaînes, de flux ou de contenus.",
  "en": "Any payment or subscription pays SOLELY for the use of the application (the player and its features: interface, favourites, local recording, EPG…). Under NO circumstances does it constitute the purchase, sale, rental or supply of channels, streams or content.",
  "es": "Cualquier pago o suscripción remunera ÚNICAMENTE el uso de la aplicación (el reproductor y sus funciones: interfaz, favoritos, grabación local, EPG…). EN NINGÚN CASO constituye la compra, venta, alquiler o suministro de canales, flujos o contenidos.",
  "sv": "Eventuella betalningar eller abonnemang avser ENDAST användningen av applikationen (spelaren och dess funktioner: gränssnitt, favoriter, lokal inspelning, EPG…). De utgör UNDER INGA omständigheter köp, försäljning, uthyrning eller tillhandahållande av kanaler, strömmar eller innehåll.",
  "da": "Enhver betaling eller ethvert abonnement dækker UDELUKKENDE brugen af applikationen (afspilleren og dens funktioner: brugerflade, favoritter, lokal optagelse, EPG…). Det udgør UNDER INGEN omstændigheder køb, salg, leje eller levering af kanaler, streams eller indhold.",
  "nb": "Enhver betaling eller ethvert abonnement dekker UTELUKKENDE bruken av applikasjonen (avspilleren og dens funksjoner: grensesnitt, favoritter, lokalt opptak, EPG…). Det utgjør IKKE UNDER NOEN omstendighet kjøp, salg, utleie eller levering av kanaler, strømmer eller innhold.",
  "ar": "أي دفعة أو اشتراك محتمل يقابل حصريًا استخدام التطبيق (المشغّل ووظائفه: الواجهة، المفضلة، التسجيل المحلي، دليل البرامج EPG…). ولا يشكّل بأي حال من الأحوال شراء قنوات أو بثوث أو محتويات أو بيعها أو تأجيرها أو توفيرها.",
  "sw": "Malipo au usajili wowote hulipia TU matumizi ya programu (kichezaji na vipengele vyake: kiolesura, vipendwa, kurekodi ndani ya kifaa, EPG…). KWA HALI YOYOTE hauwakilishi ununuzi, uuzaji, ukodishaji au utoaji wa vituo, mitiririko au maudhui."
 },
 "tvLegalSection4Title": {
  "fr": "4. Usage licite",
  "en": "4. Lawful use",
  "es": "4. Uso lícito",
  "sv": "4. Laglig användning",
  "da": "4. Lovlig brug",
  "nb": "4. Lovlig bruk",
  "ar": "4. الاستخدام القانوني",
  "sw": "4. Matumizi halali"
 },
 "tvLegalSection4Body": {
  "fr": "L'utilisateur s'engage à utiliser l'application conformément aux lois en vigueur dans son pays et à ne pas l'utiliser pour accéder à des contenus illégaux ou portant atteinte aux droits d'auteur. Toute utilisation illicite est strictement interdite et relève de la seule responsabilité de l'utilisateur.",
  "en": "The user agrees to use the application in accordance with the laws in force in their country and not to use it to access illegal or copyright-infringing content. Any unlawful use is strictly prohibited and is the sole responsibility of the user.",
  "es": "El usuario se compromete a utilizar la aplicación conforme a las leyes vigentes en su país y a no utilizarla para acceder a contenidos ilegales o que vulneren los derechos de autor. Todo uso ilícito está estrictamente prohibido y es responsabilidad exclusiva del usuario.",
  "sv": "Användaren förbinder sig att använda applikationen i enlighet med gällande lagstiftning i sitt land och att inte använda den för att få tillgång till olagligt eller upphovsrättskränkande innehåll. All olaglig användning är strängt förbjuden och sker helt på användarens eget ansvar.",
  "da": "Brugeren forpligter sig til at bruge applikationen i overensstemmelse med gældende lovgivning i sit land og til ikke at bruge den til at tilgå ulovligt eller ophavsretskrænkende indhold. Enhver ulovlig brug er strengt forbudt og sker alene på brugerens ansvar.",
  "nb": "Brukeren forplikter seg til å bruke applikasjonen i samsvar med gjeldende lover i sitt land og til ikke å bruke den for å få tilgang til ulovlig eller opphavsrettskrenkende innhold. All ulovlig bruk er strengt forbudt og skjer utelukkende på brukerens eget ansvar.",
  "ar": "يلتزم المستخدم باستخدام التطبيق وفقًا للقوانين السارية في بلده، وبعدم استخدامه للوصول إلى محتويات غير قانونية أو منتهكة لحقوق المؤلف. أي استخدام غير مشروع محظور تمامًا ويقع على مسؤولية المستخدم وحده.",
  "sw": "Mtumiaji anakubali kutumia programu kwa mujibu wa sheria zinazotumika nchini mwake na kutokuitumia kufikia maudhui haramu au yanayokiuka hakimiliki. Matumizi yoyote yasiyo halali yamepigwa marufuku kabisa na ni jukumu la mtumiaji pekee."
 },
 "tvLegalSection5Title": {
  "fr": "5. Contenus tiers — absence de responsabilité",
  "en": "5. Third-party content — no liability",
  "es": "5. Contenidos de terceros — exención de responsabilidad",
  "sv": "5. Tredjepartsinnehåll — ansvarsfrihet",
  "da": "5. Tredjepartsindhold — ansvarsfraskrivelse",
  "nb": "5. Tredjepartsinnhold — ansvarsfraskrivelse",
  "ar": "5. محتويات الأطراف الثالثة — إخلاء المسؤولية",
  "sw": "5. Maudhui ya wahusika wengine — kutokuwepo kwa dhima"
 },
 "tvLegalSection5Body": {
  "fr": "L'éditeur n'a aucun contrôle sur les contenus tiers accessibles via les sources fournies par l'utilisateur et ne saurait en être tenu responsable. Il ne garantit ni la disponibilité, ni la légalité, ni la qualité de ces contenus.",
  "en": "The publisher has no control over third-party content accessible through the sources supplied by the user and cannot be held liable for it. It guarantees neither the availability, nor the legality, nor the quality of such content.",
  "es": "El editor no tiene ningún control sobre los contenidos de terceros accesibles a través de las fuentes proporcionadas por el usuario y no puede ser considerado responsable de ellos. No garantiza ni la disponibilidad, ni la legalidad, ni la calidad de dichos contenidos.",
  "sv": "Utgivaren har ingen kontroll över tredjepartsinnehåll som är tillgängligt via de källor användaren tillhandahåller och kan inte hållas ansvarig för det. Utgivaren garanterar varken tillgängligheten, lagligheten eller kvaliteten på detta innehåll.",
  "da": "Udgiveren har ingen kontrol over tredjepartsindhold, der er tilgængeligt via de kilder, brugeren leverer, og kan ikke holdes ansvarlig herfor. Udgiveren garanterer hverken tilgængeligheden, lovligheden eller kvaliteten af dette indhold.",
  "nb": "Utgiveren har ingen kontroll over tredjepartsinnhold som er tilgjengelig via kildene brukeren leverer, og kan ikke holdes ansvarlig for det. Utgiveren garanterer verken tilgjengeligheten, lovligheten eller kvaliteten på dette innholdet.",
  "ar": "لا يملك الناشر أي سيطرة على محتويات الأطراف الثالثة التي يمكن الوصول إليها عبر المصادر التي يوفرها المستخدم، ولا يمكن تحميله المسؤولية عنها. وهو لا يضمن توفر هذه المحتويات ولا قانونيتها ولا جودتها.",
  "sw": "Mchapishaji hana udhibiti wowote juu ya maudhui ya wahusika wengine yanayofikiwa kupitia vyanzo vinavyotolewa na mtumiaji na hawezi kuwajibishwa kwayo. Hahakikishi upatikanaji, uhalali wala ubora wa maudhui hayo."
 },
 "tvLegalSection6Title": {
  "fr": "6. Propriété intellectuelle & réclamations",
  "en": "6. Intellectual property & claims",
  "es": "6. Propiedad intelectual y reclamaciones",
  "sv": "6. Immateriella rättigheter & anspråk",
  "da": "6. Immaterielle rettigheder & krav",
  "nb": "6. Immaterielle rettigheter & krav",
  "ar": "6. الملكية الفكرية والمطالبات",
  "sw": "6. Miliki bunifu na malalamiko"
 },
 "tvLegalSection6Body": {
  "fr": "Toutes les marques, logos et contenus appartiennent à leurs propriétaires respectifs. L'application n'hébergeant aucun contenu, toute réclamation relative à des droits d'auteur doit être adressée au fournisseur de la source concernée.",
  "en": "All trademarks, logos and content belong to their respective owners. As the application hosts no content, any copyright claim must be addressed to the provider of the source concerned.",
  "es": "Todas las marcas, logotipos y contenidos pertenecen a sus respectivos propietarios. Dado que la aplicación no aloja ningún contenido, toda reclamación relativa a derechos de autor debe dirigirse al proveedor de la fuente en cuestión.",
  "sv": "Alla varumärken, logotyper och allt innehåll tillhör sina respektive ägare. Eftersom applikationen inte lagrar något innehåll ska alla upphovsrättsanspråk riktas till leverantören av den berörda källan.",
  "da": "Alle varemærker, logoer og alt indhold tilhører deres respektive ejere. Da applikationen ikke hoster noget indhold, skal ethvert krav vedrørende ophavsret rettes til udbyderen af den pågældende kilde.",
  "nb": "Alle varemerker, logoer og alt innhold tilhører sine respektive eiere. Ettersom applikasjonen ikke lagrer noe innhold, må ethvert krav knyttet til opphavsrett rettes til leverandøren av den aktuelle kilden.",
  "ar": "جميع العلامات التجارية والشعارات والمحتويات ملك لأصحابها. وبما أن التطبيق لا يستضيف أي محتوى، فإن أي مطالبة تتعلق بحقوق المؤلف يجب توجيهها إلى مزوّد المصدر المعني.",
  "sw": "Chapa zote za biashara, nembo na maudhui ni mali ya wamiliki wake husika. Kwa kuwa programu haihifadhi maudhui yoyote, malalamiko yoyote kuhusu hakimiliki yanapaswa kuelekezwa kwa mtoa huduma wa chanzo husika."
 },
 "tvLegalSection7Title": {
  "fr": "7. Fourniture « en l'état »",
  "en": "7. Provided \"as is\"",
  "es": "7. Suministro « tal cual »",
  "sv": "7. Tillhandahålls \"i befintligt skick\"",
  "da": "7. Leveres \"som den er\"",
  "nb": "7. Leveres \"som den er\"",
  "ar": "7. التوفير «كما هو»",
  "sw": "7. Inatolewa \"kama ilivyo\""
 },
 "tvLegalSection7Body": {
  "fr": "L'application est fournie « telle quelle », sans garantie de disponibilité continue ni d'absence d'erreurs. L'éditeur peut faire évoluer ou suspendre tout ou partie des fonctionnalités.",
  "en": "The application is provided \"as is\", with no guarantee of continuous availability or freedom from errors. The publisher may modify or suspend all or part of its features.",
  "es": "La aplicación se suministra « tal cual », sin garantía de disponibilidad continua ni de ausencia de errores. El editor puede modificar o suspender la totalidad o parte de las funcionalidades.",
  "sv": "Applikationen tillhandahålls \"i befintligt skick\", utan garanti för kontinuerlig tillgänglighet eller frånvaro av fel. Utgivaren kan ändra eller stänga av alla eller delar av funktionerna.",
  "da": "Applikationen leveres \"som den er\", uden garanti for kontinuerlig tilgængelighed eller fravær af fejl. Udgiveren kan ændre eller suspendere alle eller dele af funktionerne.",
  "nb": "Applikasjonen leveres \"som den er\", uten garanti for kontinuerlig tilgjengelighet eller fravær av feil. Utgiveren kan endre eller suspendere alle eller deler av funksjonene.",
  "ar": "يُوفَّر التطبيق «كما هو»، دون ضمان استمرارية التوفر أو خلوّه من الأخطاء. ويجوز للناشر تطوير الوظائف كليًا أو جزئيًا أو تعليقها.",
  "sw": "Programu inatolewa \"kama ilivyo\", bila hakikisho la upatikanaji endelevu wala kutokuwepo kwa makosa. Mchapishaji anaweza kubadilisha au kusitisha vipengele vyote au sehemu yake."
 },
 "tvLegalSection8Title": {
  "fr": "8. Données personnelles",
  "en": "8. Personal data",
  "es": "8. Datos personales",
  "sv": "8. Personuppgifter",
  "da": "8. Personoplysninger",
  "nb": "8. Personopplysninger",
  "ar": "8. البيانات الشخصية",
  "sw": "8. Data za kibinafsi"
 },
 "tvLegalSection8Body": {
  "fr": "Un identifiant technique d'appareil est utilisé pour la gestion de la licence/essai et le support. Détails : app.7themotion.com/privacy.",
  "en": "A technical device identifier is used for licence/trial management and support. Details: app.7themotion.com/privacy.",
  "es": "Se utiliza un identificador técnico del dispositivo para la gestión de la licencia/prueba y el soporte. Detalles: app.7themotion.com/privacy.",
  "sv": "En teknisk enhetsidentifierare används för hantering av licens/provperiod och support. Mer information: app.7themotion.com/privacy.",
  "da": "En teknisk enhedsidentifikator bruges til administration af licens/prøveperiode og support. Detaljer: app.7themotion.com/privacy.",
  "nb": "En teknisk enhetsidentifikator brukes til administrasjon av lisens/prøveperiode og støtte. Detaljer: app.7themotion.com/privacy.",
  "ar": "يُستخدم معرّف تقني للجهاز لإدارة الترخيص/الفترة التجريبية وللدعم. التفاصيل: app.7themotion.com/privacy.",
  "sw": "Kitambulisho cha kiufundi cha kifaa hutumika kwa usimamizi wa leseni/jaribio na usaidizi. Maelezo: app.7themotion.com/privacy."
 },
 "tvLegalSection9Title": {
  "fr": "9. Acceptation",
  "en": "9. Acceptance",
  "es": "9. Aceptación",
  "sv": "9. Godkännande",
  "da": "9. Accept",
  "nb": "9. Aksept",
  "ar": "9. القبول",
  "sw": "9. Kukubali"
 },
 "tvLegalSection9Body": {
  "fr": "En installant ou en utilisant cette application, l'utilisateur reconnaît avoir lu et accepté les présentes conditions. Version complète en ligne : app.7themotion.com/terms",
  "en": "By installing or using this application, the user acknowledges having read and accepted these terms. Full version online: app.7themotion.com/terms",
  "es": "Al instalar o utilizar esta aplicación, el usuario reconoce haber leído y aceptado las presentes condiciones. Versión completa en línea: app.7themotion.com/terms",
  "sv": "Genom att installera eller använda den här applikationen bekräftar användaren att han eller hon har läst och godkänt dessa villkor. Fullständig version online: app.7themotion.com/terms",
  "da": "Ved at installere eller bruge denne applikation bekræfter brugeren at have læst og accepteret disse betingelser. Fuld version online: app.7themotion.com/terms",
  "nb": "Ved å installere eller bruke denne applikasjonen bekrefter brukeren å ha lest og akseptert disse vilkårene. Fullstendig versjon på nett: app.7themotion.com/terms",
  "ar": "بتثبيت هذا التطبيق أو استخدامه، يقرّ المستخدم بأنه قرأ هذه الشروط ووافق عليها. النسخة الكاملة على الإنترنت: app.7themotion.com/terms",
  "sw": "Kwa kusakinisha au kutumia programu hii, mtumiaji anakiri kuwa amesoma na kukubali masharti haya. Toleo kamili mtandaoni: app.7themotion.com/terms"
 },
 "legalDisclaimerTitle": {
  "fr": "Mention légale",
  "en": "Legal notice",
  "es": "Aviso legal",
  "sv": "Juridisk information",
  "da": "Juridisk meddelelse",
  "nb": "Juridisk merknad",
  "ar": "إشعار قانوني",
  "sw": "Taarifa ya kisheria"
 },
 "legalDisclaimerCompactBody": {
  "fr": "Lecteur multimédia uniquement. Cette application ne vend, n'héberge et ne fournit aucun contenu, flux, chaîne, playlist (M3U) ni abonnement IPTV. Vous fournissez votre propre source et restez seul responsable de son contenu.",
  "en": "Multimedia player only. This application does not sell, host or provide any content, stream, channel, playlist (M3U) or IPTV subscription. You supply your own source and remain solely responsible for its content.",
  "es": "Solo un reproductor multimedia. Esta aplicación no vende, no aloja ni proporciona ningún contenido, flujo, canal, lista de reproducción (M3U) ni suscripción IPTV. Usted proporciona su propia fuente y es el único responsable de su contenido.",
  "sv": "Endast en multimediaspelare. Den här applikationen säljer, lagrar eller tillhandahåller inget innehåll, inga strömmar, kanaler, spellistor (M3U) eller IPTV-abonnemang. Du tillhandahåller din egen källa och är ensam ansvarig för dess innehåll.",
  "da": "Kun en multimedieafspiller. Denne applikation sælger, hoster eller leverer intet indhold, ingen streams, kanaler, afspilningslister (M3U) eller IPTV-abonnementer. Du leverer selv din egen kilde og er alene ansvarlig for dens indhold.",
  "nb": "Kun en multimedieavspiller. Denne applikasjonen selger, lagrer eller leverer ikke noe innhold, ingen strømmer, kanaler, spillelister (M3U) eller IPTV-abonnementer. Du leverer din egen kilde og er alene ansvarlig for innholdet i den.",
  "ar": "مشغّل وسائط متعددة فقط. هذا التطبيق لا يبيع ولا يستضيف ولا يوفر أي محتوى أو بث أو قناة أو قائمة تشغيل (M3U) أو اشتراك IPTV. أنت توفر مصدرك الخاص وتظل وحدك المسؤول عن محتواه.",
  "sw": "Kichezaji cha medianuwai pekee. Programu hii haiuzi, haihifadhi wala haitoi maudhui, mtiririko, kituo, orodha ya kucheza (M3U) au usajili wa IPTV. Wewe hutoa chanzo chako mwenyewe na unabaki kuwa mwenye jukumu pekee kwa maudhui yake."
 },
 "legalDisclaimerFullPara1": {
  "fr": "Cette application est un LECTEUR multimédia générique, au même titre qu'un lecteur vidéo classique. Elle ne vend pas, n'héberge pas, ne distribue pas et ne fournit AUCUN contenu : ni flux, ni chaîne, ni film, ni playlist (M3U / M3U8), ni abonnement IPTV.",
  "en": "This application is a generic multimedia PLAYER, just like a standard video player. It does not sell, host, distribute or provide ANY content: no streams, channels, movies, playlists (M3U / M3U8) or IPTV subscriptions.",
  "es": "Esta aplicación es un REPRODUCTOR multimedia genérico, al igual que un reproductor de vídeo clásico. No vende, no aloja, no distribuye ni proporciona NINGÚN contenido: ni flujos, ni canales, ni películas, ni listas de reproducción (M3U / M3U8), ni suscripciones IPTV.",
  "sv": "Den här applikationen är en generisk multimediaSPELARE, precis som en vanlig videospelare. Den säljer, lagrar, distribuerar eller tillhandahåller INGET innehåll: inga strömmar, kanaler, filmer, spellistor (M3U / M3U8) eller IPTV-abonnemang.",
  "da": "Denne applikation er en generisk multimedieAFSPILLER, på samme måde som en almindelig videoafspiller. Den sælger, hoster, distribuerer eller leverer INTET indhold: hverken streams, kanaler, film, afspilningslister (M3U / M3U8) eller IPTV-abonnementer.",
  "nb": "Denne applikasjonen er en generisk multimedieAVSPILLER, på samme måte som en vanlig videoavspiller. Den selger, lagrer, distribuerer eller leverer IKKE noe innhold: verken strømmer, kanaler, filmer, spillelister (M3U / M3U8) eller IPTV-abonnementer.",
  "ar": "هذا التطبيق مشغّل وسائط متعددة عام، شأنه شأن أي مشغّل فيديو تقليدي. وهو لا يبيع ولا يستضيف ولا يوزّع ولا يوفر أي محتوى: لا بثوثًا ولا قنوات ولا أفلامًا ولا قوائم تشغيل (M3U / M3U8) ولا اشتراكات IPTV.",
  "sw": "Programu hii ni KICHEZAJI cha jumla cha medianuwai, sawa na kichezaji cha kawaida cha video. Haiuzi, haihifadhi, haisambazi wala haitoi maudhui YOYOTE: si mitiririko, si vituo, si filamu, si orodha za kucheza (M3U / M3U8), wala usajili wa IPTV."
 },
 "legalDisclaimerFullPara2": {
  "fr": "Aucune source, aucun lien et aucune liste de chaînes ne sont fournis ou pré-installés. Pour l'utiliser, vous devez saisir vos propres identifiants (Xtream ou URL M3U) obtenus auprès du fournisseur de votre choix.",
  "en": "No source, link or channel list is provided or pre-installed. To use it, you must enter your own credentials (Xtream or M3U URL) obtained from the provider of your choice.",
  "es": "No se proporciona ni se preinstala ninguna fuente, enlace o lista de canales. Para utilizarla, debe introducir sus propias credenciales (Xtream o URL M3U) obtenidas del proveedor de su elección.",
  "sv": "Ingen källa, ingen länk och ingen kanallista tillhandahålls eller är förinstallerad. För att använda den måste du ange dina egna uppgifter (Xtream eller M3U-URL) som du fått från valfri leverantör.",
  "da": "Ingen kilde, intet link og ingen kanalliste leveres eller er forudinstalleret. For at bruge den skal du indtaste dine egne oplysninger (Xtream eller M3U-URL), som du har fået fra en udbyder efter eget valg.",
  "nb": "Ingen kilde, ingen lenke og ingen kanalliste leveres eller er forhåndsinstallert. For å bruke den må du oppgi dine egne opplysninger (Xtream eller M3U-URL) anskaffet hos en leverandør du selv velger.",
  "ar": "لا يتم توفير أو تثبيت أي مصدر أو رابط أو قائمة قنوات مسبقًا. ولاستخدام التطبيق، يجب إدخال بيانات الاعتماد الخاصة بك (Xtream أو رابط M3U) التي حصلت عليها من المزوّد الذي تختاره.",
  "sw": "Hakuna chanzo, kiungo wala orodha ya vituo inayotolewa au kusakinishwa awali. Ili kuitumia, lazima uweke vitambulisho vyako mwenyewe (Xtream au URL ya M3U) ulivyopata kutoka kwa mtoa huduma unayemchagua."
 },
 "legalDisclaimerFullPara3": {
  "fr": "Vous êtes seul responsable des sources que vous ajoutez et de leur légalité dans votre pays. Les marques, logos et contenus appartiennent à leurs propriétaires respectifs. Toute question sur les flux ou abonnements doit être adressée à votre fournisseur — jamais à l'éditeur de l'application.",
  "en": "You are solely responsible for the sources you add and for their legality in your country. Trademarks, logos and content belong to their respective owners. Any question about streams or subscriptions must be addressed to your provider — never to the application's publisher.",
  "es": "Usted es el único responsable de las fuentes que añade y de su legalidad en su país. Las marcas, logotipos y contenidos pertenecen a sus respectivos propietarios. Cualquier pregunta sobre flujos o suscripciones debe dirigirse a su proveedor — nunca al editor de la aplicación.",
  "sv": "Du är ensam ansvarig för de källor du lägger till och för deras laglighet i ditt land. Varumärken, logotyper och innehåll tillhör sina respektive ägare. Alla frågor om strömmar eller abonnemang ska ställas till din leverantör — aldrig till applikationens utgivare.",
  "da": "Du er alene ansvarlig for de kilder, du tilføjer, og for deres lovlighed i dit land. Varemærker, logoer og indhold tilhører deres respektive ejere. Alle spørgsmål om streams eller abonnementer skal rettes til din udbyder — aldrig til applikationens udgiver.",
  "nb": "Du er alene ansvarlig for kildene du legger til og for at de er lovlige i ditt land. Varemerker, logoer og innhold tilhører sine respektive eiere. Alle spørsmål om strømmer eller abonnementer må rettes til din leverandør — aldri til applikasjonens utgiver.",
  "ar": "أنت وحدك المسؤول عن المصادر التي تضيفها وعن قانونيتها في بلدك. العلامات التجارية والشعارات والمحتويات ملك لأصحابها. وأي سؤال حول البثوث أو الاشتراكات يجب توجيهه إلى مزوّدك — وليس أبدًا إلى ناشر التطبيق.",
  "sw": "Wewe pekee ndiye mwenye jukumu kwa vyanzo unavyoongeza na kwa uhalali wake nchini mwako. Chapa za biashara, nembo na maudhui ni mali ya wamiliki wake husika. Swali lolote kuhusu mitiririko au usajili linapaswa kuelekezwa kwa mtoa huduma wako — kamwe si kwa mchapishaji wa programu."
 },
 "tvParentalEnterCode": {
  "fr": "Entre le code parental",
  "en": "Enter the parental code",
  "es": "Introduce el código parental",
  "sv": "Ange föräldrakoden",
  "da": "Indtast forældrekoden",
  "nb": "Skriv inn foreldrekoden",
  "ar": "أدخل رمز الوالدين",
  "sw": "Weka msimbo wa wazazi"
 },
 "tvParentalCurrentCode": {
  "fr": "Code actuel",
  "en": "Current code",
  "es": "Código actual",
  "sv": "Nuvarande kod",
  "da": "Nuværende kode",
  "nb": "Nåværende kode",
  "ar": "الرمز الحالي",
  "sw": "Msimbo wa sasa"
 },
 "tvParentalIntro": {
  "fr": "Le Mode Enfants masque automatiquement toutes les chaînes Adulte. Sa désactivation et le changement de code demandent le code parental.",
  "en": "Kids Mode automatically hides all Adult channels. Turning it off and changing the code require the parental code.",
  "es": "El Modo Niños oculta automáticamente todos los canales para adultos. Desactivarlo y cambiar el código requieren el código parental.",
  "sv": "Barnläget döljer automatiskt alla vuxenkanaler. Att stänga av det och byta kod kräver föräldrakoden.",
  "da": "Børnetilstand skjuler automatisk alle voksenkanaler. At slå den fra og ændre koden kræver forældrekoden.",
  "nb": "Barnemodus skjuler automatisk alle voksenkanaler. Å slå den av og endre koden krever foreldrekoden.",
  "ar": "وضع الأطفال يخفي تلقائيًا كل قنوات الكبار. يتطلب إيقافه وتغيير الرمز إدخال رمز الوالدين.",
  "sw": "Hali ya Watoto huficha kiotomatiki chaneli zote za watu wazima. Kuizima na kubadilisha msimbo kunahitaji msimbo wa wazazi."
 },
 "tvParentalKidsMode": {
  "fr": "Mode Enfants",
  "en": "Kids Mode",
  "es": "Modo Niños",
  "sv": "Barnläge",
  "da": "Børnetilstand",
  "nb": "Barnemodus",
  "ar": "وضع الأطفال",
  "sw": "Hali ya Watoto"
 },
 "tvParentalKidsOn": {
  "fr": "Activé — le contenu Adulte est masqué.",
  "en": "On — Adult content is hidden.",
  "es": "Activado: el contenido para adultos está oculto.",
  "sv": "På — vuxeninnehåll är dolt.",
  "da": "Til — voksenindhold er skjult.",
  "nb": "På — voksent innhold er skjult.",
  "ar": "مفعّل — محتوى الكبار مخفي.",
  "sw": "Imewashwa — maudhui ya watu wazima yamefichwa."
 },
 "tvParentalKidsOff": {
  "fr": "Désactivé — toutes les chaînes sont visibles.",
  "en": "Off — all channels are visible.",
  "es": "Desactivado: todos los canales están visibles.",
  "sv": "Av — alla kanaler visas.",
  "da": "Fra — alle kanaler er synlige.",
  "nb": "Av — alle kanaler er synlige.",
  "ar": "معطّل — كل القنوات ظاهرة.",
  "sw": "Imezimwa — chaneli zote zinaonekana."
 },
 "tvParentalPinCard": {
  "fr": "Code parental",
  "en": "Parental code",
  "es": "Código parental",
  "sv": "Föräldrakod",
  "da": "Forældrekode",
  "nb": "Foreldrekode",
  "ar": "رمز الوالدين",
  "sw": "Msimbo wa wazazi"
 },
 "tvParentalDefaultPinWarning": {
  "fr": "Tu utilises encore le code par défaut 0000. Change-le pour protéger le Mode Enfants.",
  "en": "You're still using the default code 0000. Change it to protect Kids Mode.",
  "es": "Todavía usas el código predeterminado 0000. Cámbialo para proteger el Modo Niños.",
  "sv": "Du använder fortfarande standardkoden 0000. Byt den för att skydda Barnläget.",
  "da": "Du bruger stadig standardkoden 0000. Skift den for at beskytte Børnetilstand.",
  "nb": "Du bruker fortsatt standardkoden 0000. Bytt den for å beskytte Barnemodus.",
  "ar": "ما زلت تستخدم الرمز الافتراضي 0000. غيّره لحماية وضع الأطفال.",
  "sw": "Bado unatumia msimbo chaguomsingi 0000. Ubadilishe ili kulinda Hali ya Watoto."
 },
 "tvParentalCustomPinSet": {
  "fr": "Un code personnalisé est en place.",
  "en": "A custom code is set.",
  "es": "Hay un código personalizado configurado.",
  "sv": "En egen kod är inställd.",
  "da": "En personlig kode er sat.",
  "nb": "En egen kode er satt.",
  "ar": "تم تعيين رمز مخصص.",
  "sw": "Msimbo maalum umewekwa."
 },
 "tvParentalChangePin": {
  "fr": "Changer le code PIN",
  "en": "Change PIN code",
  "es": "Cambiar el código PIN",
  "sv": "Byt PIN-kod",
  "da": "Skift PIN-kode",
  "nb": "Endre PIN-kode",
  "ar": "تغيير رمز PIN",
  "sw": "Badilisha msimbo wa PIN"
 },
 "tvParentalPinSubtitle": {
  "fr": "Code parental à 4 chiffres",
  "en": "4-digit parental code",
  "es": "Código parental de 4 dígitos",
  "sv": "Fyrsiffrig föräldrakod",
  "da": "Firecifret forældrekode",
  "nb": "Firesifret foreldrekode",
  "ar": "رمز والدين من 4 أرقام",
  "sw": "Msimbo wa wazazi wa tarakimu 4"
 },
 "tvParentalNewPin": {
  "fr": "Nouveau code",
  "en": "New code",
  "es": "Código nuevo",
  "sv": "Ny kod",
  "da": "Ny kode",
  "nb": "Ny kode",
  "ar": "رمز جديد",
  "sw": "Msimbo mpya"
 },
 "tvParentalNewPinSubtitle": {
  "fr": "Choisis 4 chiffres, puis confirme",
  "en": "Pick 4 digits, then confirm",
  "es": "Elige 4 dígitos y confírmalos",
  "sv": "Välj 4 siffror och bekräfta",
  "da": "Vælg 4 cifre, og bekræft",
  "nb": "Velg 4 sifre, og bekreft",
  "ar": "اختر 4 أرقام ثم أكّدها",
  "sw": "Chagua tarakimu 4, kisha thibitisha"
 },
 "tvParentalPinMismatch": {
  "fr": "Les deux codes ne correspondent pas.",
  "en": "The two codes don't match.",
  "es": "Los dos códigos no coinciden.",
  "sv": "Koderna stämmer inte överens.",
  "da": "De to koder er ikke ens.",
  "nb": "De to kodene er ikke like.",
  "ar": "الرمزان غير متطابقين.",
  "sw": "Misimbo hiyo miwili hailingani."
 },
 "tvParentalConfirmPin": {
  "fr": "Confirme le code",
  "en": "Confirm the code",
  "es": "Confirma el código",
  "sv": "Bekräfta koden",
  "da": "Bekræft koden",
  "nb": "Bekreft koden",
  "ar": "أكّد الرمز",
  "sw": "Thibitisha msimbo"
 },
 "tvRecordingsDeleteTitle": {
  "fr": "Supprimer ?",
  "en": "Delete?",
  "es": "¿Eliminar?",
  "sv": "Ta bort?",
  "da": "Slet?",
  "nb": "Slette?",
  "ar": "حذف؟",
  "sw": "Ufute?"
 },
 "tvRecordingsDeleteBody": {
  "fr": "Supprimer définitivement « {name} » ?",
  "en": "Permanently delete \"{name}\"?",
  "es": "¿Eliminar definitivamente «{name}»?",
  "sv": "Ta bort \"{name}\" permanent?",
  "da": "Slet \"{name}\" permanent?",
  "nb": "Slette \"{name}\" permanent?",
  "ar": "هل تريد حذف \"{name}\" نهائيًا؟",
  "sw": "Ufute \"{name}\" kabisa?"
 },
 "tvGuideTimeGrid": {
  "fr": "Grille horaire",
  "en": "Time grid",
  "es": "Parrilla horaria",
  "sv": "Tablå",
  "da": "Programoversigt",
  "nb": "Programoversikt",
  "ar": "الشبكة الزمنية",
  "sw": "Gridi ya ratiba"
 },
 "tvGuideUpNext": {
  "fr": "À suivre · {title}",
  "en": "Up next · {title}",
  "es": "A continuación · {title}",
  "sv": "Härnäst · {title}",
  "da": "Næste · {title}",
  "nb": "Neste · {title}",
  "ar": "التالي · {title}",
  "sw": "Inayofuata · {title}"
 },
 "tvPlayerRecStarted": {
  "fr": "Enregistrement en cours…",
  "en": "Recording…",
  "es": "Grabando…",
  "sv": "Spelar in…",
  "da": "Optager…",
  "nb": "Tar opp…",
  "ar": "جارٍ التسجيل…",
  "sw": "Inarekodi…"
 },
 "tvPlayerRecError": {
  "fr": "Erreur enregistrement",
  "en": "Recording error",
  "es": "Error de grabación",
  "sv": "Inspelningsfel",
  "da": "Optagefejl",
  "nb": "Opptaksfeil",
  "ar": "خطأ في التسجيل",
  "sw": "Hitilafu ya kurekodi"
 },
 "tvPlayerRecSaved": {
  "fr": "Enregistrement sauvegardé ({size})",
  "en": "Recording saved ({size})",
  "es": "Grabación guardada ({size})",
  "sv": "Inspelning sparad ({size})",
  "da": "Optagelse gemt ({size})",
  "nb": "Opptak lagret ({size})",
  "ar": "تم حفظ التسجيل ({size})",
  "sw": "Rekodi imehifadhiwa ({size})"
 },
 "tvPlayerRecEmpty": {
  "fr": "Enregistrement vide",
  "en": "Empty recording",
  "es": "Grabación vacía",
  "sv": "Tom inspelning",
  "da": "Tom optagelse",
  "nb": "Tomt opptak",
  "ar": "تسجيل فارغ",
  "sw": "Rekodi tupu"
 },
 "tvPlayerStillWatching": {
  "fr": "Tu regardes encore ?",
  "en": "Still watching?",
  "es": "¿Sigues ahí?",
  "sv": "Tittar du fortfarande?",
  "da": "Ser du stadig med?",
  "nb": "Ser du fortsatt på?",
  "ar": "هل ما زلت تشاهد؟",
  "sw": "Bado unatazama?"
 },
 "tvPlayerStillWatchingHint": {
  "fr": "Appuie sur n'importe quelle touche pour continuer.",
  "en": "Press any button to keep watching.",
  "es": "Pulsa cualquier botón para continuar.",
  "sv": "Tryck på valfri knapp för att fortsätta.",
  "da": "Tryk på en vilkårlig knap for at fortsætte.",
  "nb": "Trykk på en hvilken som helst knapp for å fortsette.",
  "ar": "اضغط أي زر للمتابعة.",
  "sw": "Bonyeza kitufe chochote ili kuendelea."
 },
 "tvPlayerStop": {
  "fr": "Stop",
  "en": "Stop",
  "es": "Detener",
  "sv": "Stopp",
  "da": "Stop",
  "nb": "Stopp",
  "ar": "إيقاف",
  "sw": "Simamisha"
 },
 "tvPlayerFavorite": {
  "fr": "Favori",
  "en": "Favorite",
  "es": "Favorito",
  "sv": "Favorit",
  "da": "Favorit",
  "nb": "Favoritt",
  "ar": "المفضلة",
  "sw": "Kipendwa"
 },
 "tvPlayerMulti": {
  "fr": "Multi",
  "en": "Multi",
  "es": "Multi",
  "sv": "Multi",
  "da": "Multi",
  "nb": "Multi",
  "ar": "متعدد",
  "sw": "Multi"
 },
 "tvSettingsSources": {
  "fr": "Mes sources (ajouter / activer / supprimer)",
  "en": "My sources (add / activate / delete)",
  "es": "Mis fuentes (añadir / activar / eliminar)",
  "sv": "Mina källor (lägg till / aktivera / ta bort)",
  "da": "Mine kilder (tilføj / aktivér / slet)",
  "nb": "Mine kilder (legg til / aktiver / slett)",
  "ar": "مصادري (إضافة / تفعيل / حذف)",
  "sw": "Vyanzo vyangu (ongeza / washa / futa)"
 },
 "tvSettingsFamily": {
  "fr": "Abonnement Famille (partager, 5 appareils)",
  "en": "Family plan (share, 5 devices)",
  "es": "Suscripción Familia (compartir, 5 dispositivos)",
  "sv": "Familjeabonnemang (dela, 5 enheter)",
  "da": "Familieabonnement (del, 5 enheder)",
  "nb": "Familieabonnement (del, 5 enheter)",
  "ar": "اشتراك العائلة (مشاركة، 5 أجهزة)",
  "sw": "Usajili wa Familia (shiriki, vifaa 5)"
 },
 "tvSettingsProfiles": {
  "fr": "Profils (chacun son univers)",
  "en": "Profiles (a space for everyone)",
  "es": "Perfiles (cada uno su universo)",
  "sv": "Profiler (var och en sin värld)",
  "da": "Profiler (hver sit univers)",
  "nb": "Profiler (hver sitt univers)",
  "ar": "الملفات الشخصية (لكلٍّ عالمه)",
  "sw": "Wasifu (kila mtu na ulimwengu wake)"
 },
 "tvSettingsDisclaimer": {
  "fr": "Cette application est un LECTEUR multimédia. Elle ne vend, ne fournit et n'héberge aucune chaîne, aucun flux ni aucun lien M3U. Le contenu est fourni par l'utilisateur, seul responsable de sa licéité.",
  "en": "This app is a media PLAYER. It does not sell, provide or host any channel, stream or M3U link. Content is supplied by the user, who is solely responsible for its legality.",
  "es": "Esta aplicación es un REPRODUCTOR multimedia. No vende, no proporciona ni aloja ningún canal, flujo ni enlace M3U. El contenido lo aporta el usuario, único responsable de su legalidad.",
  "sv": "Den här appen är en mediaSPELARE. Den säljer, tillhandahåller eller lagrar inga kanaler, strömmar eller M3U-länkar. Innehållet tillhandahålls av användaren, som ensam ansvarar för att det är lagligt.",
  "da": "Denne app er en medieAFSPILLER. Den sælger, leverer eller hoster ingen kanaler, streams eller M3U-links. Indholdet leveres af brugeren, som alene er ansvarlig for dets lovlighed.",
  "nb": "Denne appen er en medieSPILLER. Den verken selger, leverer eller er vert for noen kanaler, strømmer eller M3U-lenker. Innholdet leveres av brukeren, som alene er ansvarlig for at det er lovlig.",
  "ar": "هذا التطبيق مجرد مشغّل وسائط. لا يبيع أو يوفر أو يستضيف أي قناة أو بث أو رابط M3U. المحتوى يوفره المستخدم وهو المسؤول الوحيد عن قانونيته.",
  "sw": "Programu hii ni KICHEZESHI cha maudhui tu. Haiuzi, haitoi wala kuhifadhi chaneli yoyote, mtiririko wala kiungo cha M3U. Maudhui hutolewa na mtumiaji, ambaye ndiye pekee anayewajibika kisheria."
 },
 "tvFilmsEmpty": {
  "fr": "Aucun film pour le moment.\n(Source sans VOD, ou compte M3U sans films.)",
  "en": "No movies yet.\n(Source without VOD, or M3U account without movies.)",
  "es": "Aún no hay películas.\n(Fuente sin VOD o cuenta M3U sin películas.)",
  "sv": "Inga filmer ännu.\n(Källa utan VOD, eller M3U-konto utan filmer.)",
  "da": "Ingen film endnu.\n(Kilde uden VOD, eller M3U-konto uden film.)",
  "nb": "Ingen filmer ennå.\n(Kilde uten VOD, eller M3U-konto uten filmer.)",
  "ar": "لا توجد أفلام بعد.\n(مصدر بدون VOD، أو حساب M3U بدون أفلام.)",
  "sw": "Hakuna filamu kwa sasa.\n(Chanzo bila VOD, au akaunti ya M3U isiyo na filamu.)"
 },
 "tvSeriesSeason": {
  "fr": "Saison {n}",
  "en": "Season {n}",
  "es": "Temporada {n}",
  "sv": "Säsong {n}",
  "da": "Sæson {n}",
  "nb": "Sesong {n}",
  "ar": "الموسم {n}",
  "sw": "Msimu wa {n}"
 },
 "tvLiveForYou": {
  "fr": "✨ Pour vous",
  "en": "✨ For you",
  "es": "✨ Para ti",
  "sv": "✨ För dig",
  "da": "✨ Til dig",
  "nb": "✨ For deg",
  "ar": "✨ لك",
  "sw": "✨ Kwa ajili yako"
 },
 "tvLiveAllChannels": {
  "fr": "📺 Toutes",
  "en": "📺 All",
  "es": "📺 Todas",
  "sv": "📺 Alla",
  "da": "📺 Alle",
  "nb": "📺 Alle",
  "ar": "📺 الكل",
  "sw": "📺 Zote"
 },
 "tvLiveNowPlaying": {
  "fr": "EN CE MOMENT · {title}",
  "en": "ON NOW · {title}",
  "es": "AHORA · {title}",
  "sv": "JUST NU · {title}",
  "da": "LIGE NU · {title}",
  "nb": "AKKURAT NÅ · {title}",
  "ar": "الآن · {title}",
  "sw": "SASA HIVI · {title}"
 },
 "tvLiveExpiryToday": {
  "fr": "aujourd'hui",
  "en": "today",
  "es": "hoy",
  "sv": "idag",
  "da": "i dag",
  "nb": "i dag",
  "ar": "اليوم",
  "sw": "leo"
 },
 "tvLiveExpiryTomorrow": {
  "fr": "demain",
  "en": "tomorrow",
  "es": "mañana",
  "sv": "imorgon",
  "da": "i morgen",
  "nb": "i morgen",
  "ar": "غدًا",
  "sw": "kesho"
 },
 "tvLiveExpiryInDays": {
  "fr": "dans {days} jours",
  "en": "in {days} days",
  "es": "en {days} días",
  "sv": "om {days} dagar",
  "da": "om {days} dage",
  "nb": "om {days} dager",
  "ar": "خلال {days} أيام",
  "sw": "baada ya siku {days}"
 },
 "tvLiveExpiryBanner": {
  "fr": "Ton abonnement expire {when}. Pense à le renouveler auprès de ton revendeur pour ne pas être coupé.",
  "en": "Your subscription expires {when}. Renew it with your reseller so you don't get cut off.",
  "es": "Tu suscripción caduca {when}. Renuévala con tu revendedor para no quedarte sin servicio.",
  "sv": "Ditt abonnemang går ut {when}. Förnya det hos din återförsäljare så att du inte blir avstängd.",
  "da": "Dit abonnement udløber {when}. Forny det hos din forhandler, så du ikke bliver afbrudt.",
  "nb": "Abonnementet ditt utløper {when}. Forny det hos forhandleren din så du ikke blir avstengt.",
  "ar": "ينتهي اشتراكك {when}. جدّده لدى الموزّع حتى لا تنقطع الخدمة.",
  "sw": "Usajili wako unaisha {when}. Uhuishe kwa muuzaji wako ili usikatiwe huduma."
 },
 "settingsHelpSupport": {
  "fr": "Aide & Support",
  "en": "Help & support",
  "es": "Ayuda y soporte",
  "sv": "Hjälp & support",
  "da": "Hjælp & support",
  "nb": "Hjelp og støtte",
  "ar": "المساعدة والدعم",
  "sw": "Msaada na usaidizi"
 },
 "settingsMySubscription": {
  "fr": "Mon abonnement",
  "en": "My subscription",
  "es": "Mi suscripción",
  "sv": "Min prenumeration",
  "da": "Mit abonnement",
  "nb": "Mitt abonnement",
  "ar": "اشتراكي",
  "sw": "Usajili wangu"
 },
 "settingsBufferSubtitle": {
  "fr": "{seconds}s · plus c'est haut, mieux la lecture résiste aux coupures réseau (mais plus de latence sur le live)",
  "en": "{seconds}s · the higher it is, the better playback survives network drops (but more latency on live)",
  "es": "{seconds}s · cuanto más alto, mejor resiste la reproducción los cortes de red (pero más latencia en directo)",
  "sv": "{seconds}s · ju högre, desto bättre klarar uppspelningen nätverksavbrott (men mer fördröjning på live)",
  "da": "{seconds}s · jo højere, desto bedre klarer afspilningen netværksudfald (men mere forsinkelse på live)",
  "nb": "{seconds}s · jo høyere, desto bedre tåler avspillingen nettverksbrudd (men mer forsinkelse på direkte)",
  "ar": "{seconds} ث · كلما زادت القيمة، صمد التشغيل أكثر أمام انقطاعات الشبكة (لكن مع تأخير أكبر في البث المباشر)",
  "sw": "{seconds}s · kadiri inavyokuwa juu, ndivyo uchezaji unavyostahimili kukatika kwa mtandao (ila ucheleweshaji zaidi kwenye moja kwa moja)"
 },
 "settingsShowStatsSubtitle": {
  "fr": "Résolution, codec, FPS en surimpression pendant la lecture.",
  "en": "Resolution, codec and FPS overlaid during playback.",
  "es": "Resolución, códec y FPS superpuestos durante la reproducción.",
  "sv": "Upplösning, codec och FPS som overlay under uppspelning.",
  "da": "Opløsning, codec og FPS som overlay under afspilning.",
  "nb": "Oppløsning, kodek og FPS som overlegg under avspilling.",
  "ar": "الدقة والترميز وعدد الإطارات تظهر فوق الصورة أثناء التشغيل.",
  "sw": "Ubora, kodeki na FPS vinaonyeshwa juu ya picha wakati wa kucheza."
 },
 "settingsWifiOnly": {
  "fr": "Lecture en Wi-Fi uniquement",
  "en": "Play on Wi-Fi only",
  "es": "Reproducir solo con Wi-Fi",
  "sv": "Spela endast via Wi-Fi",
  "da": "Afspil kun via Wi-Fi",
  "nb": "Spill av kun via Wi-Fi",
  "ar": "التشغيل عبر Wi-Fi فقط",
  "sw": "Cheza kwa Wi-Fi pekee"
 },
 "settingsWifiOnlySubtitle": {
  "fr": "Bloque le démarrage d'un flux en données cellulaires (évite la facture surprise).",
  "en": "Blocks starting a stream on mobile data (avoids surprise bills).",
  "es": "Bloquea el inicio de un flujo con datos móviles (evita facturas sorpresa).",
  "sv": "Blockerar start av en ström via mobildata (undviker överraskande räkningar).",
  "da": "Blokerer start af en stream via mobildata (undgår overraskende regninger).",
  "nb": "Blokkerer start av en strøm via mobildata (unngår overraskende regninger).",
  "ar": "يمنع بدء البث عبر بيانات الجوال (يجنّبك فاتورة مفاجئة).",
  "sw": "Inazuia kuanzisha utiririshaji kwa data ya simu (kuepuka bili ya kushtukiza)."
 },
 "settingsWarnCellular": {
  "fr": "Avertir en données cellulaires",
  "en": "Warn on mobile data",
  "es": "Avisar con datos móviles",
  "sv": "Varna vid mobildata",
  "da": "Advar ved mobildata",
  "nb": "Varsle ved mobildata",
  "ar": "التنبيه عند استخدام بيانات الجوال",
  "sw": "Onya ukiwa kwenye data ya simu"
 },
 "settingsWarnCellularSubtitle": {
  "fr": "Affiche un avertissement avant de lire hors Wi-Fi.",
  "en": "Shows a warning before playing outside Wi-Fi.",
  "es": "Muestra un aviso antes de reproducir fuera del Wi-Fi.",
  "sv": "Visar en varning innan uppspelning utanför Wi-Fi.",
  "da": "Viser en advarsel før afspilning uden for Wi-Fi.",
  "nb": "Viser en advarsel før avspilling utenfor Wi-Fi.",
  "ar": "يعرض تنبيهًا قبل التشغيل خارج Wi-Fi.",
  "sw": "Inaonyesha onyo kabla ya kucheza nje ya Wi-Fi."
 },
 "settingsUserAgentTitle": {
  "fr": "Signature de lecture (User-Agent)",
  "en": "Playback signature (User-Agent)",
  "es": "Firma de reproducción (User-Agent)",
  "sv": "Uppspelningssignatur (User-Agent)",
  "da": "Afspilningssignatur (User-Agent)",
  "nb": "Avspillingssignatur (User-Agent)",
  "ar": "توقيع التشغيل (User-Agent)",
  "sw": "Sahihi ya uchezaji (User-Agent)"
 },
 "settingsUserAgentSubtitle": {
  "fr": "Si une source affiche une PUB du serveur au lieu des chaînes, change la signature. Actuel : {current}",
  "en": "If a source shows a server AD instead of your channels, change the signature. Current: {current}",
  "es": "Si una fuente muestra PUBLICIDAD del servidor en vez de los canales, cambia la firma. Actual: {current}",
  "sv": "Om en källa visar serverREKLAM i stället för kanalerna, byt signatur. Nuvarande: {current}",
  "da": "Hvis en kilde viser serverREKLAME i stedet for kanalerne, så skift signatur. Nuværende: {current}",
  "nb": "Hvis en kilde viser serverREKLAME i stedet for kanalene, bytt signatur. Nåværende: {current}",
  "ar": "إذا عرض المصدر إعلانًا من الخادم بدل القنوات، غيّر التوقيع. الحالي: {current}",
  "sw": "Ikiwa chanzo kinaonyesha TANGAZO la seva badala ya vituo, badilisha sahihi. Ya sasa: {current}"
 },
 "settingsMySources": {
  "fr": "Mes sources IPTV",
  "en": "My IPTV sources",
  "es": "Mis fuentes IPTV",
  "sv": "Mina IPTV-källor",
  "da": "Mine IPTV-kilder",
  "nb": "Mine IPTV-kilder",
  "ar": "مصادر IPTV الخاصة بي",
  "sw": "Vyanzo vyangu vya IPTV"
 },
 "settingsMyPlaylistsSubtitle": {
  "fr": "Liste des sources IPTV ajoutées (Xtream Codes).",
  "en": "List of added IPTV sources (Xtream Codes).",
  "es": "Lista de fuentes IPTV añadidas (Xtream Codes).",
  "sv": "Lista över tillagda IPTV-källor (Xtream Codes).",
  "da": "Liste over tilføjede IPTV-kilder (Xtream Codes).",
  "nb": "Liste over tillagte IPTV-kilder (Xtream Codes).",
  "ar": "قائمة مصادر IPTV المضافة (Xtream Codes).",
  "sw": "Orodha ya vyanzo vya IPTV vilivyoongezwa (Xtream Codes)."
 },
 "settingsActivateTitle": {
  "fr": "Activer / vérifier mon abonnement",
  "en": "Activate / check my subscription",
  "es": "Activar / verificar mi suscripción",
  "sv": "Aktivera / kontrollera min prenumeration",
  "da": "Aktivér / tjek mit abonnement",
  "nb": "Aktiver / sjekk abonnementet mitt",
  "ar": "تفعيل / التحقق من اشتراكي",
  "sw": "Washa / hakiki usajili wangu"
 },
 "settingsActivateSubtitle": {
  "fr": "Donne ta MAC à ton revendeur, puis recharge tes chaînes.",
  "en": "Give your MAC to your reseller, then reload your channels.",
  "es": "Da tu MAC a tu revendedor y luego recarga tus canales.",
  "sv": "Ge din MAC till din återförsäljare och ladda sedan om dina kanaler.",
  "da": "Giv din MAC til din forhandler, og genindlæs derefter dine kanaler.",
  "nb": "Gi MAC-en din til forhandleren, og last deretter inn kanalene på nytt.",
  "ar": "أعطِ عنوان MAC للموزّع، ثم أعد تحميل قنواتك.",
  "sw": "Mpe muuzaji wako MAC yako, kisha pakia upya vituo vyako."
 },
 "settingsRecordingsSubtitle": {
  "fr": "Liste des flux capturés via le bouton REC du lecteur.",
  "en": "List of streams captured with the player's REC button.",
  "es": "Lista de flujos capturados con el botón REC del reproductor.",
  "sv": "Lista över strömmar inspelade med spelarens REC-knapp.",
  "da": "Liste over streams optaget med afspillerens REC-knap.",
  "nb": "Liste over strømmer tatt opp med spillerens REC-knapp.",
  "ar": "قائمة التدفقات المسجّلة عبر زر REC في المشغّل.",
  "sw": "Orodha ya mitiririko iliyorekodiwa kwa kitufe cha REC cha kichezaji."
 },
 "settingsClearHistorySubtitle": {
  "fr": "Supprime la liste \"Reprendre\" sur l'accueil.",
  "en": "Removes the \"Resume\" list on the home screen.",
  "es": "Elimina la lista \"Reanudar\" de la pantalla de inicio.",
  "sv": "Tar bort listan \"Fortsätt\" på startsidan.",
  "da": "Fjerner listen \"Fortsæt\" på startskærmen.",
  "nb": "Fjerner listen \"Fortsett\" på startskjermen.",
  "ar": "يحذف قائمة \"المتابعة\" من الشاشة الرئيسية.",
  "sw": "Inaondoa orodha ya \"Endelea\" kwenye ukurasa wa mwanzo."
 },
 "settingsClearHistoryConfirmTitle": {
  "fr": "Vider l'historique ?",
  "en": "Clear history?",
  "es": "¿Vaciar el historial?",
  "sv": "Rensa historiken?",
  "da": "Ryd historikken?",
  "nb": "Tømme historikken?",
  "ar": "هل تريد مسح السجل؟",
  "sw": "Ufute historia?"
 },
 "settingsClearHistoryConfirmBody": {
  "fr": "La section \"Reprendre\" sera vide.",
  "en": "The \"Resume\" section will be empty.",
  "es": "La sección \"Reanudar\" quedará vacía.",
  "sv": "Sektionen \"Fortsätt\" blir tom.",
  "da": "Sektionen \"Fortsæt\" bliver tom.",
  "nb": "Seksjonen \"Fortsett\" blir tom.",
  "ar": "سيصبح قسم \"المتابعة\" فارغًا.",
  "sw": "Sehemu ya \"Endelea\" itakuwa tupu."
 },
 "settingsHistoryCleared": {
  "fr": "Historique vidé",
  "en": "History cleared",
  "es": "Historial vaciado",
  "sv": "Historik rensad",
  "da": "Historik ryddet",
  "nb": "Historikk tømt",
  "ar": "تم مسح السجل",
  "sw": "Historia imefutwa"
 },
 "settingsNotifications": {
  "fr": "Notifications",
  "en": "Notifications",
  "es": "Notificaciones",
  "sv": "Aviseringar",
  "da": "Notifikationer",
  "nb": "Varsler",
  "ar": "الإشعارات",
  "sw": "Arifa"
 },
 "settingsNotificationsSubtitle": {
  "fr": "Rappels d'émission, nouveautés et mises à jour de l'app.",
  "en": "Show reminders, news and app updates.",
  "es": "Recordatorios de programas, novedades y actualizaciones de la app.",
  "sv": "Programpåminnelser, nyheter och appuppdateringar.",
  "da": "Programpåmindelser, nyheder og appopdateringer.",
  "nb": "Programpåminnelser, nyheter og appoppdateringer.",
  "ar": "تذكيرات البرامج، الجديد وتحديثات التطبيق.",
  "sw": "Vikumbusho vya vipindi, habari mpya na masasisho ya programu."
 },
 "settingsCastSection": {
  "fr": "Cast",
  "en": "Cast",
  "es": "Cast",
  "sv": "Casta",
  "da": "Cast",
  "nb": "Cast",
  "ar": "البث (Cast)",
  "sw": "Cast"
 },
 "settingsCastDiagTitle": {
  "fr": "Diagnostic cast",
  "en": "Cast diagnostics",
  "es": "Diagnóstico de cast",
  "sv": "Cast-diagnostik",
  "da": "Cast-diagnostik",
  "nb": "Cast-diagnostikk",
  "ar": "تشخيص البث (Cast)",
  "sw": "Uchunguzi wa cast"
 },
 "settingsCastDiagSubtitle": {
  "fr": "Teste plusieurs chaînes sur une TV et rapporte la stratégie qui marche.",
  "en": "Tests several channels on a TV and reports the strategy that works.",
  "es": "Prueba varios canales en una TV e informa de la estrategia que funciona.",
  "sv": "Testar flera kanaler på en TV och rapporterar vilken strategi som fungerar.",
  "da": "Tester flere kanaler på et TV og rapporterer den strategi, der virker.",
  "nb": "Tester flere kanaler på en TV og rapporterer strategien som fungerer.",
  "ar": "يختبر عدة قنوات على التلفزيون ويبلّغ عن الاستراتيجية التي تنجح.",
  "sw": "Hujaribu vituo kadhaa kwenye TV na kuripoti mbinu inayofanya kazi."
 },
 "settingsAboutSubtitle": {
  "fr": "Version, mises à jour, crédits, légal.",
  "en": "Version, updates, credits, legal.",
  "es": "Versión, actualizaciones, créditos, legal.",
  "sv": "Version, uppdateringar, medverkande, juridik.",
  "da": "Version, opdateringer, krediteringer, jura.",
  "nb": "Versjon, oppdateringer, krediteringer, juridisk.",
  "ar": "الإصدار، التحديثات، الشكر، الشؤون القانونية.",
  "sw": "Toleo, masasisho, shukrani, kisheria."
 },
 "settingsLanguageAppTitle": {
  "fr": "Langue de l'application",
  "en": "App language",
  "es": "Idioma de la aplicación",
  "sv": "Appens språk",
  "da": "Appens sprog",
  "nb": "Appspråk",
  "ar": "لغة التطبيق",
  "sw": "Lugha ya programu"
 },
 "settingsLanguageFollowSystem": {
  "fr": "Suit la langue de l'OS",
  "en": "Follows the OS language",
  "es": "Sigue el idioma del sistema",
  "sv": "Följer systemets språk",
  "da": "Følger systemets sprog",
  "nb": "Følger systemspråket",
  "ar": "يتبع لغة النظام",
  "sw": "Inafuata lugha ya mfumo"
 },
 "settingsUserAgentChanged": {
  "fr": "Signature changée. Rouvre une chaîne pour tester.",
  "en": "Signature changed. Reopen a channel to test.",
  "es": "Firma cambiada. Vuelve a abrir un canal para probar.",
  "sv": "Signatur ändrad. Öppna en kanal igen för att testa.",
  "da": "Signatur ændret. Åbn en kanal igen for at teste.",
  "nb": "Signatur endret. Åpne en kanal på nytt for å teste.",
  "ar": "تم تغيير التوقيع. أعد فتح قناة للتجربة.",
  "sw": "Sahihi imebadilishwa. Fungua kituo tena kujaribu."
 },
 "settingsUserAgentSheetTitle": {
  "fr": "Signature de lecture",
  "en": "Playback signature",
  "es": "Firma de reproducción",
  "sv": "Uppspelningssignatur",
  "da": "Afspilningssignatur",
  "nb": "Avspillingssignatur",
  "ar": "توقيع التشغيل",
  "sw": "Sahihi ya uchezaji"
 },
 "settingsUserAgentSheetDesc": {
  "fr": "Certains serveurs IPTV ne diffusent les vraies chaînes qu'aux lecteurs reconnus et affichent une pub aux autres. Choisis la signature qui marche pour ta source (souvent IBO / ExoPlayer), ou saisis la tienne.",
  "en": "Some IPTV servers only serve the real channels to recognized players and show an ad to everyone else. Pick the signature that works for your source (often IBO / ExoPlayer), or enter your own.",
  "es": "Algunos servidores IPTV solo emiten los canales reales a reproductores reconocidos y muestran publicidad a los demás. Elige la firma que funcione con tu fuente (a menudo IBO / ExoPlayer) o escribe la tuya.",
  "sv": "Vissa IPTV-servrar skickar bara de riktiga kanalerna till kända spelare och visar reklam för andra. Välj signaturen som fungerar för din källa (ofta IBO / ExoPlayer), eller ange din egen.",
  "da": "Nogle IPTV-servere sender kun de rigtige kanaler til kendte afspillere og viser reklame til andre. Vælg den signatur, der virker for din kilde (ofte IBO / ExoPlayer), eller indtast din egen.",
  "nb": "Noen IPTV-servere sender bare de ekte kanalene til kjente spillere og viser reklame til andre. Velg signaturen som fungerer for kilden din (ofte IBO / ExoPlayer), eller skriv inn din egen.",
  "ar": "بعض خوادم IPTV تبث القنوات الحقيقية فقط للمشغّلات المعروفة وتعرض إعلانًا للبقية. اختر التوقيع الذي ينجح مع مصدرك (غالبًا IBO / ExoPlayer) أو أدخل توقيعك.",
  "sw": "Baadhi ya seva za IPTV hutuma vituo halisi kwa vichezaji vinavyotambulika pekee na kuonyesha tangazo kwa vingine. Chagua sahihi inayofanya kazi kwa chanzo chako (mara nyingi IBO / ExoPlayer), au andika yako."
 },
 "settingsUserAgentCustomLabel": {
  "fr": "Personnalisé",
  "en": "Custom",
  "es": "Personalizado",
  "sv": "Anpassad",
  "da": "Tilpasset",
  "nb": "Tilpasset",
  "ar": "مخصّص",
  "sw": "Maalum"
 },
 "settingsUserAgentHint": {
  "fr": "Colle ici le User-Agent exact…",
  "en": "Paste the exact User-Agent here…",
  "es": "Pega aquí el User-Agent exacto…",
  "sv": "Klistra in exakt User-Agent här…",
  "da": "Indsæt den præcise User-Agent her…",
  "nb": "Lim inn nøyaktig User-Agent her…",
  "ar": "الصق هنا الـ User-Agent بالضبط…",
  "sw": "Bandika User-Agent kamili hapa…"
 },
 "settingsUserAgentReset": {
  "fr": "Réinitialiser",
  "en": "Reset",
  "es": "Restablecer",
  "sv": "Återställ",
  "da": "Nulstil",
  "nb": "Tilbakestill",
  "ar": "إعادة التعيين",
  "sw": "Rejesha awali"
 },
 "settingsUserAgentApply": {
  "fr": "Appliquer",
  "en": "Apply",
  "es": "Aplicar",
  "sv": "Använd",
  "da": "Anvend",
  "nb": "Bruk",
  "ar": "تطبيق",
  "sw": "Tumia"
 },
 "settingsNotifIntro": {
  "fr": "Choisis ce que tu veux recevoir. Tu peux tout couper si tu préfères le silence.",
  "en": "Choose what you want to receive. You can turn everything off if you prefer silence.",
  "es": "Elige qué quieres recibir. Puedes apagarlo todo si prefieres el silencio.",
  "sv": "Välj vad du vill ta emot. Du kan stänga av allt om du föredrar tystnad.",
  "da": "Vælg, hvad du vil modtage. Du kan slå alt fra, hvis du foretrækker ro.",
  "nb": "Velg hva du vil motta. Du kan slå av alt hvis du foretrekker stillhet.",
  "ar": "اختر ما تريد استلامه. يمكنك إيقاف كل شيء إن كنت تفضّل الهدوء.",
  "sw": "Chagua unachotaka kupokea. Unaweza kuzima kila kitu ukipenda ukimya."
 },
 "settingsNotifReminders": {
  "fr": "Rappels d'émission",
  "en": "Show reminders",
  "es": "Recordatorios de programas",
  "sv": "Programpåminnelser",
  "da": "Programpåmindelser",
  "nb": "Programpåminnelser",
  "ar": "تذكيرات البرامج",
  "sw": "Vikumbusho vya vipindi"
 },
 "settingsNotifRemindersSubtitle": {
  "fr": "Être prévenu juste avant qu'un programme choisi commence.",
  "en": "Get notified just before a chosen program starts.",
  "es": "Recibir aviso justo antes de que empiece un programa elegido.",
  "sv": "Bli meddelad strax innan ett valt program börjar.",
  "da": "Få besked lige før et valgt program begynder.",
  "nb": "Bli varslet rett før et valgt program begynner.",
  "ar": "يصلك تنبيه قبيل بدء برنامج اخترته.",
  "sw": "Pata taarifa kabla tu kipindi ulichochagua hakijaanza."
 },
 "settingsNotifAnnouncements": {
  "fr": "Nouveautés & annonces",
  "en": "News & announcements",
  "es": "Novedades y anuncios",
  "sv": "Nyheter & meddelanden",
  "da": "Nyheder & meddelelser",
  "nb": "Nyheter og kunngjøringer",
  "ar": "الجديد والإعلانات",
  "sw": "Habari mpya na matangazo"
 },
 "settingsNotifAnnouncementsSubtitle": {
  "fr": "Messages de l'équipe : nouveau contenu, infos importantes.",
  "en": "Messages from the team: new content, important info.",
  "es": "Mensajes del equipo: contenido nuevo, información importante.",
  "sv": "Meddelanden från teamet: nytt innehåll, viktig info.",
  "da": "Beskeder fra teamet: nyt indhold, vigtig info.",
  "nb": "Meldinger fra teamet: nytt innhold, viktig info.",
  "ar": "رسائل الفريق: محتوى جديد ومعلومات مهمة.",
  "sw": "Ujumbe kutoka kwa timu: maudhui mapya, taarifa muhimu."
 },
 "settingsNotifUpdates": {
  "fr": "Mise à jour de l'app",
  "en": "App update",
  "es": "Actualización de la app",
  "sv": "Appuppdatering",
  "da": "Appopdatering",
  "nb": "Appoppdatering",
  "ar": "تحديث التطبيق",
  "sw": "Sasisho la programu"
 },
 "settingsNotifUpdatesSubtitle": {
  "fr": "Être prévenu quand une nouvelle version est disponible.",
  "en": "Get notified when a new version is available.",
  "es": "Recibir aviso cuando haya una nueva versión disponible.",
  "sv": "Bli meddelad när en ny version finns tillgänglig.",
  "da": "Få besked, når en ny version er tilgængelig.",
  "nb": "Bli varslet når en ny versjon er tilgjengelig.",
  "ar": "يصلك تنبيه عند توفر إصدار جديد.",
  "sw": "Pata taarifa toleo jipya linapopatikana."
 },
 "safeModeTitle": {
  "fr": "Mode de récupération",
  "en": "Recovery mode",
  "es": "Modo de recuperación",
  "sv": "Återställningsläge",
  "da": "Gendannelsestilstand",
  "nb": "Gjenopprettingsmodus",
  "ar": "وضع الاسترداد",
  "sw": "Hali ya urejeshaji"
 },
 "safeModeBodyImport": {
  "fr": "L'application s'est fermée plusieurs fois en chargeant tes chaînes (liste probablement trop lourde pour cet appareil). Choisis une option pour repartir :",
  "en": "The app closed several times while loading your channels (the list is probably too heavy for this device). Pick an option to get going again:",
  "es": "La aplicación se cerró varias veces al cargar tus canales (la lista probablemente es demasiado pesada para este dispositivo). Elige una opción para continuar:",
  "sv": "Appen stängdes flera gånger när dina kanaler laddades (listan är förmodligen för tung för den här enheten). Välj ett alternativ för att komma igång igen:",
  "da": "Appen lukkede flere gange under indlæsning af dine kanaler (listen er sandsynligvis for tung til denne enhed). Vælg en mulighed for at komme videre:",
  "nb": "Appen lukket seg flere ganger under lasting av kanalene dine (listen er sannsynligvis for tung for denne enheten). Velg et alternativ for å komme i gang igjen:",
  "ar": "أُغلق التطبيق عدة مرات أثناء تحميل قنواتك (القائمة على الأرجح ثقيلة جدًا على هذا الجهاز). اختر خيارًا للانطلاق من جديد:",
  "sw": "Programu ilijifunga mara kadhaa ikipakia vituo vyako (huenda orodha ni nzito mno kwa kifaa hiki). Chagua chaguo ili uanze tena:"
 },
 "safeModeBody": {
  "fr": "L'application s'est fermée plusieurs fois au démarrage. Choisis une option pour repartir :",
  "en": "The app closed several times at startup. Pick an option to get going again:",
  "es": "La aplicación se cerró varias veces al iniciar. Elige una opción para continuar:",
  "sv": "Appen stängdes flera gånger vid start. Välj ett alternativ för att komma igång igen:",
  "da": "Appen lukkede flere gange ved opstart. Vælg en mulighed for at komme videre:",
  "nb": "Appen lukket seg flere ganger ved oppstart. Velg et alternativ for å komme i gang igjen:",
  "ar": "أُغلق التطبيق عدة مرات عند بدء التشغيل. اختر خيارًا للانطلاق من جديد:",
  "sw": "Programu ilijifunga mara kadhaa wakati wa kuwasha. Chagua chaguo ili uanze tena:"
 },
 "safeModeStartNoReload": {
  "fr": "Démarrer sans recharger",
  "en": "Start without reloading",
  "es": "Iniciar sin recargar",
  "sv": "Starta utan att ladda om",
  "da": "Start uden at genindlæse",
  "nb": "Start uten å laste inn på nytt",
  "ar": "التشغيل دون إعادة تحميل",
  "sw": "Anza bila kupakia upya"
 },
 "safeModeStartNoReloadHint": {
  "fr": "Ouvre l'app sur les chaînes déjà téléchargées (recommandé).",
  "en": "Opens the app on the channels already downloaded (recommended).",
  "es": "Abre la app con los canales ya descargados (recomendado).",
  "sv": "Öppnar appen med de redan nedladdade kanalerna (rekommenderas).",
  "da": "Åbner appen med de allerede hentede kanaler (anbefales).",
  "nb": "Åpner appen med kanalene som allerede er lastet ned (anbefalt).",
  "ar": "يفتح التطبيق على القنوات المحمّلة مسبقًا (مستحسن).",
  "sw": "Inafungua programu na vituo vilivyokwisha pakuliwa (inapendekezwa)."
 },
 "safeModeStartNoReloadDone": {
  "fr": "C'est prêt. Rouvre l'application : elle s'ouvrira sur tes chaînes déjà téléchargées, sans tout recharger.",
  "en": "All set. Reopen the app: it will open on your already-downloaded channels, without reloading everything.",
  "es": "Listo. Vuelve a abrir la aplicación: se abrirá con tus canales ya descargados, sin recargar todo.",
  "sv": "Klart. Öppna appen igen: den öppnas med dina redan nedladdade kanaler, utan att ladda om allt.",
  "da": "Klar. Åbn appen igen: den åbner med dine allerede hentede kanaler uden at genindlæse alt.",
  "nb": "Klart. Åpne appen på nytt: den åpnes med kanalene som allerede er lastet ned, uten å laste inn alt på nytt.",
  "ar": "جاهز. أعد فتح التطبيق: سيفتح على قنواتك المحمّلة مسبقًا دون إعادة تحميل كل شيء.",
  "sw": "Tayari. Fungua programu tena: itafunguka na vituo vyako vilivyokwisha pakuliwa, bila kupakia upya kila kitu."
 },
 "safeModeDeleteSource": {
  "fr": "Supprimer ma source",
  "en": "Delete my source",
  "es": "Eliminar mi fuente",
  "sv": "Ta bort min källa",
  "da": "Slet min kilde",
  "nb": "Slett kilden min",
  "ar": "حذف مصدري",
  "sw": "Futa chanzo changu"
 },
 "safeModeDeleteSourceHint": {
  "fr": "Repart de zéro si la liste est trop lourde / corrompue.",
  "en": "Starts from scratch if the list is too heavy / corrupted.",
  "es": "Empieza de cero si la lista es demasiado pesada / está dañada.",
  "sv": "Börjar om från noll om listan är för tung / skadad.",
  "da": "Starter forfra, hvis listen er for tung / beskadiget.",
  "nb": "Starter på nytt hvis listen er for tung / skadet.",
  "ar": "يبدأ من الصفر إذا كانت القائمة ثقيلة جدًا أو تالفة.",
  "sw": "Huanza upya ikiwa orodha ni nzito mno / imeharibika."
 },
 "safeModeSourceDeletedDone": {
  "fr": "Source supprimée. Rouvre l'application, puis ré-ajoute ta liste (ou laisse le revendeur la repousser).",
  "en": "Source deleted. Reopen the app, then re-add your list (or let your reseller push it again).",
  "es": "Fuente eliminada. Vuelve a abrir la aplicación y añade de nuevo tu lista (o deja que tu revendedor la envíe otra vez).",
  "sv": "Källa borttagen. Öppna appen igen och lägg till din lista på nytt (eller låt återförsäljaren skicka den igen).",
  "da": "Kilde slettet. Åbn appen igen, og tilføj din liste på ny (eller lad forhandleren sende den igen).",
  "nb": "Kilde slettet. Åpne appen på nytt og legg til listen din igjen (eller la forhandleren sende den på nytt).",
  "ar": "تم حذف المصدر. أعد فتح التطبيق ثم أضف قائمتك من جديد (أو دع الموزّع يرسلها مجددًا).",
  "sw": "Chanzo kimefutwa. Fungua programu tena, kisha ongeza orodha yako upya (au mwache muuzaji aituma tena)."
 },
 "safeModeRetryNormal": {
  "fr": "Réessayer normalement",
  "en": "Try again normally",
  "es": "Reintentar normalmente",
  "sv": "Försök igen som vanligt",
  "da": "Prøv igen normalt",
  "nb": "Prøv igjen normalt",
  "ar": "المحاولة مجددًا بشكل عادي",
  "sw": "Jaribu tena kama kawaida"
 },
 "safeModeRetryHintImport": {
  "fr": "Relance un démarrage complet (avec rechargement).",
  "en": "Runs a full startup again (with reloading).",
  "es": "Vuelve a lanzar un arranque completo (con recarga).",
  "sv": "Kör en fullständig start igen (med omladdning).",
  "da": "Kører en fuld opstart igen (med genindlæsning).",
  "nb": "Kjører en full oppstart på nytt (med ny innlasting).",
  "ar": "يعيد تشغيلًا كاملاً (مع إعادة التحميل).",
  "sw": "Huanzisha tena uwashaji kamili (pamoja na kupakia upya)."
 },
 "safeModeRetryHint": {
  "fr": "Relance un démarrage complet.",
  "en": "Runs a full startup again.",
  "es": "Vuelve a lanzar un arranque completo.",
  "sv": "Kör en fullständig start igen.",
  "da": "Kører en fuld opstart igen.",
  "nb": "Kjører en full oppstart på nytt.",
  "ar": "يعيد تشغيلًا كاملاً.",
  "sw": "Huanzisha tena uwashaji kamili."
 },
 "safeModeRetryDone": {
  "fr": "On va réessayer un démarrage normal. Rouvre l'application.",
  "en": "We'll try a normal startup again. Reopen the app.",
  "es": "Volveremos a intentar un arranque normal. Vuelve a abrir la aplicación.",
  "sv": "Vi försöker en normal start igen. Öppna appen igen.",
  "da": "Vi prøver en normal opstart igen. Åbn appen igen.",
  "nb": "Vi prøver en normal oppstart igjen. Åpne appen på nytt.",
  "ar": "سنحاول تشغيلًا عاديًا من جديد. أعد فتح التطبيق.",
  "sw": "Tutajaribu tena uwashaji wa kawaida. Fungua programu tena."
 },
 "safeModeCompat": {
  "fr": "Démarrer en mode compatibilité",
  "en": "Start in compatibility mode",
  "es": "Iniciar en modo compatibilidad",
  "sv": "Starta i kompatibilitetsläge",
  "da": "Start i kompatibilitetstilstand",
  "nb": "Start i kompatibilitetsmodus",
  "ar": "التشغيل في وضع التوافق",
  "sw": "Anza katika hali ya utangamano"
 },
 "safeModeCompatHint": {
  "fr": "Affichage simplifié si l'écran plantait (recommandé).",
  "en": "Simplified display if the screen was crashing (recommended).",
  "es": "Pantalla simplificada si la interfaz fallaba (recomendado).",
  "sv": "Förenklad visning om skärmen kraschade (rekommenderas).",
  "da": "Forenklet visning, hvis skærmen crashede (anbefales).",
  "nb": "Forenklet visning hvis skjermen krasjet (anbefalt).",
  "ar": "عرض مبسّط إذا كانت الشاشة تنهار (مستحسن).",
  "sw": "Onyesho rahisi ikiwa skrini ilikuwa ikianguka (inapendekezwa)."
 },
 "safeModeCompatDone": {
  "fr": "Mode compatibilité activé. Rouvre l'application.",
  "en": "Compatibility mode enabled. Reopen the app.",
  "es": "Modo compatibilidad activado. Vuelve a abrir la aplicación.",
  "sv": "Kompatibilitetsläge aktiverat. Öppna appen igen.",
  "da": "Kompatibilitetstilstand aktiveret. Åbn appen igen.",
  "nb": "Kompatibilitetsmodus aktivert. Åpne appen på nytt.",
  "ar": "تم تفعيل وضع التوافق. أعد فتح التطبيق.",
  "sw": "Hali ya utangamano imewashwa. Fungua programu tena."
 },
 "safeModeReset": {
  "fr": "Réinitialiser (supprimer la source)",
  "en": "Reset (delete the source)",
  "es": "Restablecer (eliminar la fuente)",
  "sv": "Återställ (ta bort källan)",
  "da": "Nulstil (slet kilden)",
  "nb": "Tilbakestill (slett kilden)",
  "ar": "إعادة التعيين (حذف المصدر)",
  "sw": "Rejesha awali (futa chanzo)"
 },
 "safeModeResetHint": {
  "fr": "Dernier recours : repart sur une app vierge.",
  "en": "Last resort: starts over with a clean app.",
  "es": "Último recurso: empieza con una app limpia.",
  "sv": "Sista utvägen: börjar om med en tom app.",
  "da": "Sidste udvej: starter forfra med en ren app.",
  "nb": "Siste utvei: starter på nytt med en ren app.",
  "ar": "الحل الأخير: البدء بتطبيق نظيف.",
  "sw": "Suluhisho la mwisho: huanza upya na programu safi."
 },
 "safeModeCloseApp": {
  "fr": "Fermer l'application",
  "en": "Close the app",
  "es": "Cerrar la aplicación",
  "sv": "Stäng appen",
  "da": "Luk appen",
  "nb": "Lukk appen",
  "ar": "إغلاق التطبيق",
  "sw": "Funga programu"
 },
 "safeModeWait": {
  "fr": "Un instant…",
  "en": "One moment…",
  "es": "Un momento…",
  "sv": "Ett ögonblick…",
  "da": "Et øjeblik…",
  "nb": "Et øyeblikk…",
  "ar": "لحظة من فضلك…",
  "sw": "Subiri kidogo…"
 },
 "onboardingWelcomeAppTitle": {
  "fr": "Bienvenue sur {appName}",
  "en": "Welcome to {appName}",
  "es": "Bienvenido a {appName}",
  "sv": "Välkommen till {appName}",
  "da": "Velkommen til {appName}",
  "nb": "Velkommen til {appName}",
  "ar": "مرحبًا بك في {appName}",
  "sw": "Karibu {appName}"
 },
 "onboardingLoadChannelsTitle": {
  "fr": "Charge tes chaînes",
  "en": "Load your channels",
  "es": "Carga tus canales",
  "sv": "Ladda dina kanaler",
  "da": "Indlæs dine kanaler",
  "nb": "Last inn kanalene dine",
  "ar": "حمّل قنواتك",
  "sw": "Pakia vituo vyako"
 },
 "onboardingLoadChannelsDesc": {
  "fr": "Choisis ton serveur et saisis ton code Xtream (utilisateur + mot de passe). Tes chaînes apparaissent en quelques secondes.",
  "en": "Pick your server and enter your Xtream code (username + password). Your channels show up in seconds.",
  "es": "Elige tu servidor e introduce tu código Xtream (usuario + contraseña). Tus canales aparecen en segundos.",
  "sv": "Välj din server och ange din Xtream-kod (användarnamn + lösenord). Dina kanaler dyker upp på några sekunder.",
  "da": "Vælg din server, og indtast din Xtream-kode (brugernavn + adgangskode). Dine kanaler dukker op på få sekunder.",
  "nb": "Velg serveren din og skriv inn Xtream-koden (brukernavn + passord). Kanalene dine dukker opp på få sekunder.",
  "ar": "اختر خادمك وأدخل رمز Xtream (اسم المستخدم + كلمة المرور). ستظهر قنواتك خلال ثوانٍ.",
  "sw": "Chagua seva yako na uweke msimbo wako wa Xtream (jina la mtumiaji + nenosiri). Vituo vyako vinaonekana ndani ya sekunde chache."
 },
 "onboardingActivateTitle": {
  "fr": "Active tes chaînes",
  "en": "Activate your channels",
  "es": "Activa tus canales",
  "sv": "Aktivera dina kanaler",
  "da": "Aktivér dine kanaler",
  "nb": "Aktiver kanalene dine",
  "ar": "فعّل قنواتك",
  "sw": "Washa vituo vyako"
 },
 "onboardingActivateDesc": {
  "fr": "Cet identifiant unique permet d'activer ton compte à distance. Envoie-le en 1 tap, notre équipe configure ton accès en quelques minutes.",
  "en": "This unique ID lets us activate your account remotely. Send it in 1 tap and our team sets up your access in minutes.",
  "es": "Este identificador único permite activar tu cuenta a distancia. Envíalo con 1 toque y nuestro equipo configura tu acceso en minutos.",
  "sv": "Detta unika ID gör att ditt konto kan aktiveras på distans. Skicka det med ett tryck så ordnar vårt team din åtkomst på några minuter.",
  "da": "Dette unikke ID gør det muligt at aktivere din konto på afstand. Send det med ét tryk, så opsætter vores team din adgang på få minutter.",
  "nb": "Denne unike ID-en gjør at kontoen din kan aktiveres eksternt. Send den med ett trykk, så setter teamet vårt opp tilgangen din på få minutter.",
  "ar": "هذا المعرّف الفريد يتيح تفعيل حسابك عن بُعد. أرسله بضغطة واحدة وسيجهّز فريقنا وصولك خلال دقائق.",
  "sw": "Kitambulisho hiki cha kipekee huruhusu kuwasha akaunti yako kwa mbali. Kituma kwa mguso mmoja, na timu yetu itaandaa ufikiaji wako ndani ya dakika chache."
 },
 "onboardingEverythingTitle": {
  "fr": "Tout ce qu'il te faut",
  "en": "Everything you need",
  "es": "Todo lo que necesitas",
  "sv": "Allt du behöver",
  "da": "Alt hvad du behøver",
  "nb": "Alt du trenger",
  "ar": "كل ما تحتاجه",
  "sw": "Kila unachohitaji"
 },
 "onboardingEverythingDesc": {
  "fr": "Sans publicité. Cast vers TV, ordi, tablette. Enregistrement en parallèle. Lecteur 4K/8K. QR-cast. Recherche instantanée.",
  "en": "Ad-free. Cast to TV, computer, tablet. Record while you watch. 4K/8K player. QR-cast. Instant search.",
  "es": "Sin publicidad. Cast a TV, ordenador, tableta. Grabación en paralelo. Reproductor 4K/8K. QR-cast. Búsqueda instantánea.",
  "sv": "Reklamfritt. Casta till TV, dator, surfplatta. Spela in samtidigt. 4K/8K-spelare. QR-cast. Direktsökning.",
  "da": "Reklamefrit. Cast til TV, computer, tablet. Optag samtidig. 4K/8K-afspiller. QR-cast. Øjeblikkelig søgning.",
  "nb": "Reklamefritt. Cast til TV, PC, nettbrett. Ta opp samtidig. 4K/8K-spiller. QR-cast. Øyeblikkelig søk.",
  "ar": "بدون إعلانات. بث إلى التلفزيون والحاسوب واللوحي. تسجيل أثناء المشاهدة. مشغّل 4K/8K. بث بـ QR. بحث فوري.",
  "sw": "Bila matangazo. Cast kwenye TV, kompyuta, kishikwambi. Rekodi huku ukitazama. Kichezaji 4K/8K. QR-cast. Utafutaji wa papo hapo."
 },
 "onboardingTrialDesc": {
  "fr": "Profite de toutes les fonctions pendant 7 jours. Ensuite 5 €/an ou 9,90 € à vie sur tous tes appareils — paiement sécurisé (jamais in-app).",
  "en": "Enjoy every feature for 7 days. Then €5/year or €9.90 for life on all your devices — secure payment (never in-app).",
  "es": "Disfruta de todas las funciones durante 7 días. Luego 5 €/año o 9,90 € de por vida en todos tus dispositivos — pago seguro (nunca in-app).",
  "sv": "Njut av alla funktioner i 7 dagar. Sedan 5 €/år eller 9,90 € livet ut på alla dina enheter — säker betalning (aldrig i appen).",
  "da": "Nyd alle funktioner i 7 dage. Derefter 5 €/år eller 9,90 € for livstid på alle dine enheder — sikker betaling (aldrig i appen).",
  "nb": "Nyt alle funksjoner i 7 dager. Deretter 5 €/år eller 9,90 € for livstid på alle enhetene dine — sikker betaling (aldri i appen).",
  "ar": "استمتع بكل الميزات لمدة 7 أيام. بعدها 5 € سنويًا أو 9,90 € مدى الحياة على كل أجهزتك — دفع آمن (وليس داخل التطبيق أبدًا).",
  "sw": "Furahia vipengele vyote kwa siku 7. Kisha €5 kwa mwaka au €9.90 milele kwenye vifaa vyako vyote — malipo salama (kamwe si ndani ya programu)."
 },
 "onboardingActivateMessage": {
  "fr": "Bonjour {appName}, voici mon identifiant pour activer mes chaînes :\n\n{mac}",
  "en": "Hello {appName}, here is my ID to activate my channels:\n\n{mac}",
  "es": "Hola {appName}, este es mi identificador para activar mis canales:\n\n{mac}",
  "sv": "Hej {appName}, här är mitt ID för att aktivera mina kanaler:\n\n{mac}",
  "da": "Hej {appName}, her er mit ID til at aktivere mine kanaler:\n\n{mac}",
  "nb": "Hei {appName}, her er ID-en min for å aktivere kanalene mine:\n\n{mac}",
  "ar": "مرحبًا {appName}، هذا معرّفي لتفعيل قنواتي:\n\n{mac}",
  "sw": "Habari {appName}, hiki ni kitambulisho changu cha kuwasha vituo vyangu:\n\n{mac}"
 },
 "updatePromptTitle": {
  "fr": "Mise à jour disponible",
  "en": "Update available",
  "es": "Actualización disponible",
  "sv": "Uppdatering tillgänglig",
  "da": "Opdatering tilgængelig",
  "nb": "Oppdatering tilgjengelig",
  "ar": "يتوفر تحديث",
  "sw": "Sasisho linapatikana"
 },
 "updatePromptBodyVersion": {
  "fr": "La version {version} est disponible. Elle s'installe par-dessus l'app actuelle — tes favoris et réglages sont conservés.",
  "en": "Version {version} is available. It installs on top of the current app — your favorites and settings are kept.",
  "es": "La versión {version} está disponible. Se instala sobre la app actual — tus favoritos y ajustes se conservan.",
  "sv": "Version {version} är tillgänglig. Den installeras ovanpå den nuvarande appen — dina favoriter och inställningar behålls.",
  "da": "Version {version} er tilgængelig. Den installeres oven på den nuværende app — dine favoritter og indstillinger bevares.",
  "nb": "Versjon {version} er tilgjengelig. Den installeres oppå den nåværende appen — favorittene og innstillingene dine beholdes.",
  "ar": "الإصدار {version} متوفر. يُثبَّت فوق التطبيق الحالي — تبقى مفضلاتك وإعداداتك محفوظة.",
  "sw": "Toleo {version} linapatikana. Linasakinishwa juu ya programu ya sasa — vipendwa na mipangilio yako vinabaki."
 },
 "updatePromptBody": {
  "fr": "Une nouvelle version est disponible. Elle s'installe par-dessus l'app actuelle — tes favoris et réglages sont conservés.",
  "en": "A new version is available. It installs on top of the current app — your favorites and settings are kept.",
  "es": "Hay una nueva versión disponible. Se instala sobre la app actual — tus favoritos y ajustes se conservan.",
  "sv": "En ny version är tillgänglig. Den installeras ovanpå den nuvarande appen — dina favoriter och inställningar behålls.",
  "da": "En ny version er tilgængelig. Den installeres oven på den nuværende app — dine favoritter og indstillinger bevares.",
  "nb": "En ny versjon er tilgjengelig. Den installeres oppå den nåværende appen — favorittene og innstillingene dine beholdes.",
  "ar": "يتوفر إصدار جديد. يُثبَّت فوق التطبيق الحالي — تبقى مفضلاتك وإعداداتك محفوظة.",
  "sw": "Toleo jipya linapatikana. Linasakinishwa juu ya programu ya sasa — vipendwa na mipangilio yako vinabaki."
 },
 "updatePromptUpdate": {
  "fr": "Mettre à jour",
  "en": "Update",
  "es": "Actualizar",
  "sv": "Uppdatera",
  "da": "Opdater",
  "nb": "Oppdater",
  "ar": "تحديث",
  "sw": "Sasisha"
 },
 "updatePromptStarting": {
  "fr": "Démarrage…",
  "en": "Starting…",
  "es": "Iniciando…",
  "sv": "Startar…",
  "da": "Starter…",
  "nb": "Starter…",
  "ar": "جارٍ البدء…",
  "sw": "Inaanza…"
 },
 "updatePromptFailed": {
  "fr": "Échec du téléchargement. Réessaie, ou télécharge depuis le lien direct.",
  "en": "Download failed. Try again, or download from the direct link.",
  "es": "Fallo en la descarga. Reinténtalo o descarga desde el enlace directo.",
  "sv": "Nedladdningen misslyckades. Försök igen, eller ladda ner via direktlänken.",
  "da": "Download mislykkedes. Prøv igen, eller download via det direkte link.",
  "nb": "Nedlastingen mislyktes. Prøv igjen, eller last ned via direktelenken.",
  "ar": "فشل التنزيل. حاول مجددًا أو نزّل من الرابط المباشر.",
  "sw": "Upakuaji umeshindikana. Jaribu tena, au pakua kupitia kiungo cha moja kwa moja."
 },
 "cellularWifiOnlyTitle": {
  "fr": "Wi-Fi uniquement",
  "en": "Wi-Fi only",
  "es": "Solo Wi-Fi",
  "sv": "Endast Wi-Fi",
  "da": "Kun Wi-Fi",
  "nb": "Kun Wi-Fi",
  "ar": "Wi-Fi فقط",
  "sw": "Wi-Fi pekee"
 },
 "cellularWifiOnlyBody": {
  "fr": "Tu es en données cellulaires et la lecture est réglée sur « Wi-Fi uniquement ». Connecte-toi en Wi-Fi, ou lis quand même (consommera tes données).",
  "en": "You're on mobile data and playback is set to \"Wi-Fi only\". Connect to Wi-Fi, or play anyway (this will use your data).",
  "es": "Estás con datos móviles y la reproducción está en «Solo Wi-Fi». Conéctate a una red Wi-Fi o reproduce igualmente (consumirá tus datos).",
  "sv": "Du använder mobildata och uppspelningen är inställd på ”Endast Wi-Fi”. Anslut till Wi-Fi eller spela ändå (förbrukar din data).",
  "da": "Du er på mobildata, og afspilning er sat til \"Kun Wi-Fi\". Opret forbindelse til Wi-Fi, eller afspil alligevel (bruger dine data).",
  "nb": "Du er på mobildata og avspilling er satt til «Kun Wi-Fi». Koble til Wi-Fi, eller spill av likevel (bruker dataene dine).",
  "ar": "أنت على بيانات الجوال والتشغيل مضبوط على «Wi-Fi فقط». اتصل بشبكة Wi-Fi أو شغّل رغم ذلك (سيستهلك بياناتك).",
  "sw": "Uko kwenye data ya simu na uchezaji umewekwa kwa \"Wi-Fi pekee\". Unganisha kwenye Wi-Fi, au cheza hata hivyo (itatumia data yako)."
 },
 "cellularPlayAnyway": {
  "fr": "Lire quand même",
  "en": "Play anyway",
  "es": "Reproducir igualmente",
  "sv": "Spela ändå",
  "da": "Afspil alligevel",
  "nb": "Spill av likevel",
  "ar": "التشغيل رغم ذلك",
  "sw": "Cheza hata hivyo"
 },
 "cellularWarnTitle": {
  "fr": "Données cellulaires",
  "en": "Mobile data",
  "es": "Datos móviles",
  "sv": "Mobildata",
  "da": "Mobildata",
  "nb": "Mobildata",
  "ar": "بيانات الجوال",
  "sw": "Data ya simu"
 },
 "cellularWarnBody": {
  "fr": "Tu es en données cellulaires. Le streaming peut consommer beaucoup de data.",
  "en": "You're on mobile data. Streaming can use a lot of data.",
  "es": "Estás con datos móviles. El streaming puede consumir muchos datos.",
  "sv": "Du använder mobildata. Strömning kan förbruka mycket data.",
  "da": "Du er på mobildata. Streaming kan bruge meget data.",
  "nb": "Du er på mobildata. Strømming kan bruke mye data.",
  "ar": "أنت على بيانات الجوال. قد يستهلك البث كمية كبيرة من البيانات.",
  "sw": "Uko kwenye data ya simu. Utiririshaji unaweza kutumia data nyingi."
 },
 "cellularDontWarnAgain": {
  "fr": "Ne plus avertir",
  "en": "Don't warn again",
  "es": "No avisar más",
  "sv": "Varna inte igen",
  "da": "Advar ikke igen",
  "nb": "Ikke varsle igjen",
  "ar": "عدم التنبيه مجددًا",
  "sw": "Usionye tena"
 },
 "accentChampagne": {
  "fr": "Champagne",
  "en": "Champagne",
  "es": "Champán",
  "sv": "Champagne",
  "da": "Champagne",
  "nb": "Champagne",
  "ar": "شمبانيا",
  "sw": "Shampeni"
 },
 "accentEmber": {
  "fr": "Braise",
  "en": "Ember",
  "es": "Brasa",
  "sv": "Glöd",
  "da": "Glød",
  "nb": "Glo",
  "ar": "جمر",
  "sw": "Kaa la moto"
 },
 "accentOcean": {
  "fr": "Océan",
  "en": "Ocean",
  "es": "Océano",
  "sv": "Ocean",
  "da": "Ocean",
  "nb": "Osean",
  "ar": "محيط",
  "sw": "Bahari"
 },
 "accentEmerald": {
  "fr": "Émeraude",
  "en": "Emerald",
  "es": "Esmeralda",
  "sv": "Smaragd",
  "da": "Smaragd",
  "nb": "Smaragd",
  "ar": "زمرد",
  "sw": "Zumaridi"
 },
 "accentViolet": {
  "fr": "Améthyste",
  "en": "Amethyst",
  "es": "Amatista",
  "sv": "Ametist",
  "da": "Ametyst",
  "nb": "Ametyst",
  "ar": "جمشت",
  "sw": "Amethisti"
 },
 "accentGold": {
  "fr": "Or",
  "en": "Gold",
  "es": "Oro",
  "sv": "Guld",
  "da": "Guld",
  "nb": "Gull",
  "ar": "ذهبي",
  "sw": "Dhahabu"
 },
 "accentTurquoise": {
  "fr": "Turquoise",
  "en": "Turquoise",
  "es": "Turquesa",
  "sv": "Turkos",
  "da": "Turkis",
  "nb": "Turkis",
  "ar": "فيروزي",
  "sw": "Feruzi"
 },
 "accentRose": {
  "fr": "Rose",
  "en": "Pink",
  "es": "Rosa",
  "sv": "Rosa",
  "da": "Rosa",
  "nb": "Rosa",
  "ar": "وردي",
  "sw": "Waridi"
 },
 "accentCoral": {
  "fr": "Corail",
  "en": "Coral",
  "es": "Coral",
  "sv": "Korall",
  "da": "Koral",
  "nb": "Korall",
  "ar": "مرجاني",
  "sw": "Matumbawe"
 },
 "accentIndigo": {
  "fr": "Indigo",
  "en": "Indigo",
  "es": "Índigo",
  "sv": "Indigo",
  "da": "Indigo",
  "nb": "Indigo",
  "ar": "نيلي",
  "sw": "Nili"
 },
 "accentLime": {
  "fr": "Citron vert",
  "en": "Lime",
  "es": "Lima",
  "sv": "Lime",
  "da": "Lime",
  "nb": "Lime",
  "ar": "ليموني",
  "sw": "Ndimu"
 },
 "accentCustom": {
  "fr": "Personnalisé",
  "en": "Custom",
  "es": "Personalizado",
  "sv": "Anpassad",
  "da": "Tilpasset",
  "nb": "Tilpasset",
  "ar": "مخصّص",
  "sw": "Maalum"
 },
 "favoritesNowProgram": {
  "fr": "En ce moment · {program}",
  "en": "On now · {program}",
  "es": "Ahora · {program}",
  "sv": "Just nu · {program}",
  "da": "Lige nu · {program}",
  "nb": "Nå · {program}",
  "ar": "الآن · {program}",
  "sw": "Sasa hivi · {program}"
 },
 "feedbackThanks": {
  "fr": "Merci pour ton avis 🙏",
  "en": "Thanks for your feedback 🙏",
  "es": "Gracias por tu opinión 🙏",
  "sv": "Tack för din feedback 🙏",
  "da": "Tak for din feedback 🙏",
  "nb": "Takk for tilbakemeldingen 🙏",
  "ar": "شكرًا على رأيك 🙏",
  "sw": "Asante kwa maoni yako 🙏"
 },
 "feedbackHint": {
  "fr": "Écris ton avis ou comment améliorer l'app…",
  "en": "Write your feedback or how to improve the app…",
  "es": "Escribe tu opinión o cómo mejorar la app…",
  "sv": "Skriv din feedback eller hur appen kan förbättras…",
  "da": "Skriv din feedback, eller hvordan appen kan forbedres…",
  "nb": "Skriv tilbakemeldingen din eller hvordan appen kan forbedres…",
  "ar": "اكتب رأيك أو كيف نحسّن التطبيق…",
  "sw": "Andika maoni yako au jinsi ya kuboresha programu…"
 },
 "searchAiUnavailable": {
  "fr": "Recherche IA indisponible pour le moment.",
  "en": "AI search is unavailable right now.",
  "es": "Búsqueda con IA no disponible por el momento.",
  "sv": "AI-sökning är inte tillgänglig just nu.",
  "da": "AI-søgning er ikke tilgængelig lige nu.",
  "nb": "AI-søk er utilgjengelig akkurat nå.",
  "ar": "بحث الذكاء الاصطناعي غير متاح حاليًا.",
  "sw": "Utafutaji wa AI haupatikani kwa sasa."
 },
 "searchAiEmptyPrompt": {
  "fr": "Écris ce que tu veux regarder, ex. « un film d'action récent ».",
  "en": "Type what you want to watch, e.g. \"a recent action movie\".",
  "es": "Escribe lo que quieres ver, p. ej. «una película de acción reciente».",
  "sv": "Skriv vad du vill titta på, t.ex. ”en ny actionfilm”.",
  "da": "Skriv, hvad du vil se, f.eks. \"en ny actionfilm\".",
  "nb": "Skriv hva du vil se, f.eks. «en ny actionfilm».",
  "ar": "اكتب ما تريد مشاهدته، مثل «فيلم أكشن حديث».",
  "sw": "Andika unachotaka kutazama, mf. \"filamu mpya ya vituko\"."
 },
 "searchAiTip": {
  "fr": "Cherche une chaîne ou un film par son nom — ou appuie sur « IA » et décris ce que tu veux regarder.",
  "en": "Search a channel or a movie by name — or tap \"AI\" and describe what you want to watch.",
  "es": "Busca un canal o una película por su nombre — o pulsa «IA» y describe lo que quieres ver.",
  "sv": "Sök en kanal eller film på namn — eller tryck på ”AI” och beskriv vad du vill titta på.",
  "da": "Søg efter en kanal eller film på navn — eller tryk på \"AI\", og beskriv, hvad du vil se.",
  "nb": "Søk etter en kanal eller film på navn — eller trykk på «AI» og beskriv hva du vil se.",
  "ar": "ابحث عن قناة أو فيلم بالاسم — أو اضغط «الذكاء الاصطناعي» وصف ما تريد مشاهدته.",
  "sw": "Tafuta kituo au filamu kwa jina — au gusa \"AI\" na ueleze unachotaka kutazama."
 },
 "searchAiButton": {
  "fr": "Recherche IA",
  "en": "AI search",
  "es": "Búsqueda IA",
  "sv": "AI-sökning",
  "da": "AI-søgning",
  "nb": "AI-søk",
  "ar": "بحث بالذكاء الاصطناعي",
  "sw": "Utafutaji wa AI"
 },
 "navFootball": {
  "fr": "Football",
  "en": "Football",
  "es": "Fútbol",
  "sv": "Fotboll",
  "da": "Fodbold",
  "nb": "Fotball",
  "ar": "كرة القدم",
  "sw": "Soka"
 },
 "navInformation": {
  "fr": "Information",
  "en": "News",
  "es": "Noticias",
  "sv": "Nyheter",
  "da": "Nyheder",
  "nb": "Nyheter",
  "ar": "الأخبار",
  "sw": "Habari"
 },
 "navKids": {
  "fr": "Enfant",
  "en": "Kids",
  "es": "Infantil",
  "sv": "Barn",
  "da": "Børn",
  "nb": "Barn",
  "ar": "أطفال",
  "sw": "Watoto"
 },
 "playerDesktopRetryQuitHint": {
  "fr": "Entrée : Réessayer   ·   Échap : Quitter",
  "en": "Enter: Retry   ·   Esc: Quit",
  "es": "Intro: Reintentar   ·   Esc: Salir",
  "sv": "Enter: Försök igen   ·   Esc: Avsluta",
  "da": "Enter: Prøv igen   ·   Esc: Afslut",
  "nb": "Enter: Prøv igjen   ·   Esc: Avslutt",
  "ar": "Enter: إعادة المحاولة   ·   Esc: خروج",
  "sw": "Enter: Jaribu tena   ·   Esc: Ondoka"
 },
 "playerFavoriteShortcutTooltip": {
  "fr": "Favori (F)",
  "en": "Favorite (F)",
  "es": "Favorito (F)",
  "sv": "Favorit (F)",
  "da": "Favorit (F)",
  "nb": "Favoritt (F)",
  "ar": "المفضلة (F)",
  "sw": "Kipendwa (F)"
 },
 "playerFavoriteTooltip": {
  "fr": "Favori",
  "en": "Favorite",
  "es": "Favorito",
  "sv": "Favorit",
  "da": "Favorit",
  "nb": "Favoritt",
  "ar": "المفضلة",
  "sw": "Kipendwa"
 },
 "screenCastTitle": {
  "fr": "Caster sur un écran",
  "en": "Cast to a screen",
  "es": "Transmitir a una pantalla",
  "sv": "Casta till en skärm",
  "da": "Cast til en skærm",
  "nb": "Cast til en skjerm",
  "ar": "البث إلى شاشة",
  "sw": "Onyesha kwenye skrini"
 },
 "screenCastStartError": {
  "fr": "Impossible de démarrer le partage. Vérifie que le Wi-Fi est activé et réessaie.",
  "en": "Couldn't start sharing. Check that Wi-Fi is on and try again.",
  "es": "No se pudo iniciar la transmisión. Comprueba que el Wi-Fi está activado y vuelve a intentarlo.",
  "sv": "Det gick inte att starta delningen. Kontrollera att Wi-Fi är på och försök igen.",
  "da": "Delingen kunne ikke startes. Tjek at Wi-Fi er slået til, og prøv igen.",
  "nb": "Kunne ikke starte delingen. Sjekk at Wi-Fi er på og prøv igjen.",
  "ar": "تعذّر بدء المشاركة. تأكد من تفعيل Wi-Fi ثم أعد المحاولة.",
  "sw": "Imeshindwa kuanza kushiriki. Hakikisha Wi-Fi imewashwa kisha ujaribu tena."
 },
 "screenCastInstructions": {
  "fr": "Sur ton ordi ou ta TV (sur le MÊME Wi-Fi que le téléphone), ouvre le navigateur et tape cette adresse :",
  "en": "On your computer or TV (on the SAME Wi-Fi as the phone), open the browser and type this address:",
  "es": "En tu ordenador o TV (en el MISMO Wi-Fi que el teléfono), abre el navegador y escribe esta dirección:",
  "sv": "På din dator eller TV (på SAMMA Wi-Fi som telefonen), öppna webbläsaren och skriv in den här adressen:",
  "da": "På din computer eller dit TV (på SAMME Wi-Fi som telefonen), åbn browseren og indtast denne adresse:",
  "nb": "På PC-en eller TV-en din (på SAMME Wi-Fi som telefonen), åpne nettleseren og skriv inn denne adressen:",
  "ar": "على حاسوبك أو تلفازك (على نفس شبكة Wi-Fi الخاصة بالهاتف)، افتح المتصفح واكتب هذا العنوان:",
  "sw": "Kwenye kompyuta au TV yako (kwenye Wi-Fi ILE ILE ya simu), fungua kivinjari na uandike anwani hii:"
 },
 "screenCastScanHint": {
  "fr": "ou scanne avec un autre téléphone",
  "en": "or scan with another phone",
  "es": "o escanéalo con otro teléfono",
  "sv": "eller skanna med en annan telefon",
  "da": "eller scan med en anden telefon",
  "nb": "eller skann med en annen telefon",
  "ar": "أو امسحه بهاتف آخر",
  "sw": "au skani kwa simu nyingine"
 },
 "screenCastKeepOpenHint": {
  "fr": "La chaîne démarre toute seule. Garde l’app ouverte : c’est le téléphone qui envoie la vidéo à l’écran. Fonctionne avec ton abonnement (pas de blocage cloud).",
  "en": "The channel starts on its own. Keep the app open: the phone is what sends the video to the screen. Works with your subscription (no cloud blocking).",
  "es": "El canal arranca solo. Mantén la app abierta: es el teléfono el que envía el vídeo a la pantalla. Funciona con tu suscripción (sin bloqueo de la nube).",
  "sv": "Kanalen startar av sig själv. Håll appen öppen: det är telefonen som skickar videon till skärmen. Fungerar med ditt abonnemang (ingen molnblockering).",
  "da": "Kanalen starter af sig selv. Hold appen åben: det er telefonen, der sender videoen til skærmen. Virker med dit abonnement (ingen cloud-blokering).",
  "nb": "Kanalen starter av seg selv. Hold appen åpen: det er telefonen som sender videoen til skjermen. Fungerer med abonnementet ditt (ingen skyblokkering).",
  "ar": "تبدأ القناة تلقائيًا. أبقِ التطبيق مفتوحًا: الهاتف هو من يرسل الفيديو إلى الشاشة. يعمل مع اشتراكك (بدون حجب سحابي).",
  "sw": "Kituo kinaanza chenyewe. Acha programu ikiwa wazi: simu ndiyo inayotuma video kwenye skrini. Inafanya kazi na usajili wako (hakuna kizuizi cha cloud)."
 },
 "castDiagNoChannels": {
  "fr": "Aucune chaîne chargée — ajoute d'abord une playlist.",
  "en": "No channels loaded — add a playlist first.",
  "es": "No hay canales cargados: añade primero una playlist.",
  "sv": "Inga kanaler laddade — lägg till en spellista först.",
  "da": "Ingen kanaler indlæst — tilføj en playliste først.",
  "nb": "Ingen kanaler lastet — legg til en spilleliste først.",
  "ar": "لا توجد قنوات محمّلة — أضف قائمة تشغيل أولًا.",
  "sw": "Hakuna vituo vilivyopakiwa — ongeza playlist kwanza."
 },
 "castDiagReportCopied": {
  "fr": "Rapport copié dans le presse-papier",
  "en": "Report copied to clipboard",
  "es": "Informe copiado al portapapeles",
  "sv": "Rapporten kopierad till urklipp",
  "da": "Rapport kopieret til udklipsholderen",
  "nb": "Rapport kopiert til utklippstavlen",
  "ar": "تم نسخ التقرير إلى الحافظة",
  "sw": "Ripoti imenakiliwa kwenye ubao wa kunakili"
 },
 "castDiagNetReportCopied": {
  "fr": "Rapport réseau copié dans le presse-papier",
  "en": "Network report copied to clipboard",
  "es": "Informe de red copiado al portapapeles",
  "sv": "Nätverksrapporten kopierad till urklipp",
  "da": "Netværksrapport kopieret til udklipsholderen",
  "nb": "Nettverksrapport kopiert til utklippstavlen",
  "ar": "تم نسخ تقرير الشبكة إلى الحافظة",
  "sw": "Ripoti ya mtandao imenakiliwa kwenye ubao wa kunakili"
 },
 "castDiagBlackBoxCopied": {
  "fr": "Boîte noire copiée dans le presse-papier",
  "en": "Black box copied to clipboard",
  "es": "Caja negra copiada al portapapeles",
  "sv": "Svarta lådan kopierad till urklipp",
  "da": "Sort boks kopieret til udklipsholderen",
  "nb": "Svart boks kopiert til utklippstavlen",
  "ar": "تم نسخ الصندوق الأسود إلى الحافظة",
  "sw": "Sanduku jeusi limenakiliwa kwenye ubao wa kunakili"
 },
 "castDiagTitle": {
  "fr": "Diagnostic cast",
  "en": "Cast diagnostics",
  "es": "Diagnóstico de cast",
  "sv": "Cast-diagnostik",
  "da": "Cast-diagnostik",
  "nb": "Cast-diagnostikk",
  "ar": "تشخيص البث",
  "sw": "Uchunguzi wa cast"
 },
 "castDiagCopyBlackBox": {
  "fr": "Copier la boîte noire (A→Z)",
  "en": "Copy black box (A→Z)",
  "es": "Copiar la caja negra (A→Z)",
  "sv": "Kopiera svarta lådan (A→Z)",
  "da": "Kopiér sort boks (A→Z)",
  "nb": "Kopier svart boks (A→Z)",
  "ar": "نسخ الصندوق الأسود (A→Z)",
  "sw": "Nakili sanduku jeusi (A→Z)"
 },
 "castDiagRedo": {
  "fr": "Refaire",
  "en": "Run again",
  "es": "Repetir",
  "sv": "Gör om",
  "da": "Gentag",
  "nb": "Gjør om",
  "ar": "إعادة",
  "sw": "Rudia"
 },
 "castDiagCopyReport": {
  "fr": "Copier le rapport",
  "en": "Copy report",
  "es": "Copiar informe",
  "sv": "Kopiera rapporten",
  "da": "Kopiér rapport",
  "nb": "Kopier rapport",
  "ar": "نسخ التقرير",
  "sw": "Nakili ripoti"
 },
 "castDiagIntro": {
  "fr": "Teste la compatibilité cast de ta TV en lançant plusieurs chaînes à la suite. Le rapport copiable sert à remplir la matrice de compat.",
  "en": "Test your TV's cast compatibility by playing several channels in a row. The copyable report is used to fill in the compatibility matrix.",
  "es": "Prueba la compatibilidad de cast de tu TV lanzando varios canales seguidos. El informe copiable sirve para rellenar la matriz de compatibilidad.",
  "sv": "Testa din TV:s cast-kompatibilitet genom att spela flera kanaler i rad. Den kopierbara rapporten används för att fylla i kompatibilitetsmatrisen.",
  "da": "Test dit TV's cast-kompatibilitet ved at afspille flere kanaler i træk. Den kopierbare rapport bruges til at udfylde kompatibilitetsmatricen.",
  "nb": "Test TV-ens cast-kompatibilitet ved å spille flere kanaler på rad. Den kopierbare rapporten brukes til å fylle ut kompatibilitetsmatrisen.",
  "ar": "اختبر توافق البث مع تلفازك بتشغيل عدة قنوات متتالية. يُستخدم التقرير القابل للنسخ لملء مصفوفة التوافق.",
  "sw": "Jaribu uoanifu wa cast wa TV yako kwa kucheza vituo kadhaa mfululizo. Ripoti inayoweza kunakiliwa hutumika kujaza jedwali la uoanifu."
 },
 "castDiagReceiverLabel": {
  "fr": "Récepteur",
  "en": "Receiver",
  "es": "Receptor",
  "sv": "Mottagare",
  "da": "Modtager",
  "nb": "Mottaker",
  "ar": "المستقبِل",
  "sw": "Kipokezi"
 },
 "castDiagSearchingHint": {
  "fr": "Recherche en cours… Vérifie que ta TV est sur le même WiFi.",
  "en": "Searching… Check that your TV is on the same WiFi.",
  "es": "Buscando… Comprueba que tu TV está en el mismo WiFi.",
  "sv": "Söker… Kontrollera att din TV är på samma WiFi.",
  "da": "Søger… Tjek at dit TV er på samme WiFi.",
  "nb": "Søker… Sjekk at TV-en din er på samme WiFi.",
  "ar": "جارٍ البحث… تأكد أن تلفازك على نفس شبكة WiFi.",
  "sw": "Inatafuta… Hakikisha TV yako iko kwenye WiFi ile ile."
 },
 "castDiagTestSize": {
  "fr": "Taille du test",
  "en": "Test size",
  "es": "Tamaño de la prueba",
  "sv": "Teststorlek",
  "da": "Teststørrelse",
  "nb": "Teststørrelse",
  "ar": "حجم الاختبار",
  "sw": "Ukubwa wa jaribio"
 },
 "castDiagStart": {
  "fr": "Lancer le diagnostic",
  "en": "Start diagnostics",
  "es": "Iniciar diagnóstico",
  "sv": "Starta diagnostiken",
  "da": "Start diagnostik",
  "nb": "Start diagnostikk",
  "ar": "بدء التشخيص",
  "sw": "Anzisha uchunguzi"
 },
 "castDiagSelectReceiver": {
  "fr": "Sélectionne un récepteur",
  "en": "Select a receiver",
  "es": "Selecciona un receptor",
  "sv": "Välj en mottagare",
  "da": "Vælg en modtager",
  "nb": "Velg en mottaker",
  "ar": "اختر مستقبِلًا",
  "sw": "Chagua kipokezi"
 },
 "castDiagRunProgress": {
  "fr": "Test {done}/{total} — {channel}",
  "en": "Test {done}/{total} — {channel}",
  "es": "Prueba {done}/{total} — {channel}",
  "sv": "Test {done}/{total} — {channel}",
  "da": "Test {done}/{total} — {channel}",
  "nb": "Test {done}/{total} — {channel}",
  "ar": "اختبار {done}/{total} — {channel}",
  "sw": "Jaribio {done}/{total} — {channel}"
 },
 "castDiagCancelledAfter": {
  "fr": "Annulé après {done}/{total} tests",
  "en": "Cancelled after {done}/{total} tests",
  "es": "Cancelado tras {done}/{total} pruebas",
  "sv": "Avbrutet efter {done}/{total} test",
  "da": "Annulleret efter {done}/{total} test",
  "nb": "Avbrutt etter {done}/{total} tester",
  "ar": "أُلغي بعد {done}/{total} من الاختبارات",
  "sw": "Imesitishwa baada ya majaribio {done}/{total}"
 },
 "castDiagFinished": {
  "fr": "Terminé — {done}/{total} tests",
  "en": "Done — {done}/{total} tests",
  "es": "Terminado: {done}/{total} pruebas",
  "sv": "Klart — {done}/{total} test",
  "da": "Færdig — {done}/{total} test",
  "nb": "Ferdig — {done}/{total} tester",
  "ar": "اكتمل — {done}/{total} من الاختبارات",
  "sw": "Imekamilika — majaribio {done}/{total}"
 },
 "castDiagWaitingFirstResult": {
  "fr": "En attente du premier résultat…",
  "en": "Waiting for the first result…",
  "es": "Esperando el primer resultado…",
  "sv": "Väntar på det första resultatet…",
  "da": "Venter på det første resultat…",
  "nb": "Venter på det første resultatet…",
  "ar": "في انتظار النتيجة الأولى…",
  "sw": "Inasubiri matokeo ya kwanza…"
 },
 "castDiagChannelFallback": {
  "fr": "Chaîne",
  "en": "Channel",
  "es": "Canal",
  "sv": "Kanal",
  "da": "Kanal",
  "nb": "Kanal",
  "ar": "قناة",
  "sw": "Kituo"
 },
 "castDiagFailed": {
  "fr": "Échec",
  "en": "Failed",
  "es": "Error",
  "sv": "Misslyckades",
  "da": "Mislykkedes",
  "nb": "Mislyktes",
  "ar": "فشل",
  "sw": "Imeshindikana"
 },
 "castDiagSuccessRate": {
  "fr": "Taux de succès : {rate}% ({ok} / {total})",
  "en": "Success rate: {rate}% ({ok} / {total})",
  "es": "Tasa de éxito: {rate}% ({ok} / {total})",
  "sv": "Andel lyckade: {rate}% ({ok} / {total})",
  "da": "Succesrate: {rate}% ({ok} / {total})",
  "nb": "Suksessrate: {rate}% ({ok} / {total})",
  "ar": "معدل النجاح: {rate}% ({ok} / {total})",
  "sw": "Kiwango cha mafanikio: {rate}% ({ok} / {total})"
 },
 "castDiagAvgLatency": {
  "fr": "Latence moyenne au succès : {latency}",
  "en": "Average latency to success: {latency}",
  "es": "Latencia media hasta el éxito: {latency}",
  "sv": "Genomsnittlig latens vid lyckat försök: {latency}",
  "da": "Gennemsnitlig latenstid ved succes: {latency}",
  "nb": "Gjennomsnittlig latens ved suksess: {latency}",
  "ar": "متوسط زمن الاستجابة عند النجاح: {latency}",
  "sw": "Muda wa wastani hadi mafanikio: {latency}"
 },
 "castDiagWinningStrategies": {
  "fr": "Stratégies gagnantes : {list}",
  "en": "Winning strategies: {list}",
  "es": "Estrategias ganadoras: {list}",
  "sv": "Vinnande strategier: {list}",
  "da": "Vindende strategier: {list}",
  "nb": "Vinnende strategier: {list}",
  "ar": "الاستراتيجيات الناجحة: {list}",
  "sw": "Mbinu zilizofaulu: {list}"
 },
 "castDiagNetRunning": {
  "fr": "Diagnostic réseau en cours…",
  "en": "Network diagnostics running…",
  "es": "Diagnóstico de red en curso…",
  "sv": "Nätverksdiagnostik pågår…",
  "da": "Netværksdiagnostik i gang…",
  "nb": "Nettverksdiagnostikk pågår…",
  "ar": "تشخيص الشبكة جارٍ…",
  "sw": "Uchunguzi wa mtandao unaendelea…"
 },
 "castDiagNetButton": {
  "fr": "Diagnostic réseau cast",
  "en": "Cast network diagnostics",
  "es": "Diagnóstico de red del cast",
  "sv": "Nätverksdiagnostik för cast",
  "da": "Netværksdiagnostik for cast",
  "nb": "Nettverksdiagnostikk for cast",
  "ar": "تشخيص شبكة البث",
  "sw": "Uchunguzi wa mtandao wa cast"
 },
 "castDiagNetReportTitle": {
  "fr": "Rapport réseau cast",
  "en": "Cast network report",
  "es": "Informe de red del cast",
  "sv": "Nätverksrapport för cast",
  "da": "Netværksrapport for cast",
  "nb": "Nettverksrapport for cast",
  "ar": "تقرير شبكة البث",
  "sw": "Ripoti ya mtandao wa cast"
 },
 "playerChannelBlocked": {
  "fr": "Chaîne indisponible : aucune vidéo reçue. Elle est vide ou bloquée par ta source — vérifie qu'elle n'est pas déjà ouverte sur un autre appareil, sinon essaie une autre chaîne.",
  "en": "Channel unavailable: no video received. It's empty or blocked by your source — check it isn't already open on another device, otherwise try another channel.",
  "es": "Canal no disponible: no se recibió vídeo. Está vacío o bloqueado por tu fuente; comprueba que no esté ya abierto en otro dispositivo o prueba otro canal.",
  "sv": "Kanalen är otillgänglig: ingen video togs emot. Den är tom eller blockerad av din källa — kontrollera att den inte redan är öppen på en annan enhet, annars prova en annan kanal.",
  "da": "Kanalen er utilgængelig: ingen video modtaget. Den er tom eller blokeret af din kilde — tjek at den ikke allerede er åben på en anden enhed, ellers prøv en anden kanal.",
  "nb": "Kanalen er utilgjengelig: ingen video mottatt. Den er tom eller blokkert av kilden din — sjekk at den ikke allerede er åpen på en annen enhet, ellers prøv en annen kanal.",
  "ar": "القناة غير متاحة: لم يصل أي فيديو. إنها فارغة أو محجوبة من مصدرك — تأكد أنها ليست مفتوحة بالفعل على جهاز آخر، وإلا جرّب قناة أخرى.",
  "sw": "Kituo hakipatikani: hakuna video iliyopokelewa. Ni tupu au kimezuiwa na chanzo chako — hakikisha hakijafunguliwa tayari kwenye kifaa kingine, la sivyo jaribu kituo kingine."
 },
 "playerNetworkBlockHint": {
  "fr": "Ça ressemble à un blocage réseau (FAI ou DNS) plutôt qu'à un problème de l'app — un VPN peut aider si cette chaîne fonctionne ailleurs.",
  "en": "This looks like a network block (ISP or DNS) rather than an app problem — a VPN may help if this channel works elsewhere.",
  "es": "Parece un bloqueo de red (operador o DNS) más que un problema de la app; una VPN puede ayudar si este canal funciona en otro sitio.",
  "sv": "Det här ser ut som en nätverksblockering (internetleverantör eller DNS) snarare än ett problem med appen — en VPN kan hjälpa om kanalen fungerar någon annanstans.",
  "da": "Det ligner en netværksblokering (internetudbyder eller DNS) snarere end et problem med appen — en VPN kan hjælpe, hvis kanalen virker andre steder.",
  "nb": "Dette ser ut som en nettverksblokkering (internettleverandør eller DNS) heller enn et problem med appen — en VPN kan hjelpe hvis kanalen fungerer andre steder.",
  "ar": "يبدو هذا حجبًا من الشبكة (مزوّد الإنترنت أو DNS) وليس مشكلة في التطبيق — قد تساعد شبكة VPN إذا كانت هذه القناة تعمل في مكان آخر.",
  "sw": "Hii inaonekana kama kizuizi cha mtandao (mtoa huduma au DNS) badala ya tatizo la programu — VPN inaweza kusaidia ikiwa kituo hiki kinafanya kazi kwingineko."
 },
 "playerStreamInterrupted": {
  "fr": "Flux interrompu. Vérifie ta connexion puis réessaie.",
  "en": "Stream interrupted. Check your connection and try again.",
  "es": "Transmisión interrumpida. Comprueba tu conexión y vuelve a intentarlo.",
  "sv": "Strömmen avbröts. Kontrollera din anslutning och försök igen.",
  "da": "Streamen blev afbrudt. Tjek din forbindelse, og prøv igen.",
  "nb": "Strømmen ble avbrutt. Sjekk tilkoblingen din og prøv igjen.",
  "ar": "انقطع البث. تحقق من اتصالك ثم أعد المحاولة.",
  "sw": "Mtiririko umekatika. Angalia muunganisho wako kisha ujaribu tena."
 },
 "playerScreenButton": {
  "fr": "Écran",
  "en": "Screen",
  "es": "Pantalla",
  "sv": "Skärm",
  "da": "Skærm",
  "nb": "Skjerm",
  "ar": "شاشة",
  "sw": "Skrini"
 },
 "playerGoLiveLabel": {
  "fr": "En direct",
  "en": "Live",
  "es": "En directo",
  "sv": "Live",
  "da": "Live",
  "nb": "Direkte",
  "ar": "مباشر",
  "sw": "Moja kwa moja"
 },
 "playerTvFallback": {
  "fr": "la TV",
  "en": "the TV",
  "es": "la TV",
  "sv": "TV:n",
  "da": "TV'et",
  "nb": "TV-en",
  "ar": "التلفاز",
  "sw": "TV"
 },
 "playerConnectingTo": {
  "fr": "Connexion à {device}…",
  "en": "Connecting to {device}…",
  "es": "Conectando con {device}…",
  "sv": "Ansluter till {device}…",
  "da": "Opretter forbindelse til {device}…",
  "nb": "Kobler til {device}…",
  "ar": "جارٍ الاتصال بـ {device}…",
  "sw": "Inaunganisha na {device}…"
 },
 "playerCastingOn": {
  "fr": "Diffusion sur {device}",
  "en": "Playing on {device}",
  "es": "Reproduciendo en {device}",
  "sv": "Spelas på {device}",
  "da": "Afspiller på {device}",
  "nb": "Spilles på {device}",
  "ar": "يُعرض على {device}",
  "sw": "Inaonyeshwa kwenye {device}"
 },
 "playerCastHandoffHint": {
  "fr": "La lecture continue sur la TV. Le téléphone est libéré pour ne pas bloquer la connexion IPTV.",
  "en": "Playback continues on the TV. The phone is freed up so it doesn't block the IPTV connection.",
  "es": "La reproducción continúa en la TV. El teléfono queda libre para no bloquear la conexión IPTV.",
  "sv": "Uppspelningen fortsätter på TV:n. Telefonen frigörs så att den inte blockerar IPTV-anslutningen.",
  "da": "Afspilningen fortsætter på TV'et. Telefonen frigives, så den ikke blokerer IPTV-forbindelsen.",
  "nb": "Avspillingen fortsetter på TV-en. Telefonen frigjøres slik at den ikke blokkerer IPTV-tilkoblingen.",
  "ar": "يستمر التشغيل على التلفاز. تم تحرير الهاتف حتى لا يحجز اتصال IPTV.",
  "sw": "Uchezaji unaendelea kwenye TV. Simu imeachiliwa ili isizuie muunganisho wa IPTV."
 },
 "adminMissingCreds": {
  "fr": "URL serveur ou secret admin manquant.",
  "en": "Server URL or admin secret missing.",
  "es": "Falta la URL del servidor o el secreto de admin.",
  "sv": "Server-URL eller admin-hemlighet saknas.",
  "da": "Server-URL eller admin-hemmelighed mangler.",
  "nb": "Server-URL eller admin-hemmelighet mangler.",
  "ar": "عنوان الخادم أو سر المشرف مفقود.",
  "sw": "URL ya seva au siri ya admin haipo."
 },
 "adminUrlSecretRequired": {
  "fr": "URL et secret obligatoires.",
  "en": "URL and secret are required.",
  "es": "URL y secreto obligatorios.",
  "sv": "URL och hemlighet krävs.",
  "da": "URL og hemmelighed er påkrævet.",
  "nb": "URL og hemmelighet er påkrevd.",
  "ar": "العنوان والسر إلزاميان.",
  "sw": "URL na siri zinahitajika."
 },
 "adminServerConfigured": {
  "fr": "Serveur configuré. Tu peux maintenant ajouter des clients.",
  "en": "Server configured. You can now add clients.",
  "es": "Servidor configurado. Ya puedes añadir clientes.",
  "sv": "Servern är konfigurerad. Nu kan du lägga till kunder.",
  "da": "Serveren er konfigureret. Du kan nu tilføje kunder.",
  "nb": "Serveren er konfigurert. Nå kan du legge til kunder.",
  "ar": "تم إعداد الخادم. يمكنك الآن إضافة عملاء.",
  "sw": "Seva imesanidiwa. Sasa unaweza kuongeza wateja."
 },
 "adminConfigureFirst": {
  "fr": "Configure d'abord URL serveur + secret admin.",
  "en": "First set up the server URL + admin secret.",
  "es": "Configura primero la URL del servidor + el secreto de admin.",
  "sv": "Ställ först in server-URL + admin-hemlighet.",
  "da": "Konfigurér først server-URL + admin-hemmelighed.",
  "nb": "Sett først opp server-URL + admin-hemmelighet.",
  "ar": "قم أولًا بإعداد عنوان الخادم + سر المشرف.",
  "sw": "Kwanza sanidi URL ya seva + siri ya admin."
 },
 "adminClientSaved": {
  "fr": "Client enregistré. Visible côté client à sa prochaine sync.",
  "en": "Client saved. Visible on the client side at their next sync.",
  "es": "Cliente guardado. Visible en el lado del cliente en su próxima sincronización.",
  "sv": "Kunden sparades. Syns hos kunden vid nästa synk.",
  "da": "Kunden er gemt. Synlig hos kunden ved næste synkronisering.",
  "nb": "Kunden er lagret. Synlig hos kunden ved neste synkronisering.",
  "ar": "تم حفظ العميل. سيظهر لدى العميل عند مزامنته التالية.",
  "sw": "Mteja amehifadhiwa. Ataonekana upande wa mteja kwenye usawazishaji wake ujao."
 },
 "adminMacExists": {
  "fr": "Un client avec cette MAC existe déjà. Modifie-le au lieu d'en créer un nouveau.",
  "en": "A client with this MAC already exists. Edit it instead of creating a new one.",
  "es": "Ya existe un cliente con esta MAC. Modifícalo en lugar de crear uno nuevo.",
  "sv": "En kund med denna MAC finns redan. Redigera den istället för att skapa en ny.",
  "da": "En kunde med denne MAC findes allerede. Redigér den i stedet for at oprette en ny.",
  "nb": "En kunde med denne MAC-en finnes allerede. Rediger den i stedet for å opprette en ny.",
  "ar": "يوجد بالفعل عميل بهذا العنوان MAC. عدّله بدلًا من إنشاء عميل جديد.",
  "sw": "Mteja mwenye MAC hii tayari yupo. Mhariri badala ya kuunda mpya."
 },
 "adminDeleteClientTitle": {
  "fr": "Supprimer ce client ?",
  "en": "Delete this client?",
  "es": "¿Eliminar este cliente?",
  "sv": "Ta bort denna kund?",
  "da": "Slet denne kunde?",
  "nb": "Slette denne kunden?",
  "ar": "حذف هذا العميل؟",
  "sw": "Ufute mteja huyu?"
 },
 "adminDeleteClientBody": {
  "fr": "La MAC {mac} ne recevra plus de playlist. L'app cliente videra ses chaînes à la prochaine sync.",
  "en": "MAC {mac} will no longer receive a playlist. The client app will clear its channels at the next sync.",
  "es": "La MAC {mac} dejará de recibir playlist. La app del cliente vaciará sus canales en la próxima sincronización.",
  "sv": "MAC {mac} kommer inte längre att få någon spellista. Kundappen tömmer sina kanaler vid nästa synk.",
  "da": "MAC {mac} vil ikke længere modtage en playliste. Kunde-appen rydder sine kanaler ved næste synkronisering.",
  "nb": "MAC {mac} vil ikke lenger motta noen spilleliste. Klientappen tømmer kanalene sine ved neste synkronisering.",
  "ar": "لن يتلقى العنوان {mac} أي قائمة تشغيل بعد الآن. سيُفرغ تطبيق العميل قنواته عند المزامنة التالية.",
  "sw": "MAC {mac} haitapokea tena playlist. Programu ya mteja itafuta vituo vyake kwenye usawazishaji ujao."
 },
 "adminMacCopied": {
  "fr": "MAC copiée : {mac}",
  "en": "MAC copied: {mac}",
  "es": "MAC copiada: {mac}",
  "sv": "MAC kopierad: {mac}",
  "da": "MAC kopieret: {mac}",
  "nb": "MAC kopiert: {mac}",
  "ar": "تم نسخ MAC: {mac}",
  "sw": "MAC imenakiliwa: {mac}"
 },
 "adminTitle": {
  "fr": "Admin",
  "en": "Admin",
  "es": "Admin",
  "sv": "Admin",
  "da": "Admin",
  "nb": "Admin",
  "ar": "المشرف",
  "sw": "Admin"
 },
 "adminReloadTooltip": {
  "fr": "Recharger",
  "en": "Reload",
  "es": "Recargar",
  "sv": "Ladda om",
  "da": "Genindlæs",
  "nb": "Last inn på nytt",
  "ar": "إعادة التحميل",
  "sw": "Pakia upya"
 },
 "adminNewClient": {
  "fr": "Nouveau client",
  "en": "New client",
  "es": "Nuevo cliente",
  "sv": "Ny kund",
  "da": "Ny kunde",
  "nb": "Ny kunde",
  "ar": "عميل جديد",
  "sw": "Mteja mpya"
 },
 "adminServerConnected": {
  "fr": "Serveur connecté",
  "en": "Server connected",
  "es": "Servidor conectado",
  "sv": "Servern ansluten",
  "da": "Server forbundet",
  "nb": "Server tilkoblet",
  "ar": "الخادم متصل",
  "sw": "Seva imeunganishwa"
 },
 "adminEditButton": {
  "fr": "Modifier",
  "en": "Edit",
  "es": "Modificar",
  "sv": "Ändra",
  "da": "Redigér",
  "nb": "Rediger",
  "ar": "تعديل",
  "sw": "Hariri"
 },
 "adminServerConnection": {
  "fr": "Connexion serveur",
  "en": "Server connection",
  "es": "Conexión al servidor",
  "sv": "Serveranslutning",
  "da": "Serverforbindelse",
  "nb": "Servertilkobling",
  "ar": "اتصال الخادم",
  "sw": "Muunganisho wa seva"
 },
 "adminCollapse": {
  "fr": "Replier",
  "en": "Collapse",
  "es": "Plegar",
  "sv": "Fäll ihop",
  "da": "Fold sammen",
  "nb": "Skjul",
  "ar": "طيّ",
  "sw": "Kunja"
 },
 "adminSetupIntro": {
  "fr": "Setup une seule fois. Déploie ton mini-backend Cloudflare (15 min, voir cloudflare/README.md), puis colle l'URL + ton secret admin ci-dessous.",
  "en": "One-time setup. Deploy your Cloudflare mini-backend (15 min, see cloudflare/README.md), then paste the URL + your admin secret below.",
  "es": "Se configura una sola vez. Despliega tu mini-backend de Cloudflare (15 min, ver cloudflare/README.md) y pega abajo la URL + tu secreto de admin.",
  "sv": "Engångsinstallation. Distribuera din Cloudflare-minibackend (15 min, se cloudflare/README.md) och klistra sedan in URL:en + din admin-hemlighet nedan.",
  "da": "Engangsopsætning. Udrul din Cloudflare-minibackend (15 min, se cloudflare/README.md), og indsæt derefter URL'en + din admin-hemmelighed nedenfor.",
  "nb": "Engangsoppsett. Distribuer Cloudflare-minibackenden din (15 min, se cloudflare/README.md), og lim deretter inn URL-en + admin-hemmeligheten din nedenfor.",
  "ar": "إعداد لمرة واحدة. انشر خادم Cloudflare المصغّر (15 دقيقة، انظر cloudflare/README.md)، ثم الصق العنوان + سر المشرف أدناه.",
  "sw": "Usanidi wa mara moja tu. Sambaza mini-backend yako ya Cloudflare (dakika 15, angalia cloudflare/README.md), kisha bandika URL + siri yako ya admin hapa chini."
 },
 "adminServerUrlLabel": {
  "fr": "URL du serveur",
  "en": "Server URL",
  "es": "URL del servidor",
  "sv": "Server-URL",
  "da": "Server-URL",
  "nb": "Server-URL",
  "ar": "عنوان الخادم",
  "sw": "URL ya seva"
 },
 "adminSecretLabel": {
  "fr": "Secret admin",
  "en": "Admin secret",
  "es": "Secreto de admin",
  "sv": "Admin-hemlighet",
  "da": "Admin-hemmelighed",
  "nb": "Admin-hemmelighet",
  "ar": "سر المشرف",
  "sw": "Siri ya admin"
 },
 "adminSecretHint": {
  "fr": "Celui défini avec `wrangler secret put ADMIN_SECRET`",
  "en": "The one set with `wrangler secret put ADMIN_SECRET`",
  "es": "El definido con `wrangler secret put ADMIN_SECRET`",
  "sv": "Den som angavs med `wrangler secret put ADMIN_SECRET`",
  "da": "Den, der blev sat med `wrangler secret put ADMIN_SECRET`",
  "nb": "Den som ble satt med `wrangler secret put ADMIN_SECRET`",
  "ar": "السر المحدد عبر `wrangler secret put ADMIN_SECRET`",
  "sw": "Ile iliyowekwa kwa `wrangler secret put ADMIN_SECRET`"
 },
 "adminDeployHint": {
  "fr": "Pas encore déployé ? Suis cloudflare/README.md dans le repo. Cloudflare Worker est gratuit jusqu'à 100k req/jour.",
  "en": "Not deployed yet? Follow cloudflare/README.md in the repo. Cloudflare Worker is free up to 100k req/day.",
  "es": "¿Aún no lo has desplegado? Sigue cloudflare/README.md en el repo. Cloudflare Worker es gratis hasta 100k req/día.",
  "sv": "Inte distribuerad än? Följ cloudflare/README.md i repot. Cloudflare Worker är gratis upp till 100k förfrågningar/dag.",
  "da": "Ikke udrullet endnu? Følg cloudflare/README.md i repoet. Cloudflare Worker er gratis op til 100k forespørgsler/dag.",
  "nb": "Ikke distribuert ennå? Følg cloudflare/README.md i repoet. Cloudflare Worker er gratis opptil 100k forespørsler/dag.",
  "ar": "لم تنشره بعد؟ اتبع cloudflare/README.md في المستودع. Cloudflare Worker مجاني حتى 100 ألف طلب/يوم.",
  "sw": "Bado hujasambaza? Fuata cloudflare/README.md kwenye repo. Cloudflare Worker ni bure hadi maombi 100k kwa siku."
 },
 "adminSaveAndTest": {
  "fr": "Enregistrer et tester",
  "en": "Save and test",
  "es": "Guardar y probar",
  "sv": "Spara och testa",
  "da": "Gem og test",
  "nb": "Lagre og test",
  "ar": "حفظ واختبار",
  "sw": "Hifadhi na ujaribu"
 },
 "adminClientsHeader": {
  "fr": "CLIENTS",
  "en": "CLIENTS",
  "es": "CLIENTES",
  "sv": "KUNDER",
  "da": "KUNDER",
  "nb": "KUNDER",
  "ar": "العملاء",
  "sw": "WATEJA"
 },
 "adminUnnamed": {
  "fr": "Sans nom",
  "en": "Unnamed",
  "es": "Sin nombre",
  "sv": "Namnlös",
  "da": "Uden navn",
  "nb": "Uten navn",
  "ar": "بدون اسم",
  "sw": "Bila jina"
 },
 "adminPlaylistCount": {
  "fr": "{count, plural, =1{1 playlist} other{{count} playlists}}",
  "en": "{count, plural, =1{1 playlist} other{{count} playlists}}",
  "es": "{count, plural, =1{1 playlist} other{{count} playlists}}",
  "sv": "{count, plural, =1{1 spellista} other{{count} spellistor}}",
  "da": "{count, plural, =1{1 playliste} other{{count} playlister}}",
  "nb": "{count, plural, =1{1 spilleliste} other{{count} spillelister}}",
  "ar": "{count, plural, =1{قائمة تشغيل واحدة} other{{count} قوائم تشغيل}}",
  "sw": "{count, plural, =1{playlist 1} other{playlist {count}}}"
 },
 "adminNoClientsTitle": {
  "fr": "Aucun client pour l'instant",
  "en": "No clients yet",
  "es": "Ningún cliente por ahora",
  "sv": "Inga kunder ännu",
  "da": "Ingen kunder endnu",
  "nb": "Ingen kunder ennå",
  "ar": "لا يوجد عملاء بعد",
  "sw": "Hakuna wateja bado"
 },
 "adminNoClientsHint": {
  "fr": "Tape sur le bouton ci-dessous, colle la MAC que ton client t'a envoyée + son URL M3U. C'est tout.",
  "en": "Tap the button below, paste the MAC your client sent you + their M3U URL. That's it.",
  "es": "Toca el botón de abajo, pega la MAC que te envió tu cliente + su URL M3U. Eso es todo.",
  "sv": "Tryck på knappen nedan, klistra in MAC-adressen som din kund skickade + deras M3U-URL. Det är allt.",
  "da": "Tryk på knappen nedenfor, indsæt den MAC, din kunde sendte dig, + deres M3U-URL. Det er det hele.",
  "nb": "Trykk på knappen nedenfor, lim inn MAC-en kunden din sendte deg + M3U-URL-en deres. Det er alt.",
  "ar": "اضغط على الزر أدناه، والصق عنوان MAC الذي أرسله عميلك + رابط M3U الخاص به. هذا كل شيء.",
  "sw": "Gusa kitufe hapa chini, bandika MAC ambayo mteja wako alikutumia + URL yake ya M3U. Ndivyo tu."
 },
 "adminAddFirstClient": {
  "fr": "Ajouter mon premier client",
  "en": "Add my first client",
  "es": "Añadir mi primer cliente",
  "sv": "Lägg till min första kund",
  "da": "Tilføj min første kunde",
  "nb": "Legg til min første kunde",
  "ar": "إضافة عميلي الأول",
  "sw": "Ongeza mteja wangu wa kwanza"
 },
 "adminPinConfirmTitle": {
  "fr": "Confirme ton code",
  "en": "Confirm your code",
  "es": "Confirma tu código",
  "sv": "Bekräfta din kod",
  "da": "Bekræft din kode",
  "nb": "Bekreft koden din",
  "ar": "أكّد رمزك",
  "sw": "Thibitisha msimbo wako"
 },
 "adminPinCreateTitle": {
  "fr": "Crée ton code admin",
  "en": "Create your admin code",
  "es": "Crea tu código de admin",
  "sv": "Skapa din admin-kod",
  "da": "Opret din admin-kode",
  "nb": "Opprett admin-koden din",
  "ar": "أنشئ رمز المشرف الخاص بك",
  "sw": "Unda msimbo wako wa admin"
 },
 "adminPinTitle": {
  "fr": "Code admin",
  "en": "Admin code",
  "es": "Código de admin",
  "sv": "Admin-kod",
  "da": "Admin-kode",
  "nb": "Admin-kode",
  "ar": "رمز المشرف",
  "sw": "Msimbo wa admin"
 },
 "adminPinCreateHint": {
  "fr": "{count} chiffres. Personne d'autre n'aura cet accès.",
  "en": "{count} digits. No one else will have this access.",
  "es": "{count} dígitos. Nadie más tendrá este acceso.",
  "sv": "{count} siffror. Ingen annan får den här åtkomsten.",
  "da": "{count} cifre. Ingen andre får denne adgang.",
  "nb": "{count} sifre. Ingen andre får denne tilgangen.",
  "ar": "{count} أرقام. لن يحصل أي شخص آخر على هذا الوصول.",
  "sw": "Tarakimu {count}. Hakuna mtu mwingine atakayepata ufikiaji huu."
 },
 "adminPinConfirmHint": {
  "fr": "Retape le même code pour confirmer.",
  "en": "Type the same code again to confirm.",
  "es": "Vuelve a escribir el mismo código para confirmar.",
  "sv": "Skriv samma kod igen för att bekräfta.",
  "da": "Indtast den samme kode igen for at bekræfte.",
  "nb": "Skriv inn den samme koden igjen for å bekrefte.",
  "ar": "أعد إدخال الرمز نفسه للتأكيد.",
  "sw": "Andika msimbo uleule tena kuthibitisha."
 },
 "adminPinEnterHint": {
  "fr": "Entre ton code pour accéder au mode admin.",
  "en": "Enter your code to access admin mode.",
  "es": "Introduce tu código para acceder al modo admin.",
  "sv": "Ange din kod för att komma åt admin-läget.",
  "da": "Indtast din kode for at få adgang til admin-tilstand.",
  "nb": "Skriv inn koden din for å få tilgang til admin-modus.",
  "ar": "أدخل رمزك للوصول إلى وضع المشرف.",
  "sw": "Weka msimbo wako kufikia hali ya admin."
 },
 "adminPinMismatch": {
  "fr": "Les deux codes ne correspondent pas.",
  "en": "The two codes don't match.",
  "es": "Los dos códigos no coinciden.",
  "sv": "De två koderna stämmer inte överens.",
  "da": "De to koder stemmer ikke overens.",
  "nb": "De to kodene stemmer ikke overens.",
  "ar": "الرمزان غير متطابقين.",
  "sw": "Misimbo miwili hailingani."
 },
 "adminPinTooManyAttempts": {
  "fr": "Trop de tentatives. Reviens dans une minute.",
  "en": "Too many attempts. Come back in a minute.",
  "es": "Demasiados intentos. Vuelve en un minuto.",
  "sv": "För många försök. Kom tillbaka om en minut.",
  "da": "For mange forsøg. Kom tilbage om et minut.",
  "nb": "For mange forsøk. Kom tilbake om et minutt.",
  "ar": "محاولات كثيرة جدًا. عد بعد دقيقة.",
  "sw": "Majaribio mengi mno. Rudi baada ya dakika moja."
 },
 "adminPinAccessTitle": {
  "fr": "Accès admin",
  "en": "Admin access",
  "es": "Acceso admin",
  "sv": "Admin-åtkomst",
  "da": "Admin-adgang",
  "nb": "Admin-tilgang",
  "ar": "وصول المشرف",
  "sw": "Ufikiaji wa admin"
 },
 "adminMacInvalid": {
  "fr": "MAC invalide. Format attendu : MK:AA:BB:CC:DD:EE",
  "en": "Invalid MAC. Expected format: MK:AA:BB:CC:DD:EE",
  "es": "MAC no válida. Formato esperado: MK:AA:BB:CC:DD:EE",
  "sv": "Ogiltig MAC. Förväntat format: MK:AA:BB:CC:DD:EE",
  "da": "Ugyldig MAC. Forventet format: MK:AA:BB:CC:DD:EE",
  "nb": "Ugyldig MAC. Forventet format: MK:AA:BB:CC:DD:EE",
  "ar": "عنوان MAC غير صالح. التنسيق المتوقع: MK:AA:BB:CC:DD:EE",
  "sw": "MAC si sahihi. Muundo unaotarajiwa: MK:AA:BB:CC:DD:EE"
 },
 "adminM3uRequired": {
  "fr": "L'URL M3U est obligatoire.",
  "en": "The M3U URL is required.",
  "es": "La URL M3U es obligatoria.",
  "sv": "M3U-URL:en krävs.",
  "da": "M3U-URL'en er påkrævet.",
  "nb": "M3U-URL-en er påkrevd.",
  "ar": "رابط M3U إلزامي.",
  "sw": "URL ya M3U inahitajika."
 },
 "adminXtreamFieldsRequired": {
  "fr": "Serveur, utilisateur ET mot de passe sont requis.",
  "en": "Server, username AND password are required.",
  "es": "Servidor, usuario Y contraseña son obligatorios.",
  "sv": "Server, användarnamn OCH lösenord krävs.",
  "da": "Server, brugernavn OG adgangskode er påkrævet.",
  "nb": "Server, brukernavn OG passord er påkrevd.",
  "ar": "الخادم واسم المستخدم وكلمة المرور كلها مطلوبة.",
  "sw": "Seva, jina la mtumiaji NA nenosiri vinahitajika."
 },
 "adminDefaultPlaylistName": {
  "fr": "Abonnement IPTV",
  "en": "IPTV subscription",
  "es": "Suscripción IPTV",
  "sv": "IPTV-abonnemang",
  "da": "IPTV-abonnement",
  "nb": "IPTV-abonnement",
  "ar": "اشتراك IPTV",
  "sw": "Usajili wa IPTV"
 },
 "adminEditClientTitle": {
  "fr": "Modifier le client",
  "en": "Edit client",
  "es": "Modificar cliente",
  "sv": "Redigera kund",
  "da": "Redigér kunde",
  "nb": "Rediger kunde",
  "ar": "تعديل العميل",
  "sw": "Hariri mteja"
 },
 "adminClientMacLabel": {
  "fr": "MAC du client",
  "en": "Client MAC",
  "es": "MAC del cliente",
  "sv": "Kundens MAC",
  "da": "Kundens MAC",
  "nb": "Kundens MAC",
  "ar": "عنوان MAC للعميل",
  "sw": "MAC ya mteja"
 },
 "adminClientNameLabel": {
  "fr": "Nom du client (optionnel)",
  "en": "Client name (optional)",
  "es": "Nombre del cliente (opcional)",
  "sv": "Kundens namn (valfritt)",
  "da": "Kundens navn (valgfrit)",
  "nb": "Kundens navn (valgfritt)",
  "ar": "اسم العميل (اختياري)",
  "sw": "Jina la mteja (hiari)"
 },
 "adminClientNameHint": {
  "fr": "Ex : Lionel, Salon, Maman…",
  "en": "E.g. Lionel, Living room, Mom…",
  "es": "Ej.: Lionel, Salón, Mamá…",
  "sv": "T.ex. Lionel, Vardagsrummet, Mamma…",
  "da": "F.eks. Lionel, Stuen, Mor…",
  "nb": "F.eks. Lionel, Stua, Mamma…",
  "ar": "مثال: ليونيل، الصالة، ماما…",
  "sw": "Mf.: Lionel, Sebule, Mama…"
 },
 "adminPlaylistSection": {
  "fr": "PLAYLIST",
  "en": "PLAYLIST",
  "es": "PLAYLIST",
  "sv": "SPELLISTA",
  "da": "PLAYLISTE",
  "nb": "SPILLELISTE",
  "ar": "قائمة التشغيل",
  "sw": "PLAYLIST"
 },
 "adminPlaylistNameLabel": {
  "fr": "Nom de la playlist (optionnel)",
  "en": "Playlist name (optional)",
  "es": "Nombre de la playlist (opcional)",
  "sv": "Spellistans namn (valfritt)",
  "da": "Playlistens navn (valgfrit)",
  "nb": "Spillelistens navn (valgfritt)",
  "ar": "اسم قائمة التشغيل (اختياري)",
  "sw": "Jina la playlist (hiari)"
 },
 "adminPlaylistNameHint": {
  "fr": "Défaut : \"Abonnement IPTV\"",
  "en": "Default: \"IPTV subscription\"",
  "es": "Por defecto: \"Suscripción IPTV\"",
  "sv": "Standard: \"IPTV-abonnemang\"",
  "da": "Standard: \"IPTV-abonnement\"",
  "nb": "Standard: \"IPTV-abonnement\"",
  "ar": "الافتراضي: \"اشتراك IPTV\"",
  "sw": "Chaguomsingi: \"Usajili wa IPTV\""
 },
 "adminEpgUrlLabel": {
  "fr": "URL EPG (optionnel)",
  "en": "EPG URL (optional)",
  "es": "URL EPG (opcional)",
  "sv": "EPG-URL (valfritt)",
  "da": "EPG-URL (valgfrit)",
  "nb": "EPG-URL (valgfritt)",
  "ar": "رابط EPG (اختياري)",
  "sw": "URL ya EPG (hiari)"
 },
 "castErrorTvRefusedStream": {
  "fr": "La TV a refusé ce flux — format probablement non pris en charge par ce récepteur. Essaie une autre chaîne.",
  "en": "The TV refused this stream — the format is probably not supported by this receiver. Try another channel.",
  "es": "El televisor rechazó este flujo: probablemente el receptor no admite este formato. Prueba otro canal.",
  "sv": "TV:n avvisade den här strömmen — formatet stöds förmodligen inte av mottagaren. Prova en annan kanal.",
  "da": "TV'et afviste denne stream — formatet understøttes sandsynligvis ikke af modtageren. Prøv en anden kanal.",
  "nb": "TV-en avviste denne strømmen — formatet støttes trolig ikke av mottakeren. Prøv en annen kanal.",
  "ar": "رفض التلفاز هذا البث — غالبًا لأن هذا المستقبِل لا يدعم هذه الصيغة. جرّب قناة أخرى.",
  "sw": "TV imekataa mtiririko huu — huenda kipokezi hiki hakitumii umbizo hili. Jaribu kituo kingine."
 },
 "castErrorTooLong": {
  "fr": "Cast trop long — la TV ou le réseau ne répondent pas",
  "en": "Casting took too long — the TV or the network isn't responding",
  "es": "El cast tarda demasiado: el televisor o la red no responden",
  "sv": "Castningen tog för lång tid — TV:n eller nätverket svarar inte",
  "da": "Castingen tog for lang tid — TV'et eller netværket svarer ikke",
  "nb": "Castingen tok for lang tid — TV-en eller nettverket svarer ikke",
  "ar": "استغرق البث وقتًا طويلًا — التلفاز أو الشبكة لا يستجيبان",
  "sw": "Kutuma kumechukua muda mrefu — TV au mtandao haujibu"
 },
 "castErrorTvTooSlow": {
  "fr": "La TV met trop de temps à répondre. Réessaie ou choisis une autre TV.",
  "en": "The TV is taking too long to respond. Try again or pick another TV.",
  "es": "El televisor tarda demasiado en responder. Reintenta o elige otro televisor.",
  "sv": "TV:n tar för lång tid på sig att svara. Försök igen eller välj en annan TV.",
  "da": "TV'et er for længe om at svare. Prøv igen, eller vælg et andet TV.",
  "nb": "TV-en bruker for lang tid på å svare. Prøv igjen eller velg en annen TV.",
  "ar": "يستغرق التلفاز وقتًا طويلًا للاستجابة. أعد المحاولة أو اختر تلفازًا آخر.",
  "sw": "TV inachukua muda mrefu kujibu. Jaribu tena au chagua TV nyingine."
 },
 "castErrorRelayBlocked": {
  "fr": "Ta TV ne joint pas le téléphone (WiFi invité ou isolation AP ?). Mets le téléphone et la TV sur le MÊME réseau WiFi (pas le réseau invité) et désactive l'isolation AP.",
  "en": "Your TV can't reach the phone (guest WiFi or AP isolation?). Put the phone and the TV on the SAME WiFi network (not the guest network) and turn off AP isolation.",
  "es": "Tu televisor no puede conectar con el teléfono (¿WiFi de invitados o aislamiento AP?). Pon el teléfono y el televisor en la MISMA red WiFi (no la de invitados) y desactiva el aislamiento AP.",
  "sv": "Din TV når inte telefonen (gäst-WiFi eller AP-isolering?). Anslut telefonen och TV:n till SAMMA WiFi-nätverk (inte gästnätverket) och stäng av AP-isolering.",
  "da": "Dit TV kan ikke nå telefonen (gæste-WiFi eller AP-isolering?). Sæt telefonen og TV'et på det SAMME WiFi-netværk (ikke gæstenetværket), og slå AP-isolering fra.",
  "nb": "TV-en din når ikke telefonen (gjeste-WiFi eller AP-isolering?). Koble telefonen og TV-en til SAMME WiFi-nettverk (ikke gjestenettverket) og slå av AP-isolering.",
  "ar": "لا يستطيع التلفاز الوصول إلى الهاتف (شبكة ضيوف أو عزل AP؟). ضع الهاتف والتلفاز على نفس شبكة WiFi (وليس شبكة الضيوف) وعطّل خاصية عزل AP.",
  "sw": "TV yako haiwezi kuifikia simu (WiFi ya wageni au AP isolation?). Weka simu na TV kwenye mtandao MMOJA wa WiFi (si wa wageni) na uzime AP isolation."
 },
 "castErrorNoPlayServices": {
  "fr": "Le Chromecast officiel a besoin des services Google Play, absents sur ce téléphone. Tu peux quand même caster vers une Smart TV (DLNA) ou un Roku depuis la liste.",
  "en": "Official Chromecast needs Google Play services, which are missing on this phone. You can still cast to a Smart TV (DLNA) or a Roku from the list.",
  "es": "El Chromecast oficial necesita los servicios de Google Play, ausentes en este teléfono. Aun así puedes enviar a una Smart TV (DLNA) o un Roku desde la lista.",
  "sv": "Officiell Chromecast kräver Google Play-tjänster, som saknas på den här telefonen. Du kan ändå casta till en smart-TV (DLNA) eller en Roku från listan.",
  "da": "Officiel Chromecast kræver Google Play-tjenester, som mangler på denne telefon. Du kan stadig caste til et Smart TV (DLNA) eller en Roku fra listen.",
  "nb": "Offisiell Chromecast krever Google Play-tjenester, som mangler på denne telefonen. Du kan likevel caste til en smart-TV (DLNA) eller en Roku fra listen.",
  "ar": "يحتاج Chromecast الرسمي إلى خدمات Google Play، وهي غير متوفرة على هذا الهاتف. يمكنك مع ذلك البث إلى تلفاز ذكي (DLNA) أو جهاز Roku من القائمة.",
  "sw": "Chromecast rasmi inahitaji huduma za Google Play, ambazo hazipo kwenye simu hii. Bado unaweza kutuma kwa Smart TV (DLNA) au Roku kutoka kwenye orodha."
 },
 "castErrorDnsUnstable": {
  "fr": "Internet ou DNS instable. Réessaie dans quelques secondes.",
  "en": "Unstable internet or DNS. Try again in a few seconds.",
  "es": "Internet o DNS inestable. Reintenta en unos segundos.",
  "sv": "Instabilt internet eller DNS. Försök igen om några sekunder.",
  "da": "Ustabilt internet eller DNS. Prøv igen om få sekunder.",
  "nb": "Ustabilt internett eller DNS. Prøv igjen om noen sekunder.",
  "ar": "الإنترنت أو DNS غير مستقر. أعد المحاولة بعد بضع ثوانٍ.",
  "sw": "Intaneti au DNS si thabiti. Jaribu tena baada ya sekunde chache."
 },
 "castErrorTvStuckTransitioning": {
  "fr": "Ta TV est bloquée sur un précédent cast. Éteins-la quelques secondes puis rallume-la et réessaie.",
  "en": "Your TV is stuck on a previous cast. Turn it off for a few seconds, turn it back on and try again.",
  "es": "Tu televisor se quedó bloqueado en un cast anterior. Apágalo unos segundos, vuelve a encenderlo y reintenta.",
  "sv": "Din TV har fastnat i en tidigare castning. Stäng av den i några sekunder, slå på den igen och försök på nytt.",
  "da": "Dit TV sidder fast i en tidligere casting. Sluk det i et par sekunder, tænd det igen, og prøv på ny.",
  "nb": "TV-en din har hengt seg opp i en tidligere casting. Slå den av i noen sekunder, slå den på igjen og prøv på nytt.",
  "ar": "التلفاز عالق في بث سابق. أطفئه لبضع ثوانٍ ثم أعد تشغيله وحاول مجددًا.",
  "sw": "TV yako imekwama kwenye utumaji uliopita. Izime kwa sekunde chache, kisha uiwashe tena na ujaribu upya."
 },
 "castErrorFormatNotAccepted": {
  "fr": "Ta TV n'accepte pas ce format. Essaie une autre chaîne.",
  "en": "Your TV doesn't accept this format. Try another channel.",
  "es": "Tu televisor no acepta este formato. Prueba otro canal.",
  "sv": "Din TV accepterar inte det här formatet. Prova en annan kanal.",
  "da": "Dit TV accepterer ikke dette format. Prøv en anden kanal.",
  "nb": "TV-en din godtar ikke dette formatet. Prøv en annen kanal.",
  "ar": "التلفاز لا يقبل هذه الصيغة. جرّب قناة أخرى.",
  "sw": "TV yako haikubali umbizo hili. Jaribu kituo kingine."
 },
 "castErrorProviderLimit": {
  "fr": "Ton fournisseur IPTV refuse une connexion supplémentaire (limite atteinte). Coupe une autre app qui regarde et réessaie.",
  "en": "Your IPTV provider is refusing an extra connection (limit reached). Close another app that's watching and try again.",
  "es": "Tu proveedor IPTV rechaza una conexión adicional (límite alcanzado). Cierra otra app que esté viendo y reintenta.",
  "sv": "Din IPTV-leverantör nekar en extra anslutning (gränsen är nådd). Stäng en annan app som tittar och försök igen.",
  "da": "Din IPTV-udbyder afviser en ekstra forbindelse (grænsen er nået). Luk en anden app, der ser med, og prøv igen.",
  "nb": "IPTV-leverandøren din avviser en ekstra tilkobling (grensen er nådd). Lukk en annen app som ser på, og prøv igjen.",
  "ar": "مزوّد IPTV يرفض اتصالًا إضافيًا (تم بلوغ الحد). أغلق تطبيقًا آخر يشاهد الآن وأعد المحاولة.",
  "sw": "Mtoa huduma wako wa IPTV anakataa muunganisho wa ziada (kikomo kimefikiwa). Funga programu nyingine inayotazama kisha ujaribu tena."
 },
 "castErrorTvNotResponding": {
  "fr": "La TV ne répond pas. Vérifie le WiFi.",
  "en": "The TV isn't responding. Check the WiFi.",
  "es": "El televisor no responde. Comprueba el WiFi.",
  "sv": "TV:n svarar inte. Kontrollera WiFi-nätverket.",
  "da": "TV'et svarer ikke. Tjek WiFi.",
  "nb": "TV-en svarer ikke. Sjekk WiFi.",
  "ar": "التلفاز لا يستجيب. تحقّق من شبكة WiFi.",
  "sw": "TV haijibu. Kagua WiFi."
 },
 "castErrorStreamAccessDenied": {
  "fr": "Accès au flux refusé — ton abonnement a peut-être expiré.",
  "en": "Access to the stream was denied — your subscription may have expired.",
  "es": "Acceso al flujo denegado: puede que tu suscripción haya caducado.",
  "sv": "Åtkomst till strömmen nekades — ditt abonnemang kan ha gått ut.",
  "da": "Adgang til streamen blev nægtet — dit abonnement er måske udløbet.",
  "nb": "Tilgang til strømmen ble nektet — abonnementet ditt kan ha utløpt.",
  "ar": "رُفض الوصول إلى البث — ربما انتهت صلاحية اشتراكك.",
  "sw": "Ufikiaji wa mtiririko umekataliwa — huenda usajili wako umeisha muda."
 },
 "castErrorTvRejectedStream": {
  "fr": "Cette TV n'a pas accepté ce flux. Essaie une autre chaîne.",
  "en": "This TV didn't accept this stream. Try another channel.",
  "es": "Este televisor no aceptó este flujo. Prueba otro canal.",
  "sv": "Den här TV:n accepterade inte strömmen. Prova en annan kanal.",
  "da": "Dette TV accepterede ikke denne stream. Prøv en anden kanal.",
  "nb": "Denne TV-en godtok ikke denne strømmen. Prøv en annen kanal.",
  "ar": "لم يقبل هذا التلفاز هذا البث. جرّب قناة أخرى.",
  "sw": "TV hii haikukubali mtiririko huu. Jaribu kituo kingine."
 },
 "castErrorTvUnreachableChecklist": {
  "fr": "Ta TV ne répond pas sur le réseau. Vérifie : (1) qu'elle est allumée, (2) qu'elle est sur le MÊME WiFi que ton téléphone (pas le réseau \"invité\"), (3) que l'option « Isolation client / AP isolation » est DÉSACTIVÉE dans les réglages de ta box internet.",
  "en": "Your TV isn't responding on the network. Check: (1) it's turned on, (2) it's on the SAME WiFi as your phone (not the \"guest\" network), (3) the \"Client isolation / AP isolation\" option is DISABLED in your router settings.",
  "es": "Tu televisor no responde en la red. Comprueba: (1) que está encendido, (2) que está en el MISMO WiFi que tu teléfono (no la red de \"invitados\"), (3) que la opción «Aislamiento de clientes / AP isolation» está DESACTIVADA en los ajustes de tu router.",
  "sv": "Din TV svarar inte på nätverket. Kontrollera: (1) att den är på, (2) att den är på SAMMA WiFi som din telefon (inte \"gästnätverket\"), (3) att alternativet ”Klientisolering / AP isolation” är AVSTÄNGT i routerns inställningar.",
  "da": "Dit TV svarer ikke på netværket. Tjek: (1) at det er tændt, (2) at det er på det SAMME WiFi som din telefon (ikke \"gæstenetværket\"), (3) at indstillingen ”Klientisolering / AP isolation” er SLÅET FRA i din routers indstillinger.",
  "nb": "TV-en din svarer ikke på nettverket. Sjekk: (1) at den er slått på, (2) at den er på SAMME WiFi som telefonen din (ikke \"gjestenettverket\"), (3) at alternativet «Klientisolering / AP isolation» er SLÅTT AV i ruterinnstillingene.",
  "ar": "التلفاز لا يستجيب على الشبكة. تحقّق من: (1) أنه مشغّل، (2) أنه على نفس شبكة WiFi مثل هاتفك (وليس شبكة \"الضيوف\")، (3) أن خيار «عزل العملاء / AP isolation» معطَّل في إعدادات جهاز التوجيه.",
  "sw": "TV yako haijibu kwenye mtandao. Kagua: (1) kwamba imewashwa, (2) kwamba iko kwenye WiFi ILE ILE na simu yako (si mtandao wa \"wageni\"), (3) kwamba chaguo la \"Client isolation / AP isolation\" LIMEZIMWA kwenye mipangilio ya router yako."
 },
 "castErrorTvConnectionFailed": {
  "fr": "Connexion impossible avec la TV.",
  "en": "Couldn't connect to the TV.",
  "es": "No se pudo conectar con el televisor.",
  "sv": "Det gick inte att ansluta till TV:n.",
  "da": "Kunne ikke oprette forbindelse til TV'et.",
  "nb": "Kunne ikke koble til TV-en.",
  "ar": "تعذّر الاتصال بالتلفاز.",
  "sw": "Imeshindikana kuunganisha na TV."
 },
 "castErrorGeneric": {
  "fr": "Le cast a échoué. Essaie de relancer.",
  "en": "Casting failed. Try again.",
  "es": "El cast ha fallado. Vuelve a intentarlo.",
  "sv": "Castningen misslyckades. Försök igen.",
  "da": "Castingen mislykkedes. Prøv igen.",
  "nb": "Castingen mislyktes. Prøv igjen.",
  "ar": "فشل البث. حاول من جديد.",
  "sw": "Kutuma kumeshindikana. Jaribu tena."
 },
 "castNotifRelayKeepAlive": {
  "fr": "Diffusion sur la TV — garde le téléphone sur ce WiFi",
  "en": "Streaming to the TV — keep the phone on this WiFi",
  "es": "Emitiendo en el televisor: mantén el teléfono en este WiFi",
  "sv": "Strömmar till TV:n — behåll telefonen på detta WiFi",
  "da": "Streamer til TV'et — hold telefonen på dette WiFi",
  "nb": "Strømmer til TV-en — hold telefonen på dette WiFi-et",
  "ar": "يجري البث على التلفاز — أبقِ الهاتف على شبكة WiFi هذه",
  "sw": "Inatuma kwenye TV — weka simu kwenye WiFi hii"
 },
 "castDefaultDlnaReceiverName": {
  "fr": "Récepteur DLNA",
  "en": "DLNA receiver",
  "es": "Receptor DLNA",
  "sv": "DLNA-mottagare",
  "da": "DLNA-modtager",
  "nb": "DLNA-mottaker",
  "ar": "مستقبِل DLNA",
  "sw": "Kipokezi cha DLNA"
 },
 "castDiagPresetQuickLabel": {
  "fr": "Rapide",
  "en": "Quick",
  "es": "Rápido",
  "sv": "Snabb",
  "da": "Hurtig",
  "nb": "Rask",
  "ar": "سريع",
  "sw": "Haraka"
 },
 "castDiagPresetStandardLabel": {
  "fr": "Standard",
  "en": "Standard",
  "es": "Estándar",
  "sv": "Standard",
  "da": "Standard",
  "nb": "Standard",
  "ar": "قياسي",
  "sw": "Kawaida"
 },
 "castDiagPresetThoroughLabel": {
  "fr": "Complet",
  "en": "Full",
  "es": "Completo",
  "sv": "Fullständig",
  "da": "Fuld",
  "nb": "Fullstendig",
  "ar": "كامل",
  "sw": "Kamili"
 },
 "castDiagPresetDescription": {
  "fr": "{count} chaînes (~{minutes} min)",
  "en": "{count} channels (~{minutes} min)",
  "es": "{count} canales (~{minutes} min)",
  "sv": "{count} kanaler (~{minutes} min)",
  "da": "{count} kanaler (~{minutes} min.)",
  "nb": "{count} kanaler (~{minutes} min)",
  "ar": "{count} قنوات (~{minutes} د)",
  "sw": "Vituo {count} (~dakika {minutes})"
 },
 "genreSports": {
  "fr": "Sports",
  "en": "Sports",
  "es": "Deportes",
  "sv": "Sport",
  "da": "Sport",
  "nb": "Sport",
  "ar": "رياضة",
  "sw": "Michezo"
 },
 "genreMovies": {
  "fr": "Films",
  "en": "Movies",
  "es": "Películas",
  "sv": "Filmer",
  "da": "Film",
  "nb": "Filmer",
  "ar": "أفلام",
  "sw": "Filamu"
 },
 "genreSeries": {
  "fr": "Séries",
  "en": "Series",
  "es": "Series",
  "sv": "Serier",
  "da": "Serier",
  "nb": "Serier",
  "ar": "مسلسلات",
  "sw": "Mfululizo"
 },
 "genreKids": {
  "fr": "Jeunesse",
  "en": "Kids",
  "es": "Infantil",
  "sv": "Barn",
  "da": "Børn",
  "nb": "Barn",
  "ar": "أطفال",
  "sw": "Watoto"
 },
 "genreNews": {
  "fr": "Info",
  "en": "News",
  "es": "Noticias",
  "sv": "Nyheter",
  "da": "Nyheder",
  "nb": "Nyheter",
  "ar": "أخبار",
  "sw": "Habari"
 },
 "genreMusic": {
  "fr": "Musique",
  "en": "Music",
  "es": "Música",
  "sv": "Musik",
  "da": "Musik",
  "nb": "Musikk",
  "ar": "موسيقى",
  "sw": "Muziki"
 },
 "genreDocumentary": {
  "fr": "Docu",
  "en": "Docs",
  "es": "Documentales",
  "sv": "Dokumentärer",
  "da": "Dokumentarer",
  "nb": "Dokumentarer",
  "ar": "وثائقيات",
  "sw": "Dokumentari"
 },
 "genreEntertainment": {
  "fr": "Divertissement",
  "en": "Entertainment",
  "es": "Entretenimiento",
  "sv": "Underhållning",
  "da": "Underholdning",
  "nb": "Underholdning",
  "ar": "ترفيه",
  "sw": "Burudani"
 },
 "genreInternational": {
  "fr": "International",
  "en": "International",
  "es": "Internacional",
  "sv": "Internationellt",
  "da": "International",
  "nb": "Internasjonalt",
  "ar": "دولي",
  "sw": "Kimataifa"
 },
 "genreAdult": {
  "fr": "Adulte",
  "en": "Adult",
  "es": "Adultos",
  "sv": "Vuxet",
  "da": "Voksen",
  "nb": "Voksen",
  "ar": "للكبار",
  "sw": "Watu wazima"
 },
 "genreOther": {
  "fr": "Autres",
  "en": "Other",
  "es": "Otros",
  "sv": "Övrigt",
  "da": "Andet",
  "nb": "Annet",
  "ar": "أخرى",
  "sw": "Nyingine"
 },
 "playlistErrorNoChannelsInM3u": {
  "fr": "Aucune chaîne trouvée dans le fichier M3U. URL invalide ou format incompatible ?",
  "en": "No channels found in the M3U file. Invalid URL or unsupported format?",
  "es": "No se encontró ningún canal en el archivo M3U. ¿URL inválida o formato incompatible?",
  "sv": "Inga kanaler hittades i M3U-filen. Ogiltig URL eller inkompatibelt format?",
  "da": "Ingen kanaler fundet i M3U-filen. Ugyldig URL eller inkompatibelt format?",
  "nb": "Fant ingen kanaler i M3U-filen. Ugyldig URL eller inkompatibelt format?",
  "ar": "لم يتم العثور على أي قناة في ملف M3U. هل الرابط غير صالح أو التنسيق غير متوافق؟",
  "sw": "Hakuna kituo kilichopatikana kwenye faili la M3U. Je, URL si sahihi au muundo haukubaliki?"
 },
 "playlistErrorParserDetails": {
  "fr": "Détails parser :",
  "en": "Parser details:",
  "es": "Detalles del parser:",
  "sv": "Parserdetaljer:",
  "da": "Parserdetaljer:",
  "nb": "Parserdetaljer:",
  "ar": "تفاصيل المحلل:",
  "sw": "Maelezo ya kichanganuzi:"
 },
 "playlistErrorRefreshEmpty": {
  "fr": "Aucune chaîne dans la nouvelle version.",
  "en": "No channels in the new version.",
  "es": "Ningún canal en la nueva versión.",
  "sv": "Inga kanaler i den nya versionen.",
  "da": "Ingen kanaler i den nye version.",
  "nb": "Ingen kanaler i den nye versjonen.",
  "ar": "لا توجد قنوات في النسخة الجديدة.",
  "sw": "Hakuna vituo katika toleo jipya."
 },
 "xtreamErrorNoLiveChannels": {
  "fr": "Aucune chaîne live disponible pour ce compte Xtream.",
  "en": "No live channels available for this Xtream account.",
  "es": "No hay canales en directo disponibles para esta cuenta Xtream.",
  "sv": "Inga livekanaler tillgängliga för det här Xtream-kontot.",
  "da": "Ingen live-kanaler tilgængelige for denne Xtream-konto.",
  "nb": "Ingen direktekanaler tilgjengelige for denne Xtream-kontoen.",
  "ar": "لا توجد قنوات بث مباشر متاحة لحساب Xtream هذا.",
  "sw": "Hakuna vituo vya moja kwa moja kwenye akaunti hii ya Xtream."
 },
 "xtreamErrorRefreshNoLive": {
  "fr": "Aucune chaîne live disponible.",
  "en": "No live channels available.",
  "es": "No hay canales en directo disponibles.",
  "sv": "Inga livekanaler tillgängliga.",
  "da": "Ingen live-kanaler tilgængelige.",
  "nb": "Ingen direktekanaler tilgjengelige.",
  "ar": "لا توجد قنوات بث مباشر متاحة.",
  "sw": "Hakuna vituo vya moja kwa moja vinavyopatikana."
 },
 "xtreamErrorInvalidResponse": {
  "fr": "Réponse serveur invalide (pas de user_info).",
  "en": "Invalid server response (no user_info).",
  "es": "Respuesta del servidor inválida (sin user_info).",
  "sv": "Ogiltigt serversvar (ingen user_info).",
  "da": "Ugyldigt serversvar (ingen user_info).",
  "nb": "Ugyldig serversvar (ingen user_info).",
  "ar": "استجابة الخادم غير صالحة (بدون user_info).",
  "sw": "Jibu la seva si sahihi (hakuna user_info)."
 },
 "xtreamErrorLoginRefused": {
  "fr": "Identifiants refusés par le serveur. Vérifie ton login/mot de passe.",
  "en": "Credentials refused by the server. Check your username/password.",
  "es": "El servidor rechazó las credenciales. Revisa tu usuario/contraseña.",
  "sv": "Servern avvisade inloggningsuppgifterna. Kontrollera ditt användarnamn/lösenord.",
  "da": "Serveren afviste loginoplysningerne. Tjek dit brugernavn/adgangskode.",
  "nb": "Serveren avviste påloggingsinfoen. Sjekk brukernavn/passord.",
  "ar": "رفض الخادم بيانات الدخول. تحقق من اسم المستخدم/كلمة المرور.",
  "sw": "Seva imekataa vitambulisho. Angalia jina lako la mtumiaji/nenosiri."
 },
 "xtreamErrorAccountInactive": {
  "fr": "Compte non-actif côté serveur (status={status}).",
  "en": "Account not active on the server (status={status}).",
  "es": "Cuenta no activa en el servidor (status={status}).",
  "sv": "Kontot är inte aktivt på servern (status={status}).",
  "da": "Kontoen er ikke aktiv på serveren (status={status}).",
  "nb": "Kontoen er ikke aktiv på serveren (status={status}).",
  "ar": "الحساب غير نشط على الخادم (status={status}).",
  "sw": "Akaunti haiko hai kwenye seva (status={status})."
 },
 "xtreamErrorHttp": {
  "fr": "Erreur HTTP {code} sur {host}",
  "en": "HTTP error {code} on {host}",
  "es": "Error HTTP {code} en {host}",
  "sv": "HTTP-fel {code} på {host}",
  "da": "HTTP-fejl {code} på {host}",
  "nb": "HTTP-feil {code} på {host}",
  "ar": "خطأ HTTP {code} على {host}",
  "sw": "Hitilafu ya HTTP {code} kwenye {host}"
 },
 "xtreamErrorUnreachable": {
  "fr": "Serveur Xtream injoignable ({host}).",
  "en": "Xtream server unreachable ({host}).",
  "es": "Servidor Xtream inaccesible ({host}).",
  "sv": "Xtream-servern kan inte nås ({host}).",
  "da": "Xtream-serveren kan ikke nås ({host}).",
  "nb": "Xtream-serveren er utilgjengelig ({host}).",
  "ar": "تعذر الوصول إلى خادم Xtream ({host}).",
  "sw": "Seva ya Xtream haipatikani ({host})."
 },
 "xtreamErrorTooLarge": {
  "fr": "Source Xtream trop volumineuse (> {maxMb} Mo). Filtre les catégories côté fournisseur.",
  "en": "Xtream source too large (> {maxMb} MB). Filter categories on the provider side.",
  "es": "Fuente Xtream demasiado grande (> {maxMb} MB). Filtra las categorías en el proveedor.",
  "sv": "Xtream-källan är för stor (> {maxMb} MB). Filtrera kategorierna hos leverantören.",
  "da": "Xtream-kilden er for stor (> {maxMb} MB). Filtrér kategorierne hos udbyderen.",
  "nb": "Xtream-kilden er for stor (> {maxMb} MB). Filtrer kategoriene hos leverandøren.",
  "ar": "مصدر Xtream كبير جدًا (> {maxMb} م.ب). صفِّ الفئات لدى المزود.",
  "sw": "Chanzo cha Xtream ni kikubwa mno (> {maxMb} MB). Chuja kategoria upande wa mtoa huduma."
 },
 "xtreamErrorUnexpectedJson": {
  "fr": "Réponse JSON non attendue sur action={action}.",
  "en": "Unexpected JSON response on action={action}.",
  "es": "Respuesta JSON inesperada en action={action}.",
  "sv": "Oväntat JSON-svar på action={action}.",
  "da": "Uventet JSON-svar på action={action}.",
  "nb": "Uventet JSON-svar på action={action}.",
  "ar": "استجابة JSON غير متوقعة على action={action}.",
  "sw": "Jibu la JSON lisilotarajiwa kwenye action={action}."
 },
 "xtreamErrorNotJson": {
  "fr": "Réponse non-JSON sur action={action} : {message}",
  "en": "Non-JSON response on action={action}: {message}",
  "es": "Respuesta no JSON en action={action}: {message}",
  "sv": "Icke-JSON-svar på action={action}: {message}",
  "da": "Ikke-JSON-svar på action={action}: {message}",
  "nb": "Ikke-JSON-svar på action={action}: {message}",
  "ar": "استجابة ليست JSON على action={action}: {message}",
  "sw": "Jibu lisilo la JSON kwenye action={action}: {message}"
 },
 "m3uErrorHttp": {
  "fr": "HTTP {code} sur {url}",
  "en": "HTTP {code} on {url}",
  "es": "HTTP {code} en {url}",
  "sv": "HTTP {code} på {url}",
  "da": "HTTP {code} på {url}",
  "nb": "HTTP {code} på {url}",
  "ar": "HTTP {code} على {url}",
  "sw": "HTTP {code} kwenye {url}"
 },
 "m3uErrorEmptyResponse": {
  "fr": "Le serveur a renvoyé une réponse vide pour {url}",
  "en": "The server returned an empty response for {url}",
  "es": "El servidor devolvió una respuesta vacía para {url}",
  "sv": "Servern returnerade ett tomt svar för {url}",
  "da": "Serveren returnerede et tomt svar for {url}",
  "nb": "Serveren returnerte et tomt svar for {url}",
  "ar": "أعاد الخادم استجابة فارغة لـ {url}",
  "sw": "Seva ilirudisha jibu tupu kwa {url}"
 },
 "m3uErrorHtmlResponse": {
  "fr": "Le serveur a renvoyé une page web (HTML), pas une playlist.",
  "en": "The server returned a web page (HTML), not a playlist.",
  "es": "El servidor devolvió una página web (HTML), no una playlist.",
  "sv": "Servern returnerade en webbsida (HTML), inte en spellista.",
  "da": "Serveren returnerede en webside (HTML), ikke en playliste.",
  "nb": "Serveren returnerte en nettside (HTML), ikke en spilleliste.",
  "ar": "أعاد الخادم صفحة ويب (HTML) وليس قائمة تشغيل.",
  "sw": "Seva ilirudisha ukurasa wa wavuti (HTML), si orodha ya vituo."
 },
 "m3uErrorNoChannels": {
  "fr": "Réponse sans aucune chaîne (ni #EXTM3U ni URL) pour {url}",
  "en": "Response without any channel (no #EXTM3U nor URL) for {url}",
  "es": "Respuesta sin ningún canal (ni #EXTM3U ni URL) para {url}",
  "sv": "Svar utan någon kanal (varken #EXTM3U eller URL) för {url}",
  "da": "Svar uden nogen kanal (hverken #EXTM3U eller URL) for {url}",
  "nb": "Svar uten noen kanal (verken #EXTM3U eller URL) for {url}",
  "ar": "استجابة بدون أي قناة (لا #EXTM3U ولا URL) لـ {url}",
  "sw": "Jibu lisilo na kituo chochote (wala #EXTM3U wala URL) kwa {url}"
 },
 "m3uErrorAllAgentsFailed": {
  "fr": "Impossible de récupérer la playlist : le serveur a refusé les {count} signatures de lecteur testées (VLC, IBO/ExoPlayer, Smarters, TiviMate, Kodi…). Vérifie que l'URL est correcte et que l'abonnement est actif ; un lien « localhost » ne marche pas depuis cet appareil.",
  "en": "Couldn't fetch the playlist: the server refused all {count} player signatures tested (VLC, IBO/ExoPlayer, Smarters, TiviMate, Kodi…). Check that the URL is correct and the subscription is active; a \"localhost\" link won't work from this device.",
  "es": "Imposible recuperar la playlist: el servidor rechazó las {count} firmas de reproductor probadas (VLC, IBO/ExoPlayer, Smarters, TiviMate, Kodi…). Comprueba que la URL sea correcta y que la suscripción esté activa; un enlace «localhost» no funciona desde este dispositivo.",
  "sv": "Det gick inte att hämta spellistan: servern avvisade alla {count} testade spelarsignaturer (VLC, IBO/ExoPlayer, Smarters, TiviMate, Kodi…). Kontrollera att URL:en är korrekt och att abonnemanget är aktivt; en \"localhost\"-länk fungerar inte från den här enheten.",
  "da": "Kunne ikke hente playlisten: serveren afviste alle {count} testede afspillersignaturer (VLC, IBO/ExoPlayer, Smarters, TiviMate, Kodi…). Tjek at URL'en er korrekt, og at abonnementet er aktivt; et \"localhost\"-link virker ikke fra denne enhed.",
  "nb": "Kunne ikke hente spillelisten: serveren avviste alle {count} testede spillersignaturer (VLC, IBO/ExoPlayer, Smarters, TiviMate, Kodi…). Sjekk at URL-en er riktig og at abonnementet er aktivt; en «localhost»-lenke fungerer ikke fra denne enheten.",
  "ar": "تعذر جلب قائمة التشغيل: رفض الخادم كل توقيعات المشغلات المختبرة ({count}) (VLC وIBO/ExoPlayer وSmarters وTiviMate وKodi…). تحقق من صحة الرابط ومن أن الاشتراك نشط؛ رابط «localhost» لا يعمل من هذا الجهاز.",
  "sw": "Imeshindikana kupata orodha ya vituo: seva ilikataa sahihi zote {count} za vichezaji zilizojaribiwa (VLC, IBO/ExoPlayer, Smarters, TiviMate, Kodi…). Hakikisha URL ni sahihi na usajili uko hai; kiungo cha \"localhost\" hakifanyi kazi kutoka kifaa hiki."
 },
 "m3uErrorLastResponse": {
  "fr": "Dernière réponse : {detail}",
  "en": "Last response: {detail}",
  "es": "Última respuesta: {detail}",
  "sv": "Senaste svar: {detail}",
  "da": "Seneste svar: {detail}",
  "nb": "Siste svar: {detail}",
  "ar": "آخر استجابة: {detail}",
  "sw": "Jibu la mwisho: {detail}"
 },
 "m3uErrorTooLarge": {
  "fr": "Playlist trop volumineuse (> {maxMb} Mo). Réduis la source ou filtre les catégories côté fournisseur.",
  "en": "Playlist too large (> {maxMb} MB). Reduce the source or filter categories on the provider side.",
  "es": "Playlist demasiado grande (> {maxMb} MB). Reduce la fuente o filtra las categorías en el proveedor.",
  "sv": "Spellistan är för stor (> {maxMb} MB). Minska källan eller filtrera kategorierna hos leverantören.",
  "da": "Playlisten er for stor (> {maxMb} MB). Reducér kilden eller filtrér kategorierne hos udbyderen.",
  "nb": "Spillelisten er for stor (> {maxMb} MB). Reduser kilden eller filtrer kategoriene hos leverandøren.",
  "ar": "قائمة التشغيل كبيرة جدًا (> {maxMb} م.ب). قلّص المصدر أو صفِّ الفئات لدى المزود.",
  "sw": "Orodha ya vituo ni kubwa mno (> {maxMb} MB). Punguza chanzo au chuja kategoria upande wa mtoa huduma."
 },
 "notifChannelRemindersName": {
  "fr": "Rappels de programmes",
  "en": "Program reminders",
  "es": "Recordatorios de programas",
  "sv": "Programpåminnelser",
  "da": "Programpåmindelser",
  "nb": "Programpåminnelser",
  "ar": "تذكيرات البرامج",
  "sw": "Vikumbusho vya vipindi"
 },
 "notifChannelRemindersDesc": {
  "fr": "Notifications avant le début d'un programme que vous avez choisi.",
  "en": "Notifications before a program you picked starts.",
  "es": "Notificaciones antes de que empiece un programa que has elegido.",
  "sv": "Aviseringar innan ett program du valt börjar.",
  "da": "Notifikationer før et program, du har valgt, begynder.",
  "nb": "Varsler før et program du har valgt begynner.",
  "ar": "إشعارات قبل بدء برنامج اخترته.",
  "sw": "Arifa kabla ya kuanza kwa kipindi ulichochagua."
 },
 "notifChannelGeneralName": {
  "fr": "Annonces & mises à jour",
  "en": "Announcements & updates",
  "es": "Anuncios y actualizaciones",
  "sv": "Meddelanden & uppdateringar",
  "da": "Meddelelser & opdateringer",
  "nb": "Kunngjøringer og oppdateringer",
  "ar": "الإعلانات والتحديثات",
  "sw": "Matangazo na masasisho"
 },
 "notifChannelGeneralDesc": {
  "fr": "Nouveautés, annonces de l'équipe et disponibilité des mises à jour.",
  "en": "News, team announcements and update availability.",
  "es": "Novedades, anuncios del equipo y disponibilidad de actualizaciones.",
  "sv": "Nyheter, meddelanden från teamet och tillgängliga uppdateringar.",
  "da": "Nyheder, meddelelser fra holdet og tilgængelige opdateringer.",
  "nb": "Nyheter, kunngjøringer fra teamet og tilgjengelige oppdateringer.",
  "ar": "الجديد وإعلانات الفريق وتوفر التحديثات.",
  "sw": "Habari mpya, matangazo ya timu na upatikanaji wa masasisho."
 },
 "notifReminderBody": {
  "fr": "Commence à {time} sur {channel}",
  "en": "Starts at {time} on {channel}",
  "es": "Empieza a las {time} en {channel}",
  "sv": "Börjar {time} på {channel}",
  "da": "Begynder kl. {time} på {channel}",
  "nb": "Begynner kl. {time} på {channel}",
  "ar": "يبدأ الساعة {time} على {channel}",
  "sw": "Inaanza saa {time} kwenye {channel}"
 },
 "notifUpdateAvailableTitle": {
  "fr": "Mise à jour disponible",
  "en": "Update available",
  "es": "Actualización disponible",
  "sv": "Uppdatering tillgänglig",
  "da": "Opdatering tilgængelig",
  "nb": "Oppdatering tilgjengelig",
  "ar": "تحديث متاح",
  "sw": "Sasisho linapatikana"
 },
 "notifUpdateAvailableBody": {
  "fr": "Une nouvelle version de l'application est prête à installer.",
  "en": "A new version of the app is ready to install.",
  "es": "Una nueva versión de la aplicación está lista para instalar.",
  "sv": "En ny version av appen är redo att installeras.",
  "da": "En ny version af appen er klar til installation.",
  "nb": "En ny versjon av appen er klar til installering.",
  "ar": "نسخة جديدة من التطبيق جاهزة للتثبيت.",
  "sw": "Toleo jipya la programu liko tayari kusakinishwa."
 },
 "notifUpdateAvailableBodyVersion": {
  "fr": "Nouvelle version ({version}) prête à installer.",
  "en": "New version ({version}) ready to install.",
  "es": "Nueva versión ({version}) lista para instalar.",
  "sv": "Ny version ({version}) redo att installeras.",
  "da": "Ny version ({version}) klar til installation.",
  "nb": "Ny versjon ({version}) klar til installering.",
  "ar": "نسخة جديدة ({version}) جاهزة للتثبيت.",
  "sw": "Toleo jipya ({version}) liko tayari kusakinishwa."
 },
 "notifAnnouncementFallbackTitle": {
  "fr": "Nouveauté",
  "en": "What's new",
  "es": "Novedad",
  "sv": "Nyhet",
  "da": "Nyhed",
  "nb": "Nyhet",
  "ar": "جديد",
  "sw": "Jipya"
 },
 "blackBoxFindingCrashTitle": {
  "fr": "Crash de l'application",
  "en": "App crash",
  "es": "Fallo de la aplicación",
  "sv": "Appen kraschade",
  "da": "Appen crashede",
  "nb": "Appen krasjet",
  "ar": "انهيار التطبيق",
  "sw": "Programu ilianguka"
 },
 "blackBoxFindingCrashDetail": {
  "fr": "Une erreur FATALE a été enregistrée — la queue de la session précédente est conservée dans la boîte noire.",
  "en": "A FATAL error was recorded — the tail of the previous session is kept in the black box.",
  "es": "Se registró un error FATAL — el final de la sesión anterior se conserva en la caja negra.",
  "sv": "Ett FATALT fel registrerades — slutet av föregående session finns kvar i svarta lådan.",
  "da": "En FATAL fejl blev registreret — slutningen af forrige session er gemt i den sorte boks.",
  "nb": "En FATAL feil ble registrert — slutten av forrige økt er bevart i svartboksen.",
  "ar": "سُجّل خطأ فادح — نهاية الجلسة السابقة محفوظة في الصندوق الأسود.",
  "sw": "Hitilafu MBAYA ilirekodiwa — mwisho wa kipindi kilichopita umehifadhiwa kwenye sanduku jeusi."
 },
 "blackBoxFindingUncaughtTitle": {
  "fr": "Erreurs non rattrapées",
  "en": "Uncaught errors",
  "es": "Errores no capturados",
  "sv": "Ohanterade fel",
  "da": "Uhåndterede fejl",
  "nb": "Uhåndterte feil",
  "ar": "أخطاء غير مُعالجة",
  "sw": "Hitilafu zisizoshughulikiwa"
 },
 "blackBoxFindingUncaughtDetail": {
  "fr": "Des exceptions ont atteint le filet global (FlutterError / zone). Voir les entrées domain=crash.",
  "en": "Exceptions reached the global safety net (FlutterError / zone). See the domain=crash entries.",
  "es": "Algunas excepciones llegaron a la red de seguridad global (FlutterError / zone). Ver las entradas domain=crash.",
  "sv": "Undantag nådde det globala skyddsnätet (FlutterError / zone). Se posterna domain=crash.",
  "da": "Undtagelser nåede det globale sikkerhedsnet (FlutterError / zone). Se posterne domain=crash.",
  "nb": "Unntak nådde det globale sikkerhetsnettet (FlutterError / zone). Se oppføringene domain=crash.",
  "ar": "وصلت استثناءات إلى شبكة الأمان العامة (FlutterError / zone). راجع إدخالات domain=crash.",
  "sw": "Hitilafu zilifika kwenye wavu wa usalama wa jumla (FlutterError / zone). Angalia maingizo ya domain=crash."
 },
 "blackBoxFindingProxyBlockedTitle": {
  "fr": "Proxy cloud refusé par le fournisseur IPTV",
  "en": "Cloud proxy refused by the IPTV provider",
  "es": "Proxy en la nube rechazado por el proveedor IPTV",
  "sv": "Molnproxy avvisad av IPTV-leverantören",
  "da": "Cloud-proxy afvist af IPTV-udbyderen",
  "nb": "Skyproxy avvist av IPTV-leverandøren",
  "ar": "رفض مزود IPTV وكيل السحابة",
  "sw": "Proksi ya wingu imekataliwa na mtoa huduma wa IPTV"
 },
 "blackBoxFindingProxyBlockedDetail": {
  "fr": "Le serveur IPTV rejette l'IP datacenter du proxy (/cast-proxy). L'app bascule sur le relais du téléphone — comportement attendu, mais le téléphone doit rester allumé.",
  "en": "The IPTV server rejects the proxy's datacenter IP (/cast-proxy). The app falls back to the phone relay — expected behavior, but the phone must stay on.",
  "es": "El servidor IPTV rechaza la IP de datacenter del proxy (/cast-proxy). La app pasa al relé del teléfono — comportamiento esperado, pero el teléfono debe permanecer encendido.",
  "sv": "IPTV-servern avvisar proxyns datacenter-IP (/cast-proxy). Appen växlar till telefonens relä — förväntat beteende, men telefonen måste vara på.",
  "da": "IPTV-serveren afviser proxyens datacenter-IP (/cast-proxy). Appen skifter til telefonens relæ — forventet adfærd, men telefonen skal forblive tændt.",
  "nb": "IPTV-serveren avviser proxyens datasenter-IP (/cast-proxy). Appen bytter til telefonreléet — forventet oppførsel, men telefonen må være på.",
  "ar": "يرفض خادم IPTV عنوان IP الخاص بمركز بيانات الوكيل (/cast-proxy). يتحول التطبيق إلى مرحل الهاتف — سلوك متوقع، لكن يجب أن يبقى الهاتف مشغلاً.",
  "sw": "Seva ya IPTV inakataa IP ya kituo cha data cha proksi (/cast-proxy). Programu inahamia kwenye upitishaji wa simu — tabia inayotarajiwa, ila simu lazima ibaki imewashwa."
 },
 "blackBoxFindingProxyFallbackTitle": {
  "fr": "Bascule proxy → relais téléphone",
  "en": "Switched proxy → phone relay",
  "es": "Cambio proxy → relé del teléfono",
  "sv": "Byte proxy → telefonrelä",
  "da": "Skift proxy → telefonrelæ",
  "nb": "Bytte proxy → telefonrelé",
  "ar": "التبديل من الوكيل إلى مرحل الهاتف",
  "sw": "Kubadilisha proksi → upitishaji wa simu"
 },
 "blackBoxFindingProxyFallbackDetail": {
  "fr": "Le chemin prioritaire /cast-proxy était indisponible ; le relais HLS local a pris le relais.",
  "en": "The primary /cast-proxy path was unavailable; the local HLS relay took over.",
  "es": "La ruta prioritaria /cast-proxy no estaba disponible; el relé HLS local tomó el relevo.",
  "sv": "Den primära /cast-proxy-vägen var otillgänglig; det lokala HLS-reläet tog över.",
  "da": "Den primære /cast-proxy-rute var utilgængelig; det lokale HLS-relæ tog over.",
  "nb": "Den primære /cast-proxy-ruten var utilgjengelig; det lokale HLS-reléet tok over.",
  "ar": "كان المسار الأساسي /cast-proxy غير متاح؛ فتولى مرحل HLS المحلي المهمة.",
  "sw": "Njia kuu /cast-proxy haikupatikana; upitishaji wa HLS wa ndani ulichukua nafasi."
 },
 "blackBoxFindingLoadRejectedTitle": {
  "fr": "Commande de lecture rejetée par la TV",
  "en": "Playback command rejected by the TV",
  "es": "Comando de reproducción rechazado por la TV",
  "sv": "Uppspelningskommandot avvisades av TV:n",
  "da": "Afspilningskommandoen blev afvist af TV'et",
  "nb": "Avspillingskommandoen ble avvist av TV-en",
  "ar": "رفض التلفزيون أمر التشغيل",
  "sw": "Amri ya kucheza imekataliwa na TV"
 },
 "blackBoxFindingLoadRejectedDetail": {
  "fr": "LOAD refusé par le récepteur Cast — flux injoignable depuis la TV ou récepteur indisponible.",
  "en": "LOAD refused by the Cast receiver — stream unreachable from the TV or receiver unavailable.",
  "es": "LOAD rechazado por el receptor Cast — flujo inaccesible desde la TV o receptor no disponible.",
  "sv": "LOAD avvisades av Cast-mottagaren — strömmen kan inte nås från TV:n eller mottagaren är otillgänglig.",
  "da": "LOAD afvist af Cast-modtageren — streamen kan ikke nås fra TV'et, eller modtageren er utilgængelig.",
  "nb": "LOAD avvist av Cast-mottakeren — strømmen kan ikke nås fra TV-en, eller mottakeren er utilgjengelig.",
  "ar": "رفض مستقبل Cast أمر LOAD — تعذر الوصول إلى البث من التلفزيون أو المستقبل غير متاح.",
  "sw": "LOAD imekataliwa na kipokezi cha Cast — mtiririko haufikiki kutoka kwa TV au kipokezi hakipatikani."
 },
 "blackBoxFindingUpstreamDeadTitle": {
  "fr": "Flux IPTV coupé pendant le relais",
  "en": "IPTV stream cut off during relay",
  "es": "Flujo IPTV cortado durante el relé",
  "sv": "IPTV-strömmen bröts under reläet",
  "da": "IPTV-streamen blev afbrudt under relæet",
  "nb": "IPTV-strømmen ble brutt under reléet",
  "ar": "انقطع بث IPTV أثناء الترحيل",
  "sw": "Mtiririko wa IPTV ulikatika wakati wa upitishaji"
 },
 "blackBoxFindingUpstreamDeadDetail": {
  "fr": "Le serveur IPTV a cessé de répondre au relais du téléphone malgré les reconnexions (token expiré ? chaîne morte ?).",
  "en": "The IPTV server stopped responding to the phone relay despite reconnections (expired token? dead channel?).",
  "es": "El servidor IPTV dejó de responder al relé del teléfono pese a las reconexiones (¿token caducado? ¿canal muerto?).",
  "sv": "IPTV-servern slutade svara på telefonreläet trots återanslutningar (utgången token? död kanal?).",
  "da": "IPTV-serveren holdt op med at svare telefonrelæet trods genforbindelser (udløbet token? død kanal?).",
  "nb": "IPTV-serveren sluttet å svare telefonreléet til tross for gjentilkoblinger (utløpt token? død kanal?).",
  "ar": "توقف خادم IPTV عن الرد على مرحل الهاتف رغم إعادة الاتصال (هل انتهت صلاحية الرمز؟ هل القناة ميتة؟).",
  "sw": "Seva ya IPTV iliacha kujibu upitishaji wa simu licha ya kuunganisha upya (tokeni imeisha muda? kituo kimekufa?)."
 },
 "blackBoxFindingMemoryTitle": {
  "fr": "Pression mémoire détectée",
  "en": "Memory pressure detected",
  "es": "Presión de memoria detectada",
  "sv": "Minnestryck upptäckt",
  "da": "Hukommelsespres registreret",
  "nb": "Minnepress oppdaget",
  "ar": "تم رصد ضغط على الذاكرة",
  "sw": "Shinikizo la kumbukumbu limegunduliwa"
 },
 "blackBoxFindingMemoryDetail": {
  "fr": "Des fils d'Ariane mémoire ont été posés — utile si l'app a été tuée par Android (appareil à faible RAM).",
  "en": "Memory breadcrumbs were recorded — useful if Android killed the app (low-RAM device).",
  "es": "Se registraron migas de pan de memoria — útil si Android cerró la app (dispositivo con poca RAM).",
  "sv": "Minnesbrödsmulor registrerades — användbart om Android dödade appen (enhet med lite RAM).",
  "da": "Hukommelses-brødkrummer blev registreret — nyttigt hvis Android lukkede appen (enhed med lidt RAM).",
  "nb": "Minnebrødsmuler ble registrert — nyttig hvis Android drepte appen (enhet med lite RAM).",
  "ar": "سُجّلت مؤشرات للذاكرة — مفيدة إذا أنهى أندرويد التطبيق (جهاز بذاكرة منخفضة).",
  "sw": "Alama za kumbukumbu zilirekodiwa — muhimu ikiwa Android iliua programu (kifaa chenye RAM ndogo)."
 },
 "blackBoxFindingNoisyDomainTitle": {
  "fr": "Domaine bruyant : {domain}",
  "en": "Noisy domain: {domain}",
  "es": "Dominio ruidoso: {domain}",
  "sv": "Bullrig domän: {domain}",
  "da": "Støjende domæne: {domain}",
  "nb": "Støyende domene: {domain}",
  "ar": "نطاق كثير الضجيج: {domain}",
  "sw": "Kikoa chenye kelele: {domain}"
 },
 "blackBoxFindingNoisyDomainDetail": {
  "fr": "{count} avertissements/erreurs enregistrés dans « {domain} » sur la fenêtre de la boîte noire.",
  "en": "{count} warnings/errors recorded in \"{domain}\" over the black box window.",
  "es": "{count} avisos/errores registrados en «{domain}» en la ventana de la caja negra.",
  "sv": "{count} varningar/fel registrerade i \"{domain}\" under svarta lådans fönster.",
  "da": "{count} advarsler/fejl registreret i \"{domain}\" i den sorte boks' vindue.",
  "nb": "{count} advarsler/feil registrert i «{domain}» i svartboksens vindu.",
  "ar": "{count} تحذيرات/أخطاء سُجّلت في «{domain}» ضمن نافذة الصندوق الأسود.",
  "sw": "Maonyo/hitilafu {count} zimerekodiwa katika \"{domain}\" ndani ya dirisha la sanduku jeusi."
 }
}

PLACEHOLDERS = {
 "tvSourcesDeleteConfirm": {
  "name": {
   "type": "String"
  }
 },
 "tvAboutRamGb": {
  "gb": {
   "type": "String"
  }
 },
 "tvAboutCacheCleared": {
  "mb": {
   "type": "String"
  }
 },
 "castStageConnectingAttempt": {
  "attempt": {
   "type": "int"
  },
  "total": {
   "type": "int"
  }
 },
 "castStageRetrying": {
  "attempt": {
   "type": "int"
  },
  "total": {
   "type": "int"
  }
 },
 "guideReminderSet": {
  "title": {
   "type": "String"
  },
  "start": {
   "type": "String"
  }
 },
 "guideStartsAt": {
  "title": {
   "type": "String"
  },
  "start": {
   "type": "String"
  }
 },
 "adminErrHttp": {
  "code": {
   "type": "int"
  },
  "body": {
   "type": "String"
  }
 },
 "adminErrUnreadableResponse": {
  "error": {
   "type": "String"
  }
 },
 "adminErrDetail": {
  "detail": {
   "type": "String"
  }
 },
 "adminErrSaveFailed": {
  "code": {
   "type": "int"
  }
 },
 "adminErrDeleteFailed": {
  "code": {
   "type": "int"
  }
 },
 "adminErrServerUnreachable": {
  "error": {
   "type": "String"
  }
 },
 "tvCollectionsInCollection": {
  "count": {
   "type": "int"
  }
 },
 "tvSleepCountdown": {
  "remaining": {
   "type": "String"
  }
 },
 "tvComponentsWaMyCode": {
  "code": {
   "type": "String"
  }
 },
 "tvFamilyAttachedTo": {
  "owner": {
   "type": "String"
  }
 },
 "tvFamilyMembersHeader": {
  "count": {
   "type": "int"
  },
  "max": {
   "type": "int"
  }
 },
 "tvFamilyJoinSuccess": {
  "owner": {
   "type": "String"
  }
 },
 "tvTeamPickerNotFound": {
  "name": {
   "type": "String"
  }
 },
 "tvDiagCaptiveFail": {
  "code": {
   "type": "int"
  },
  "bytes": {
   "type": "int"
  }
 },
 "tvDiagDnsLookup": {
  "host": {
   "type": "String"
  }
 },
 "tvDiagDnsNoIp": {
  "host": {
   "type": "String"
  }
 },
 "tvDiagDnsTimeout": {
  "host": {
   "type": "String"
  }
 },
 "tvDiagStreamOk": {
  "code": {
   "type": "int"
  }
 },
 "tvDiagSourceMacUnknown": {
  "mac": {
   "type": "String"
  }
 },
 "tvRecordingsDeleteBody": {
  "name": {
   "type": "String"
  }
 },
 "tvGuideUpNext": {
  "title": {
   "type": "String"
  }
 },
 "tvPlayerRecSaved": {
  "size": {
   "type": "String"
  }
 },
 "tvSeriesSeason": {
  "n": {
   "type": "int"
  }
 },
 "tvLiveNowPlaying": {
  "title": {
   "type": "String"
  }
 },
 "tvLiveExpiryInDays": {
  "days": {
   "type": "int"
  }
 },
 "tvLiveExpiryBanner": {
  "when": {
   "type": "String"
  }
 },
 "settingsBufferSubtitle": {
  "seconds": {
   "type": "int"
  }
 },
 "settingsUserAgentSubtitle": {
  "current": {
   "type": "String"
  }
 },
 "onboardingWelcomeAppTitle": {
  "appName": {
   "type": "String"
  }
 },
 "onboardingActivateMessage": {
  "appName": {
   "type": "String"
  },
  "mac": {
   "type": "String"
  }
 },
 "updatePromptBodyVersion": {
  "version": {
   "type": "String"
  }
 },
 "favoritesNowProgram": {
  "program": {
   "type": "String"
  }
 },
 "castDiagRunProgress": {
  "done": {
   "type": "int"
  },
  "total": {
   "type": "int"
  },
  "channel": {
   "type": "String"
  }
 },
 "castDiagCancelledAfter": {
  "done": {
   "type": "int"
  },
  "total": {
   "type": "int"
  }
 },
 "castDiagFinished": {
  "done": {
   "type": "int"
  },
  "total": {
   "type": "int"
  }
 },
 "castDiagSuccessRate": {
  "rate": {
   "type": "int"
  },
  "ok": {
   "type": "int"
  },
  "total": {
   "type": "int"
  }
 },
 "castDiagAvgLatency": {
  "latency": {
   "type": "String"
  }
 },
 "castDiagWinningStrategies": {
  "list": {
   "type": "String"
  }
 },
 "playerConnectingTo": {
  "device": {
   "type": "String"
  }
 },
 "playerCastingOn": {
  "device": {
   "type": "String"
  }
 },
 "adminDeleteClientBody": {
  "mac": {
   "type": "String"
  }
 },
 "adminMacCopied": {
  "mac": {
   "type": "String"
  }
 },
 "adminPlaylistCount": {
  "count": {
   "type": "int"
  }
 },
 "adminPinCreateHint": {
  "count": {
   "type": "int"
  }
 },
 "castDiagPresetDescription": {
  "count": {
   "type": "int"
  },
  "minutes": {
   "type": "int"
  }
 },
 "xtreamErrorAccountInactive": {
  "status": {
   "type": "String"
  }
 },
 "xtreamErrorHttp": {
  "code": {
   "type": "int"
  },
  "host": {
   "type": "String"
  }
 },
 "xtreamErrorUnreachable": {
  "host": {
   "type": "String"
  }
 },
 "xtreamErrorTooLarge": {
  "maxMb": {
   "type": "int"
  }
 },
 "xtreamErrorUnexpectedJson": {
  "action": {
   "type": "String"
  }
 },
 "xtreamErrorNotJson": {
  "action": {
   "type": "String"
  },
  "message": {
   "type": "String"
  }
 },
 "m3uErrorHttp": {
  "code": {
   "type": "int"
  },
  "url": {
   "type": "String"
  }
 },
 "m3uErrorEmptyResponse": {
  "url": {
   "type": "String"
  }
 },
 "m3uErrorNoChannels": {
  "url": {
   "type": "String"
  }
 },
 "m3uErrorAllAgentsFailed": {
  "count": {
   "type": "int"
  }
 },
 "m3uErrorLastResponse": {
  "detail": {
   "type": "String"
  }
 },
 "m3uErrorTooLarge": {
  "maxMb": {
   "type": "int"
  }
 },
 "notifReminderBody": {
  "time": {
   "type": "String"
  },
  "channel": {
   "type": "String"
  }
 },
 "notifUpdateAvailableBodyVersion": {
  "version": {
   "type": "String"
  }
 },
 "blackBoxFindingNoisyDomainTitle": {
  "domain": {
   "type": "String"
  }
 },
 "blackBoxFindingNoisyDomainDetail": {
  "count": {
   "type": "int"
  },
  "domain": {
   "type": "String"
  }
 }
}

added_report = {}
for lang in LANGS:
    path = os.path.join(ARB_DIR, f'app_{lang}.arb')
    with open(path, encoding='utf-8') as fh:
        data = json.load(fh, object_pairs_hook=collections.OrderedDict)
    added = 0
    for key, vals in T.items():
        if key in data:
            continue
        data[key] = vals[lang]
        added += 1
        if lang == 'fr' and key in PLACEHOLDERS:
            data['@' + key] = {'placeholders': PLACEHOLDERS[key]}
    with open(path, 'w', encoding='utf-8') as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
        fh.write('\n')
    added_report[lang] = added

print('Clés ajoutées par langue :', dict(added_report))
print('Total clés définies :', len(T))
