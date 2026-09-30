// =========================================================
//  show_lines.dart — Phrases du bandeau, dans la langue de l'app
// =========================================================
//  Ces phrases restent ici (pas dans les 16 fichiers .arb) :
//  elles ne servent qu'à cette fonction. Chaque langue de
//  l'application a SA phrase. Une langue inconnue retombe
//  sur le français, comme le reste des fonctions en plus
//  quand la traduction manque — sauf qu'ici les 16 langues
//  sont écrites.
// =========================================================

import 'show_clock.dart';

/// Langues livrées avec l'app (fichiers app_xx.arb).
const Set<String> kFollowedLanguages = <String>{
  'ar',
  'da',
  'de',
  'en',
  'es',
  'fr',
  'hi',
  'it',
  'nb',
  'nl',
  'pt',
  'ru',
  'sv',
  'sw',
  'tr',
  'zh',
};

String _code(String languageCode) {
  final String code = languageCode.toLowerCase();
  return kFollowedLanguages.contains(code) ? code : 'fr';
}

/// « Journal commence dans 5 minutes ».
String startsInLine(String languageCode, String title, int minutes) {
  final int n = minutes < 1 ? 1 : minutes;
  final bool one = n == 1;
  switch (_code(languageCode)) {
    case 'en':
      return one ? '$title starts in 1 minute' : '$title starts in $n minutes';
    case 'es':
      return one
          ? '$title empieza en 1 minuto'
          : '$title empieza en $n minutos';
    case 'de':
      return one
          ? '$title beginnt in 1 Minute'
          : '$title beginnt in $n Minuten';
    case 'pt':
      return one ? '$title começa em 1 minuto' : '$title começa em $n minutos';
    case 'it':
      return one ? '$title inizia tra 1 minuto' : '$title inizia tra $n minuti';
    case 'nl':
      return one
          ? '$title begint over 1 minuut'
          : '$title begint over $n minuten';
    case 'da':
      return one
          ? '$title starter om 1 minut'
          : '$title starter om $n minutter';
    case 'nb':
      return one
          ? '$title starter om 1 minutt'
          : '$title starter om $n minutter';
    case 'sv':
      return one ? '$title börjar om 1 minut' : '$title börjar om $n minuter';
    case 'ar':
      return one ? '$title يبدأ خلال دقيقة' : '$title يبدأ خلال $n دقائق';
    case 'ru':
      return one
          ? '$title начнётся через 1 минуту'
          : '$title начнётся через $n мин';
    case 'tr':
      return '$title $n dakika sonra başlıyor';
    case 'hi':
      return '$title $n मिनट में शुरू';
    case 'zh':
      return '$title 将在 $n 分钟后开始';
    case 'sw':
      return '$title inaanza baada ya dakika $n';
    case 'fr':
    default:
      return one
          ? '$title commence dans 1 minute'
          : '$title commence dans $n minutes';
  }
}

/// « Journal a commencé il y a 12 minutes ».
String startedAgoLine(String languageCode, String title, int minutes) {
  final int n = minutes < 1 ? 1 : minutes;
  final bool one = n == 1;
  switch (_code(languageCode)) {
    case 'en':
      return one
          ? '$title started 1 minute ago'
          : '$title started $n minutes ago';
    case 'es':
      return one
          ? '$title empezó hace 1 minuto'
          : '$title empezó hace $n minutos';
    case 'de':
      return one
          ? '$title hat vor 1 Minute begonnen'
          : '$title hat vor $n Minuten begonnen';
    case 'pt':
      return one
          ? '$title começou há 1 minuto'
          : '$title começou há $n minutos';
    case 'it':
      return one
          ? '$title è iniziato da 1 minuto'
          : '$title è iniziato da $n minuti';
    case 'nl':
      return one
          ? '$title is 1 minuut geleden begonnen'
          : '$title is $n minuten geleden begonnen';
    case 'da':
      return one
          ? '$title startede for 1 minut siden'
          : '$title startede for $n minutter siden';
    case 'nb':
      return one
          ? '$title startet for 1 minutt siden'
          : '$title startet for $n minutter siden';
    case 'sv':
      return one
          ? '$title började för 1 minut sedan'
          : '$title började för $n minuter sedan';
    case 'ar':
      return one ? '$title بدأ منذ دقيقة' : '$title بدأ منذ $n دقائق';
    case 'ru':
      return one
          ? '$title началось 1 минуту назад'
          : '$title началось $n мин назад';
    case 'tr':
      return '$title $n dakika önce başladı';
    case 'hi':
      return '$title $n मिनट पहले शुरू हुआ';
    case 'zh':
      return '$title 已开始 $n 分钟';
    case 'sw':
      return '$title ilianza dakika $n zilizopita';
    case 'fr':
    default:
      return one
          ? '$title a commencé il y a 1 minute'
          : '$title a commencé il y a $n minutes';
  }
}

