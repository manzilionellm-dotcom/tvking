// Résumé de la politique publiée pour le paquet com.sevenmotion.novatube.tv.
// Les éditions génériques gardent leurs mentions existantes. La page publique
// existe en français et en anglais ; les autres langues ouvrent l'anglais.
// Ce résumé décrit les traitements effectifs sans remplacer la page complète.

Uri novatubePrivacyUri(String languageCode) => Uri.parse(
  'https://novatube-legal.manzilionel-lm.workers.dev/privacy/tv/'
  '${languageCode == 'fr' ? 'fr' : 'en'}',
);

String novatubePrivacySummary(String languageCode) {
  final String summary = languageCode == 'fr'
      ? _frenchSummary
      : _englishSummary;
  // L'adresse reste lisible sur une TV même si aucun navigateur n'est installé.
  return '$summary\n\n${novatubePrivacyUri(languageCode)}';
}

const String _frenchSummary =
    'Pour NOVATUBE MAX, le service api.zuno8k.com reçoit automatiquement '
    'l’identifiant de l’appareil, une clé d’installation, le modèle et les '
    'versions Android/application. Il conserve l’état de licence, la présence, '
    'l’adresse IP et le pays approximatif déduit de la connexion. Il reçoit '
    'aussi l’inventaire des sources '
    '(noms, serveurs, nombre de chaînes) et les identifiants de chaînes récemment '
    'regardées pour le fonctionnement et le suivi technique. Le nom '
    'd’utilisateur Xtream peut être transmis dans cet inventaire, '
    'puis retiré avant son stockage.\n\n'
    'L’envoi des journaux techniques au support est activé par défaut. Vous '
    'pouvez le couper dans Réglages → En plus → Journal au support. Cela ne coupe '
    'pas les échanges automatiques de licence, de présence et d’inventaire, ni '
    'l’audit des attributions par code d’accès et des récupérations de clé.\n\n'
    'L’assistance de recherche distante est facultative et désactivée par défaut. '
    'Si vous l’activez, votre recherche est envoyée au service puis à Mistral AI '
    'lorsqu’il est configuré. La recherche vocale utilise le service Android de '
    'reconnaissance vocale.\n\n'
    'Sur téléphone ou tablette compatible, certaines diffusions Cast transmettent '
    'au relais l’URL du flux, qui peut contenir les identifiants du fournisseur. '
    'Google Cast transmet également des événements techniques à Google.\n\n'
    'Les échanges avec notre service utilisent HTTPS ; vos sources peuvent '
    'utiliser HTTP. Effacer les données locales ne supprime pas les données du '
    'serveur. Aucun délai maximal d’effacement automatique n’est garanti. La '
    'politique complète précise les destinataires, la conservation et les moyens '
    'de contact.';

const String _englishSummary =
    'For NOVATUBE MAX, the api.zuno8k.com service automatically receives the '
    'device identifier, installation key, device model and Android/app versions. '
    'It stores licence status, presence information, IP address and the '
    'approximate country inferred from the connection. It also receives a '
    'source inventory (names, servers, channel counts) and identifiers of '
    'recently watched channels for operation and technical monitoring. '
    'The Xtream username may be sent '
    'in this inventory, then removed before the inventory is stored.\n\n'
    'Sending technical logs to support is enabled by default. You can disable '
    'it in Settings → Extras → Log to support (Réglages → En plus → Journal au '
    'support in French). This does not stop automatic licence, presence and '
    'inventory exchanges, or the audit of access-code grants and key '
    'recoveries.\n\n'
    'Remote search assistance is optional and disabled by default. If you '
    'enable it, your search is sent to the service and then to Mistral AI when '
    'configured. Voice search uses Android’s speech-recognition service.\n\n'
    'On compatible phones or tablets, some Cast playback sends the stream URL '
    'to the relay; that URL may contain provider credentials. Google Cast also '
    'sends technical events to Google.\n\n'
    'Connections to our service use HTTPS; your sources may use HTTP. Clearing '
    'local data does not erase server data. No maximum automatic-deletion '
    'period is guaranteed. The full policy describes recipients, retention '
    'and contact options.';
