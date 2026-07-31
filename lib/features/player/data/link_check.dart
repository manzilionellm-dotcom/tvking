// =========================================================
//  link_check.dart — Vérification d'un lien AVANT lecture
// =========================================================
//  Engagement porté de TV King : « Chaque lien est vérifié avant
//  lecture — un lien invalide est signalé avec sa raison et n'est
//  jamais envoyé au lecteur : aucune attente sans fin. »
//
//  La vérification est PUREMENT SYNCHRONE (trim → parse URI →
//  schéma http/https → hôte non vide) : instantanée, sans réseau,
//  donc sans risque de bloquer une lecture valide à cause d'un
//  sondage qui échoue (philosophie fail-open du reste du code —
//  cf. cellular_guard.dart, hls_preflight.dart). Un lien qui
//  échoue ICI ne pourrait de toute façon JAMAIS être lu : le
//  refuser n'enlève rien, il remplace 25 s de timeout lecteur
//  par un message immédiat et actionnable.
// =========================================================

/// Raison structurée d'un refus — traduite côté UI via l10n.
enum LinkCheckReason { empty, unreadable, scheme, noHost }

/// Résultat de la vérification : `ok` ou une raison de refus.
class LinkCheck {
  const LinkCheck.ok()
      : ok = true,
        reason = null;
  const LinkCheck.bad(LinkCheckReason this.reason) : ok = false;

  final bool ok;
  final LinkCheckReason? reason;
}

/// Vérifie qu'une URL de flux est structurellement lisible par le
/// lecteur. Ne fait AUCUN appel réseau — voir l'en-tête du fichier.
LinkCheck verifyStreamUrl(String url) {
  final String trimmed = url.trim();
  if (trimmed.isEmpty) return const LinkCheck.bad(LinkCheckReason.empty);

  final Uri? parsed = Uri.tryParse(trimmed);
  // Uri.tryParse est très permissif : « pas une url » se parse en Uri
  // sans schéma. On exige donc un schéma explicite pour distinguer
  // « illisible » de « protocole non pris en charge ».
  if (parsed == null) return const LinkCheck.bad(LinkCheckReason.unreadable);
  if (!parsed.hasScheme) {
    return const LinkCheck.bad(LinkCheckReason.unreadable);
  }
  if (parsed.scheme != 'http' && parsed.scheme != 'https') {
    return const LinkCheck.bad(LinkCheckReason.scheme);
  }
  if (parsed.host.isEmpty) return const LinkCheck.bad(LinkCheckReason.noHost);
  return const LinkCheck.ok();
}
