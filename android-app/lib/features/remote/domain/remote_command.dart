// =========================================================
//  remote_command.dart — Ce que le téléphone a le DROIT d'envoyer
// =========================================================
//  Liste fermée. Tout le reste (une adresse, un fichier, une commande
//  système, un volume absolu…) est refusé. Le téléphone ne peut que
//  imiter une télécommande : flèches, OK, retour, volume d'un cran,
//  chaîne d'un cran, et un texte court pour la recherche.
// =========================================================

/// Touches autorisées. Le nom est celui du JSON `{"a":"up"}`.
enum RemoteButton {
  up,
  down,
  left,
  right,
  ok,
  back,
  volumeUp,
  volumeDown,
  channelUp,
  channelDown,
}

/// Une commande déjà vérifiée. Le serveur ne construit JAMAIS ça
/// à partir d'un texte libre : seulement via [parseRemoteCommand].
sealed class RemoteCommand {
  const RemoteCommand();
}

class RemotePress extends RemoteCommand {
  const RemotePress(this.button);
  final RemoteButton button;
}

/// Texte de recherche (ou contenu d'un champ). Déjà nettoyé :
/// pas de caractères de contrôle, au plus [kRemoteTextMax] caractères.
class RemoteQuery extends RemoteCommand {
  const RemoteQuery(this.text);
  final String text;
}

/// Plafond du texte. Assez long pour une adresse Xtream collée dans
/// « Ajouter une source », trop court pour servir de tunnel.
const int kRemoteTextMax = 240;

/// Noms JSON autorisés pour une touche. Source unique : la page web
/// et le parseur s'y réfèrent, les tests vérifient qu'ils coïncident.
const Map<String, RemoteButton> kRemoteButtonNames = <String, RemoteButton>{
  'up': RemoteButton.up,
  'down': RemoteButton.down,
  'left': RemoteButton.left,
  'right': RemoteButton.right,
  'ok': RemoteButton.ok,
  'back': RemoteButton.back,
  'vol_up': RemoteButton.volumeUp,
  'vol_down': RemoteButton.volumeDown,
  'ch_up': RemoteButton.channelUp,
  'ch_down': RemoteButton.channelDown,
};

/// Corps JSON d'une commande, ou null si on doit répondre 400
/// SANS exécuter quoi que ce soit.
///
/// [json] est l'objet déjà décodé (`{"a":"up"}` ou
/// `{"a":"query","t":"tf1"}`). On ignore les champs inconnus :
/// ils ne donnent aucun pouvoir en plus.
RemoteCommand? parseRemoteCommand(Object? json) {
  if (json is! Map) return null;
  final Object? action = json['a'];
  if (action is! String) return null;
  if (action == 'query') {
    final Object? raw = json['t'];
    if (raw is! String) return null;
    final String? clean = sanitizeRemoteText(raw);
    if (clean == null) return null;
    return RemoteQuery(clean);
  }
  final RemoteButton? button = kRemoteButtonNames[action];
  if (button == null) return null;
  return RemotePress(button);
}

/// Enlève les caractères de contrôle (retours ligne, nuls, marques
/// bidi qui inversent l'affichage) et refuse au-delà de
/// [kRemoteTextMax]. Renvoie null si le texte est trop long APRÈS
/// nettoyage — on ne coupe pas en silence (le téléphone a un
/// `maxlength` identique, un dépassement est une requête anormale).
///
/// La chaîne vide est valide : c'est « effacer la recherche ».
String? sanitizeRemoteText(String raw) {
  final StringBuffer out = StringBuffer();
  for (final int rune in raw.runes) {
    if (rune < 0x20 || rune == 0x7F) continue;
    // Marques bidirectionnelles : un nom de chaîne n'en a pas besoin,
    // et elles peuvent masquer ce qui s'affiche sur la box.
    if (rune >= 0x202A && rune <= 0x202E) continue;
    if (rune >= 0x2066 && rune <= 0x2069) continue;
    out.writeCharCode(rune);
  }
  final String text = out.toString();
  if (text.length > kRemoteTextMax) return null;
  return text;
}
