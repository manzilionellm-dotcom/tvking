// =========================================================
//  trial_block_copy.dart — Texte de l'écran « essai terminé »
// =========================================================
//  Texte CHALEUREUX, court, professionnel. Français et anglais.
//  Le panel peut remplacer le titre et le corps (champs vides =
//  on garde ce texte). Le lien de paiement reste vide tant que
//  personne ne le remplit : on n'invente pas de caisse.
//
//  Fonction pure : testable sans écran ni réseau.
// =========================================================

class TrialBlockText {
  const TrialBlockText({
    required this.title,
    required this.body,
    required this.payUrl,
    required this.french,
    required this.whatsAppLabel,
    required this.phoneLabel,
    required this.payLabel,
    required this.macLabel,
    required this.daysLabel,
  });

  final String title;
  final String body;

  /// Lien https du panel. Vide = l'écran utilise le site déjà connu
  /// du projet (https://7themotion.com) et WhatsApp.
  final String payUrl;
  final bool french;
  final String whatsAppLabel;
  final String phoneLabel;
  final String payLabel;
  final String macLabel;

  /// Modèle « Essai · 3 j » / « Trial · 3 d ». Le nombre est à part.
  final String daysLabel;
}

const String kBuiltInTitleFr = 'Ton essai de 7 jours est terminé';
const String kBuiltInBodyFr =
    'Merci d’avoir essayé l’application. Pour continuer, active ton accès : '
    'envoie l’identifiant ci-dessous à ton revendeur. Il te débloque en quelques instants.';
const String kBuiltInTitleEn = 'Your 7-day trial has ended';
const String kBuiltInBodyEn =
    'Thank you for trying the app. To keep going, activate your access: '
    'send the device ID below to your reseller. They will unlock it in a few moments.';

/// [languageCode] : « fr » → français, tout le reste → anglais.
/// Un texte panel non vide remplace le texte intégré de CETTE langue.
TrialBlockText resolveTrialBlock({
  required String languageCode,
  String titleFr = '',
  String bodyFr = '',
  String titleEn = '',
  String bodyEn = '',
  String payUrl = '',
  required int daysLeft,
}) {
  final bool french = languageCode.toLowerCase().startsWith('fr');
  final String customTitle = (french ? titleFr : titleEn).trim();
  final String customBody = (french ? bodyFr : bodyEn).trim();
  final String title = customTitle.isNotEmpty
      ? customTitle
      : (french ? kBuiltInTitleFr : kBuiltInTitleEn);
  final String body = customBody.isNotEmpty
      ? customBody
      : (french ? kBuiltInBodyFr : kBuiltInBodyEn);
  final String days = french ? 'Essai · $daysLeft j' : 'Trial · $daysLeft d';
  return TrialBlockText(
    title: title,
    body: body,
    payUrl: payUrl.trim(),
    french: french,
    whatsAppLabel: french ? 'Écrire sur WhatsApp' : 'Message on WhatsApp',
    phoneLabel: french ? 'Appeler' : 'Call',
    payLabel: french ? 'Voir comment activer' : 'See how to activate',
    macLabel: french ? 'Identifiant de l’appareil' : 'Device ID',
    daysLabel: days,
  );
}