/// « Journal est terminée ».
String finishedLine(String languageCode, String title) {
  switch (_code(languageCode)) {
    case 'en':
      return '$title is over';
    case 'es':
      return '$title ha terminado';
    case 'de':
      return '$title ist zu Ende';
    case 'pt':
      return '$title terminou';
    case 'it':
      return '$title è finito';
    case 'nl':
      return '$title is afgelopen';
    case 'da':
      return '$title er slut';
    case 'nb':
      return '$title er ferdig';
    case 'sv':
      return '$title är slut';
    case 'ar':
      return '$title انتهى';
    case 'ru':
      return '$title закончилось';
    case 'tr':
      return '$title bitti';
    case 'hi':
      return '$title समाप्त';
    case 'zh':
      return '$title 已结束';
    case 'sw':
      return '$title imeisha';
    case 'fr':
    default:
      return '$title est terminée';
  }
}

/// Phrase du bandeau selon le moment.
String cueLine(String languageCode, ShowCue cue) {
  switch (cue.moment) {
    case ShowMoment.soon:
      return startsInLine(languageCode, cue.title, cue.minutes);
    case ShowMoment.started:
    case ShowMoment.onAir:
      return startedAgoLine(languageCode, cue.title, cue.minutes);
    case ShowMoment.finished:
      return finishedLine(languageCode, cue.title);
  }
}

/// Sous-titre d'une carte de la rangée.
String rowSubtitle(String languageCode, ShowCue cue) {
  final String when = switch (cue.rowGroup) {
    ShowMoment.onAir => followedWord(languageCode, 'on'),
    ShowMoment.soon =>
      '${followedWord(languageCode, 'soon')} · ${cue.minutes} min',
    ShowMoment.started =>
      '${followedWord(languageCode, 'late')} · ${cue.minutes} min',
    ShowMoment.finished => finishedLine(languageCode, cue.title),
  };
  final String channel = cue.channelName.trim();
  if (channel.isEmpty) return when;
  return '$when · $channel';
}

/// Mot court (bouton, titre de rangée, réglage).
String followedWord(String languageCode, String id) {
  final Map<String, String>? row = _words[_code(languageCode)] ?? _words['fr'];
  return row?[id] ?? _words['fr']![id] ?? id;
}

/// « OK passe au délai suivant : 2, 5, 10 ou 15 minutes. »
String leadHint(String languageCode) {
  switch (_code(languageCode)) {
    case 'en':
      return 'OK picks the next delay: 2, 5, 10 or 15 minutes.';
    case 'es':
      return 'OK elige el siguiente aviso: 2, 5, 10 o 15 minutos.';
    case 'de':
      return 'OK wählt die nächste Frist: 2, 5, 10 oder 15 Minuten.';
    case 'pt':
      return 'OK escolhe o aviso seguinte: 2, 5, 10 ou 15 minutos.';
    case 'it':
      return 'OK sceglie il prossimo avviso: 2, 5, 10 o 15 minuti.';
    case 'nl':
      return 'OK kiest de volgende termijn: 2, 5, 10 of 15 minuten.';
    case 'da':
      return 'OK vælger næste frist: 2, 5, 10 eller 15 minutter.';
    case 'nb':
      return 'OK velger neste frist: 2, 5, 10 eller 15 minutter.';
    case 'sv':
      return 'OK väljer nästa tid: 2, 5, 10 eller 15 minuter.';
    case 'ar':
      return 'موافق يختار المهلة التالية: 2 أو 5 أو 10 أو 15 دقيقة.';
    case 'ru':
      return 'OK выбирает следующий срок: 2, 5, 10 или 15 минут.';
    case 'tr':
      return 'OK sıradaki süreyi seçer: 2, 5, 10 veya 15 dakika.';
    case 'hi':
      return 'OK अगली देरी चुनता है: 2, 5, 10 या 15 मिनट.';
    case 'zh':
      return '按 OK 切换下一项：2、5、10 或 15 分钟。';
    case 'sw':
      return 'OK kuchagua muda unaofuata: dakika 2, 5, 10 au 15.';
    case 'fr':
    default:
      return 'OK passe au délai suivant : 2, 5, 10 ou 15 minutes.';
  }
}

