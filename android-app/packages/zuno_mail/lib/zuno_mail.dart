// =========================================================
//  zuno_mail — le canal, pas l'envoi
// =========================================================
//  Le plugin enregistre le MethodChannel côté Android. Le code
//  de l'application l'appelle par ce nom. Rien n'est envoyé
//  depuis ce fichier.
library zuno_mail;

/// Doit être le même que ZunoMailPlugin.CHANNEL.
const String kZunoMailChannel = 'com.manzilionellm.zuno/mail';