/// « Prévenir 5 minutes avant. OK pour changer. »
String leadLine(String languageCode, int minutes) {
  return followedWord(languageCode, 'lead').replaceAll('{n}', '$minutes');
}

const Map<String, Map<String, String>> _words = <String, Map<String, String>>{
  'fr': <String, String>{
    'row': 'Tes émissions',
    'on': 'En cours',
    'soon': 'Bientôt',
    'late': 'Déjà commencée',
    'watch': 'Regarder',
    'live': 'Regarder en direct',
    'start': 'Reprendre depuis le début',
    'replay': 'Rediffusion',
    'later': 'Plus tard',
    'follow': 'Suivre',
    'following': 'Suivi',
    'flashOn': 'Émission suivie',
    'flashOff': 'Émission retirée',
    'setOn':
        'L\'app repère tes émissions et prévient avant qu\'elles commencent. OK pour couper. Rien ne se lance tout seul. Tout reste sur la box.',
    'setOff':
        'Coupé. OK pour rallumer. On n\'apprend plus, et le bandeau disparaît.',
    'lead': 'Prévenir {n} minutes avant. OK pour changer.',
  },
  'en': <String, String>{
    'row': 'Your shows',
    'on': 'On now',
    'soon': 'Soon',
    'late': 'Already started',
    'watch': 'Watch',
    'live': 'Watch live',
    'start': 'Resume from the start',
    'replay': 'Replay',
    'later': 'Later',
    'follow': 'Follow',
    'following': 'Following',
    'flashOn': 'Show followed',
    'flashOff': 'Show removed',
    'setOn':
        'The app notices your shows and warns you before they start. OK to turn off. Nothing starts on its own. It all stays on the box.',
    'setOff': 'Off. OK to turn on. We stop learning, and the banner goes away.',
    'lead': 'Warn {n} minutes before. OK to change.',
  },
  'es': <String, String>{
    'row': 'Tus programas',
    'on': 'En curso',
    'soon': 'Pronto',
    'late': 'Ya empezó',
    'watch': 'Ver',
    'live': 'Ver en directo',
    'start': 'Volver al inicio',
    'replay': 'Repetición',
    'later': 'Luego',
    'follow': 'Seguir',
    'following': 'Seguido',
    'flashOn': 'Programa seguido',
    'flashOff': 'Programa quitado',
    'setOn':
        'La app detecta tus programas y avisa antes de que empiecen. OK para apagar. Nada se abre solo. Todo queda en la box.',
    'setOff':
        'Apagado. OK para encender. Ya no aprende, y el aviso desaparece.',
    'lead': 'Avisar {n} minutos antes. OK para cambiar.',
  },
  'de': <String, String>{
    'row': 'Deine Sendungen',
    'on': 'Läuft',
    'soon': 'Gleich',
    'late': 'Schon begonnen',
    'watch': 'Ansehen',
    'live': 'Live ansehen',
    'start': 'Von vorn',
    'replay': 'Wiederholung',
    'later': 'Später',
    'follow': 'Folgen',
    'following': 'Folge ich',
    'flashOn': 'Sendung gemerkt',
    'flashOff': 'Sendung entfernt',
    'setOn':
        'Die App merkt sich deine Sendungen und warnt vorher. OK zum Ausschalten. Nichts startet von allein. Alles bleibt auf der Box.',
    'setOff':
        'Aus. OK zum Einschalten. Es wird nichts mehr gelernt, der Hinweis verschwindet.',
    'lead': '{n} Minuten vorher warnen. OK zum Ändern.',
  },
  'pt': <String, String>{
    'row': 'Os teus programas',
    'on': 'A decorrer',
    'soon': 'Em breve',
    'late': 'Já começou',
    'watch': 'Ver',
    'live': 'Ver em direto',
    'start': 'Retomar do início',
    'replay': 'Repetição',
    'later': 'Depois',
    'follow': 'Seguir',
    'following': 'A seguir',
    'flashOn': 'Programa seguido',
    'flashOff': 'Programa retirado',
    'setOn':
        'A app reconhece os teus programas e avisa antes de começarem. OK para desligar. Nada abre sozinho. Tudo fica na box.',
    'setOff': 'Desligado. OK para ligar. Deixa de aprender, e o aviso some.',
    'lead': 'Avisar {n} minutos antes. OK para mudar.',
  },
  'it': <String, String>{
    'row': 'I tuoi programmi',
    'on': 'In corso',
    'soon': 'Tra poco',
    'late': 'Già iniziato',
    'watch': 'Guarda',
    'live': 'Guarda in diretta',
    'start': 'Riprendi dall\'inizio',
    'replay': 'Replica',
    'later': 'Più tardi',
    'follow': 'Segui',
    'following': 'Seguito',
    'flashOn': 'Programma seguito',
    'flashOff': 'Programma tolto',
    'setOn':
        'L\'app nota i tuoi programmi e avvisa prima che inizino. OK per spegnere. Niente parte da solo. Tutto resta sulla box.',
    'setOff':
        'Spento. OK per riaccendere. Non impara più, e l\'avviso sparisce.',
    'lead': 'Avvisa {n} minuti prima. OK per cambiare.',
  },
  'nl': <String, String>{
    'row': 'Jouw programma\'s',
    'on': 'Bezig',
    'soon': 'Zo',
    'late': 'Al begonnen',
    'watch': 'Kijken',
    'live': 'Live kijken',
    'start': 'Vanaf het begin',
    'replay': 'Herhaling',
    'later': 'Later',
    'follow': 'Volgen',
    'following': 'Gevolgd',
    'flashOn': 'Programma gevolgd',
    'flashOff': 'Programma weg',
    'setOn':
        'De app herkent je programma\'s en waarschuwt van tevoren. OK om uit te zetten. Niets start vanzelf. Alles blijft op de box.',
    'setOff':
        'Uit. OK om aan te zetten. Er wordt niets meer geleerd, de balk verdwijnt.',
    'lead': '{n} minuten van tevoren waarschuwen. OK om te wijzigen.',
  },
  'da': <String, String>{
    'row': 'Dine programmer',
    'on': 'I gang',
    'soon': 'Snart',
    'late': 'Allerede i gang',
    'watch': 'Se',
    'live': 'Se live',
    'start': 'Fra starten',
    'replay': 'Genudsendelse',
    'later': 'Senere',
    'follow': 'Følg',
    'following': 'Fulgt',
    'flashOn': 'Program fulgt',
    'flashOff': 'Program fjernet',
    'setOn':
        'Appen finder dine programmer og advarer før de starter. OK for at slukke. Intet starter af sig selv. Alt bliver på boksen.',
    'setOff':
        'Slukket. OK for at tænde. Den lærer ikke mere, og banneret forsvinder.',
    'lead': 'Advar {n} minutter før. OK for at skifte.',
  },
  'nb': <String, String>{
    'row': 'Programmene dine',
    'on': 'Pågår',
    'soon': 'Snart',
    'late': 'Allerede i gang',
    'watch': 'Se',
    'live': 'Se direkte',
    'start': 'Fra starten',
    'replay': 'Reprise',
    'later': 'Senere',
    'follow': 'Følg',
    'following': 'Fulgt',
    'flashOn': 'Program fulgt',
    'flashOff': 'Program fjernet',
    'setOn':
        'Appen finner programmene dine og varsler før de starter. OK for å slå av. Ingenting starter av seg selv. Alt blir på boksen.',
    'setOff':
        'Av. OK for å slå på. Den lærer ikke mer, og banneret forsvinner.',
    'lead': 'Varsle {n} minutter før. OK for å endre.',
  },
  'sv': <String, String>{
    'row': 'Dina program',
    'on': 'Pågår',
    'soon': 'Snart',
    'late': 'Redan igång',
    'watch': 'Titta',
    'live': 'Titta live',
    'start': 'Från början',
    'replay': 'Repris',
    'later': 'Senare',
    'follow': 'Följ',
    'following': 'Följer',
    'flashOn': 'Program följt',
    'flashOff': 'Program borttaget',
    'setOn':
        'Appen hittar dina program och varnar innan de börjar. OK för att stänga av. Inget startar av sig själv. Allt stannar på boxen.',
    'setOff':
        'Av. OK för att slå på. Den lär sig inte mer, och bannern försvinner.',
    'lead': 'Varna {n} minuter innan. OK för att ändra.',
  },
  'ar': <String, String>{
    'row': 'برامجك',
    'on': 'يعرض الآن',
    'soon': 'قريبًا',
    'late': 'بدأ بالفعل',
    'watch': 'شاهد',
    'live': 'شاهد مباشرة',
    'start': 'من البداية',
    'replay': 'إعادة',
    'later': 'لاحقًا',
    'follow': 'متابعة',
    'following': 'تُتابَع',
    'flashOn': 'تمت متابعة البرنامج',
    'flashOff': 'أُزيل البرنامج',
    'setOn':
        'يتعرّف التطبيق على برامجك وينبّهك قبل أن تبدأ. موافق للإيقاف. لا يفتح شيئًا وحده. كل شيء يبقى على الجهاز.',
    'setOff': 'متوقف. موافق للتشغيل. لن يتعلّم بعد الآن، ويختفي الشريط.',
    'lead': 'التنبيه قبل {n} دقائق. موافق للتغيير.',
  },
  'ru': <String, String>{
    'row': 'Ваши передачи',
    'on': 'Сейчас',
    'soon': 'Скоро',
    'late': 'Уже началась',
    'watch': 'Смотреть',
    'live': 'Смотреть эфир',
    'start': 'С начала',
    'replay': 'Повтор',
    'later': 'Позже',
    'follow': 'Следить',
    'following': 'Слежу',
    'flashOn': 'Передача добавлена',
    'flashOff': 'Передача убрана',
    'setOn':
        'Приложение замечает ваши передачи и предупреждает заранее. OK чтобы выключить. Само ничего не запускает. Всё остаётся на приставке.',
    'setOff':
        'Выключено. OK чтобы включить. Больше не запоминает, полоска исчезает.',
    'lead': 'Предупреждать за {n} минут. OK чтобы сменить.',
  },
  'tr': <String, String>{
    'row': 'Programların',
    'on': 'Yayında',
    'soon': 'Yakında',
    'late': 'Çoktan başladı',
    'watch': 'İzle',
    'live': 'Canlı izle',
    'start': 'Baştan sürdür',
    'replay': 'Tekrar',
    'later': 'Sonra',
    'follow': 'Takip et',
    'following': 'Takipte',
    'flashOn': 'Program takipte',
    'flashOff': 'Program çıkarıldı',
    'setOn':
        'Uygulama programlarını fark eder ve başlamadan haber verir. Kapatmak için OK. Hiçbir şey kendiliğinden açılmaz. Hepsi kutuda kalır.',
    'setOff': 'Kapalı. Açmak için OK. Artık öğrenmez, şerit kaybolur.',
    'lead': '{n} dakika önce haber ver. Değiştirmek için OK.',
  },
  'hi': <String, String>{
    'row': 'आपके कार्यक्रम',
    'on': 'अभी चल रहा',
    'soon': 'जल्द',
    'late': 'शुरू हो चुका',
    'watch': 'देखें',
    'live': 'लाइव देखें',
    'start': 'शुरुआत से',
    'replay': 'पुनः प्रसारण',
    'later': 'बाद में',
    'follow': 'फ़ॉलो',
    'following': 'फ़ॉलो है',
    'flashOn': 'कार्यक्रम फ़ॉलो हुआ',
    'flashOff': 'कार्यक्रम हटा',
    'setOn':
        'ऐप आपके कार्यक्रम पहचानती है और शुरू होने से पहले बताती है. बंद करने के लिए OK. कुछ अपने आप नहीं खुलता. सब बॉक्स पर रहता है.',
    'setOff': 'बंद. चालू करने के लिए OK. अब नहीं सीखेगी, और पट्टी हट जाएगी.',
    'lead': '{n} मिनट पहले बताएँ. बदलने के लिए OK.',
  },
  'zh': <String, String>{
    'row': '你的节目',
    'on': '正在播出',
    'soon': '即将开始',
    'late': '已经开始',
    'watch': '观看',
    'live': '看直播',
    'start': '从头播放',
    'replay': '重播',
    'later': '稍后',
    'follow': '关注',
    'following': '已关注',
    'flashOn': '已关注节目',
    'flashOff': '已取消关注',
    'setOn': '应用会认出你的节目，并在开始前提醒。按 OK 关闭。不会自己打开。数据只留在盒子上。',
    'setOff': '已关闭。按 OK 打开。不再学习，提示条消失。',
    'lead': '提前 {n} 分钟提醒。按 OK 更改。',
  },
  'sw': <String, String>{
    'row': 'Vipindi vyako',
    'on': 'Inaendelea',
    'soon': 'Hivi karibuni',
    'late': 'Imeanza tayari',
    'watch': 'Tazama',
    'live': 'Tazama moja kwa moja',
    'start': 'Anza tangu mwanzo',
    'replay': 'Rudia',
    'later': 'Baadaye',
    'follow': 'Fuata',
    'following': 'Unafuata',
    'flashOn': 'Kipindi kinafuatwa',
    'flashOff': 'Kipindi kimeondolewa',
    'setOn':
        'Programu inatambua vipindi vyako na kukuonya kabla havijaanza. OK kuzima. Hakuna kinachojiwasha. Yote inabaki kwenye kisanduku.',
    'setOff': 'Imezimwa. OK kuwasha. Haijifunzi tena, na utepe unaondoka.',
    'lead': 'Onya dakika {n} kabla. OK kubadilisha.',
  },
};
