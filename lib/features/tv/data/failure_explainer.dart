// =========================================================
//  failure_explainer.dart — Le POURQUOI humain d'un échec de lecture
// =========================================================
//  Table de traduction PURE et TESTABLE : (code d'erreur ExoPlayer stable,
//  contexte) → phrase en français que le client comprend, + conseil
//  actionnable. C'est le cœur du volet « Chaînes qui ne s'ouvrent pas »
//  de la Boîte noire (Réglages).
//
//  CONTRAT DIX ANS (exigence produit : « une boîte noire que je ne veux
//  pas changer, qui peut travailler même dix ans ») :
//    • On ne se base QUE sur les CODES Media3/ExoPlayer (`errorCodeName`,
//      constante stable ex. "ERROR_CODE_IO_BAD_HTTP_STATUS", et
//      `errorCode` numérique). JAMAIS sur le TEXTE d'un message d'erreur :
//      les textes changent entre versions ExoPlayer, les codes sont
//      contractuels (c'est déjà la philosophie du pont natif,
//      cf. NativeVideoView.kt).
//      Seule exception ASSUMÉE et tolérante : pour BAD_HTTP_STATUS, le code
//      HTTP réel (456, 403…) ne voyage QUE dans le message de la cause —
//      on tente d'y repêcher un nombre 4xx/5xx ; si on ne trouve rien, on
//      retombe sur un verdict générique propre (jamais de crash, jamais de
//      dépendance à la formulation).
//    • Un code INCONNU (version future d'ExoPlayer) tombe sur un verdict
//      générique avec le code brut à donner au support — l'app ne casse
//      pas, elle reste utile.
//    • Fonctions PURES (aucun I/O, aucun singleton) → testables à vie.
// =========================================================

/// Verdict humain d'un échec de lecture : le POURQUOI en une phrase,
/// et un conseil actionnable.
class PlaybackFailureExplanation {
  const PlaybackFailureExplanation({required this.why, required this.advice});

  /// Le POURQUOI, en français humain (« Ton fournisseur limite le nombre
  /// d'écrans en même temps »).
  final String why;

  /// Le conseil actionnable (« Ferme l'app sur l'autre appareil »).
  final String advice;

  @override
  String toString() => '$why — $advice';
}

/// Tente d'extraire un code HTTP (4xx/5xx) du message de CAUSE d'une erreur
/// ERROR_CODE_IO_BAD_HTTP_STATUS. Media3 ne transporte le statut HTTP que
/// dans le texte de la cause (« Response code: 456 ») — on repêche le
/// premier nombre 400-599 rencontré, sans dépendre de la formulation.
/// `null` si rien de plausible (tolérance totale : jamais d'exception).
int? extractHttpStatus(String? cause) {
  if (cause == null || cause.isEmpty) return null;
  final RegExp num3 = RegExp(r'\b([45]\d\d)\b');
  final Match? m = num3.firstMatch(cause);
  if (m == null) return null;
  return int.tryParse(m.group(1)!);
}

/// Traduit un échec de lecture en verdict humain. FONCTION PURE.
///
///  • [errorCodeName] : constante Media3 STABLE (ex.
///    "ERROR_CODE_IO_NETWORK_CONNECTION_FAILED"). Prioritaire.
///  • [errorCode] : équivalent numérique (2001…) — repli si le nom manque.
///  • [cause] : message de la cause racine — utilisé UNIQUEMENT pour
///    repêcher un code HTTP (cf. [extractHttpStatus]), jamais pour matcher
///    du texte.
///  • [everShownFrame] : la chaîne a-t-elle affiché au moins une image
///    avant de tomber ? (coupure en cours de lecture ≠ chaîne jamais ouverte)
///  • [dnsFailed] : le diagnostic réseau a-t-il conclu à un DNS KO ?
///    (affine le verdict des erreurs de connexion)
///  • [httpStatus] : code HTTP si déjà connu par l'appelant (prime sur
///    l'extraction depuis [cause]).
PlaybackFailureExplanation explainPlaybackFailure({
  String? errorCodeName,
  int? errorCode,
  String? cause,
  bool everShownFrame = false,
  bool dnsFailed = false,
  int? httpStatus,
}) {
  final String name = errorCodeName ?? _nameFromNumericCode(errorCode);

  switch (name) {
    // ---- Réseau : la box ne joint pas le serveur ----
    case 'ERROR_CODE_IO_NETWORK_CONNECTION_FAILED':
      if (dnsFailed) {
        return const PlaybackFailureExplanation(
          why: 'La box n\'arrive pas à joindre internet (le DNS ne répond '
              'pas).',
          advice: 'Vérifie le Wi-Fi/câble de la box, redémarre-la, ou change '
              'le DNS (ex. 8.8.8.8).',
        );
      }
      return PlaybackFailureExplanation(
        why: everShownFrame
            ? 'La connexion au serveur du fournisseur s\'est coupée en pleine '
                'lecture.'
            : 'La box n\'arrive pas à joindre le serveur du fournisseur '
                '(internet coupé ou serveur injoignable).',
        advice: 'Vérifie la connexion internet de la box ; si internet '
            'marche ailleurs, le serveur du fournisseur est peut-être bloqué '
            '(un VPN peut aider).',
      );
    case 'ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT':
      return PlaybackFailureExplanation(
        why: everShownFrame
            ? 'Le serveur du fournisseur est lent ou saturé (il a cessé de '
                'répondre en pleine lecture).'
            : 'Le serveur du fournisseur met trop de temps à répondre '
                '(lent ou saturé).',
        advice: 'Réessaie dans quelques minutes ; si ça dure, préviens ton '
            'fournisseur (son serveur est surchargé).',
      );

    // ---- HTTP : le serveur répond mais REFUSE ----
    case 'ERROR_CODE_IO_BAD_HTTP_STATUS':
      final int? status = httpStatus ?? extractHttpStatus(cause);
      return _explainHttpStatus(status);
    case 'ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE':
      return const PlaybackFailureExplanation(
        why: 'Le serveur renvoie autre chose que de la vidéo (une page '
            'd\'erreur déguisée) — le fournisseur bloque probablement la '
            'signature de ce lecteur.',
        advice: 'L\'app essaie automatiquement d\'autres signatures '
            '(VLC, Smarters…) ; si rien ne passe, vérifie la chaîne chez le '
            'fournisseur.',
      );
    case 'ERROR_CODE_IO_FILE_NOT_FOUND':
      return const PlaybackFailureExplanation(
        why: 'Le flux de cette chaîne n\'existe plus à cette adresse '
            '(supprimé ou déplacé chez le fournisseur).',
        advice: 'Actualise ta source (Réglages → Mes sources) pour récupérer '
            'les nouvelles adresses.',
      );
    case 'ERROR_CODE_IO_NO_PERMISSION':
      return const PlaybackFailureExplanation(
        why: 'L\'accès au flux est refusé (permission manquante).',
        advice: 'Vérifie que ton abonnement chez le fournisseur est actif.',
      );
    case 'ERROR_CODE_IO_CLEARTEXT_NOT_PERMITTED':
      return const PlaybackFailureExplanation(
        why: 'Le flux est en HTTP simple (non chiffré) et cette box '
            'l\'interdit.',
        advice: 'Demande au fournisseur une adresse en HTTPS, ou signale ce '
            'code au support.',
      );
    case 'ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE':
      return const PlaybackFailureExplanation(
        why: 'Le serveur a renvoyé un morceau de flux incohérent (lecture '
            'hors limites).',
        advice: 'Réessaie ; si ça persiste, le flux du fournisseur est '
            'défectueux.',
      );
    case 'ERROR_CODE_IO_UNSPECIFIED':
      return const PlaybackFailureExplanation(
        why: 'Problème réseau non précisé entre la box et le serveur du '
            'fournisseur.',
        advice: 'Vérifie la connexion de la box, puis réessaie.',
      );

    // ---- Flux abîmé / format non géré (côté fournisseur) ----
    case 'ERROR_CODE_PARSING_CONTAINER_MALFORMED':
    case 'ERROR_CODE_PARSING_MANIFEST_MALFORMED':
      return const PlaybackFailureExplanation(
        why: 'Le flux envoyé par le fournisseur est abîmé (données '
            'illisibles).',
        advice: 'Ce n\'est pas la box : signale la chaîne à ton fournisseur.',
      );
    case 'ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED':
    case 'ERROR_CODE_PARSING_MANIFEST_UNSUPPORTED':
      return const PlaybackFailureExplanation(
        why: 'Le format d\'emballage de ce flux n\'est pas géré par le '
            'lecteur.',
        advice: 'Signale ce code au support avec le nom de la chaîne.',
      );

    // ---- Décodage : c'est la BOX qui ne suit pas ----
    case 'ERROR_CODE_DECODER_INIT_FAILED':
    case 'ERROR_CODE_DECODER_QUERY_FAILED':
    case 'ERROR_CODE_DECODING_FAILED':
    case 'ERROR_CODE_DECODING_FORMAT_UNSUPPORTED':
      return const PlaybackFailureExplanation(
        why: 'Cette box ne sait pas décoder le format de cette chaîne '
            '(codec vidéo non supporté).',
        advice: 'Demande au fournisseur une version compatible de la chaîne '
            '(ex. H.264 au lieu de HEVC), ou essaie sur une box plus '
            'récente.',
      );
    case 'ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES':
      return const PlaybackFailureExplanation(
        why: 'Cette chaîne est trop lourde pour cette box (ex. flux 4K sur '
            'une box 1080p).',
        advice: 'Choisis la version SD/HD de la chaîne si le fournisseur en '
            'propose une.',
      );

    // ---- Audio ----
    case 'ERROR_CODE_AUDIO_TRACK_INIT_FAILED':
    case 'ERROR_CODE_AUDIO_TRACK_WRITE_FAILED':
      return const PlaybackFailureExplanation(
        why: 'La sortie audio de la box a refusé le son de cette chaîne.',
        advice: 'Redémarre la box ; vérifie les réglages audio (HDMI/ARC).',
      );

    // ---- Direct décroché ----
    case 'ERROR_CODE_BEHIND_LIVE_WINDOW':
      return const PlaybackFailureExplanation(
        why: 'Le direct a décroché (la lecture a pris trop de retard sur '
            'l\'antenne).',
        advice: 'Rien à faire : l\'app se recale automatiquement sur le '
            'direct.',
      );

    // ---- Génériques Media3 ----
    case 'ERROR_CODE_TIMEOUT':
      return const PlaybackFailureExplanation(
        why: 'Le lecteur a attendu trop longtemps une réponse (serveur lent '
            'ou saturé).',
        advice: 'Réessaie dans quelques minutes.',
      );
    case 'ERROR_CODE_REMOTE_ERROR':
      return const PlaybackFailureExplanation(
        why: 'Erreur signalée par un composant distant du lecteur.',
        advice: 'Réessaie ; si ça persiste, donne ce code au support.',
      );
    case 'ERROR_CODE_FAILED_RUNTIME_CHECK':
      return const PlaybackFailureExplanation(
        why: 'Le lecteur a détecté une incohérence interne.',
        advice: 'Redémarre l\'app ; si ça persiste, donne ce code au '
            'support.',
      );
  }

  // ---- DRM (famille complète, codes 6000-6999) ----
  if (name.startsWith('ERROR_CODE_DRM_')) {
    return const PlaybackFailureExplanation(
      why: 'Cette chaîne est protégée (DRM) et ce lecteur ne peut pas '
          'l\'ouvrir.',
      advice: 'Le fournisseur doit livrer une version non protégée du flux.',
    );
  }

  // ---- Familles inconnues mais RECONNAISSABLES au préfixe (codes futurs
  //      d'ExoPlayer : on reste utile sans connaître le code exact) ----
  if (name.startsWith('ERROR_CODE_IO_')) {
    return PlaybackFailureExplanation(
      why: 'Problème réseau entre la box et le serveur du fournisseur '
          '($name).',
      advice: 'Vérifie la connexion de la box, puis réessaie.',
    );
  }
  if (name.startsWith('ERROR_CODE_PARSING_')) {
    return PlaybackFailureExplanation(
      why: 'Le flux envoyé par le fournisseur est illisible ($name).',
      advice: 'Signale la chaîne à ton fournisseur.',
    );
  }
  if (name.startsWith('ERROR_CODE_DECOD') ||
      name.startsWith('ERROR_CODE_VIDEO_')) {
    return PlaybackFailureExplanation(
      why: 'Cette box n\'arrive pas à décoder cette chaîne ($name).',
      advice: 'Demande au fournisseur un format compatible (codec).',
    );
  }
  if (name.startsWith('ERROR_CODE_AUDIO_')) {
    return PlaybackFailureExplanation(
      why: 'Problème de son sur cette chaîne ($name).',
      advice: 'Redémarre la box ; vérifie les réglages audio.',
    );
  }

  // ---- Aucun code du tout : on raisonne sur le contexte ----
  if (errorCodeName == null && errorCode == null) {
    return PlaybackFailureExplanation(
      why: everShownFrame
          ? 'Le flux s\'est coupé en cours de lecture malgré les '
              'reconnexions automatiques (serveur du fournisseur instable).'
          : 'La chaîne n\'a jamais démarré : source vide ou bloquée par le '
              'fournisseur (souvent : déjà ouverte sur un autre appareil).',
      advice: everShownFrame
          ? 'Réessaie ; si ça se répète toujours sur cette chaîne, '
              'signale-la au fournisseur.'
          : 'Ferme l\'app sur les autres appareils, puis réessaie.',
    );
  }

  // ---- Verdict générique propre : code inconnu / futur ----
  final String shown = errorCodeName ?? 'CODE_${errorCode ?? '?'}';
  return PlaybackFailureExplanation(
    why: 'Erreur du lecteur ($shown).',
    advice: 'Donne ce code au support — il permet un diagnostic précis.',
  );
}

/// Verdict pour un code HTTP de refus (le serveur répond mais dit non).
PlaybackFailureExplanation _explainHttpStatus(int? status) {
  switch (status) {
    case 456:
    case 458:
      return PlaybackFailureExplanation(
        why: 'Ton fournisseur limite le nombre d\'écrans en même temps '
            '(HTTP $status) : ce compte est déjà utilisé ailleurs.',
        advice: 'Ferme l\'app sur l\'autre appareil, ou demande une '
            'connexion de plus au fournisseur.',
      );
    case 403:
    case 451:
      return PlaybackFailureExplanation(
        why: 'Le fournisseur ou le pays bloque ce flux (HTTP $status).',
        advice: 'Un VPN peut aider si cette chaîne fonctionne ailleurs ; '
            'sinon vérifie ton abonnement chez le fournisseur.',
      );
    case 401:
      return const PlaybackFailureExplanation(
        why: 'Le fournisseur refuse les identifiants (HTTP 401) : abonnement '
            'expiré ou mot de passe changé.',
        advice: 'Vérifie/renouvelle tes identifiants dans Réglages → Mes '
            'sources.',
      );
    case 404:
      return const PlaybackFailureExplanation(
        why: 'Cette chaîne n\'existe plus chez le fournisseur (HTTP 404).',
        advice: 'Actualise ta source pour récupérer la liste à jour.',
      );
    case 429:
      return const PlaybackFailureExplanation(
        why: 'Le fournisseur trouve qu\'on demande trop vite (HTTP 429).',
        advice: 'Attends une minute puis réessaie.',
      );
    default:
      if (status != null && status >= 500) {
        return PlaybackFailureExplanation(
          why: 'Le serveur du fournisseur est en panne (HTTP $status).',
          advice: 'Ce n\'est ni la box ni l\'app : réessaie plus tard ou '
              'préviens le fournisseur.',
        );
      }
      if (status != null) {
        return PlaybackFailureExplanation(
          why: 'Le serveur a refusé le flux (HTTP $status).',
          advice: 'Donne ce code au support ou au fournisseur.',
        );
      }
      return const PlaybackFailureExplanation(
        why: 'Le serveur a refusé le flux (code HTTP non transmis).',
        advice: 'Relance le diagnostic (il affichera le code HTTP exact).',
      );
  }
}

/// Repli quand seul le code NUMÉRIQUE est disponible : on reconstruit le nom
/// Media3 pour les codes connus, sinon on renvoie une chaîne vide (l'appelant
/// tombera sur le verdict générique). Les PLAGES (2000-2999 = IO, etc.) sont
/// contractuelles chez Media3 — stable sur dix ans.
String _nameFromNumericCode(int? code) {
  switch (code) {
    case 1000:
      return 'ERROR_CODE_UNSPECIFIED';
    case 1001:
      return 'ERROR_CODE_REMOTE_ERROR';
    case 1002:
      return 'ERROR_CODE_BEHIND_LIVE_WINDOW';
    case 1003:
      return 'ERROR_CODE_TIMEOUT';
    case 1004:
      return 'ERROR_CODE_FAILED_RUNTIME_CHECK';
    case 2000:
      return 'ERROR_CODE_IO_UNSPECIFIED';
    case 2001:
      return 'ERROR_CODE_IO_NETWORK_CONNECTION_FAILED';
    case 2002:
      return 'ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT';
    case 2003:
      return 'ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE';
    case 2004:
      return 'ERROR_CODE_IO_BAD_HTTP_STATUS';
    case 2005:
      return 'ERROR_CODE_IO_FILE_NOT_FOUND';
    case 2006:
      return 'ERROR_CODE_IO_NO_PERMISSION';
    case 2007:
      return 'ERROR_CODE_IO_CLEARTEXT_NOT_PERMITTED';
    case 2008:
      return 'ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE';
    case 3001:
      return 'ERROR_CODE_PARSING_CONTAINER_MALFORMED';
    case 3002:
      return 'ERROR_CODE_PARSING_MANIFEST_MALFORMED';
    case 3003:
      return 'ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED';
    case 3004:
      return 'ERROR_CODE_PARSING_MANIFEST_UNSUPPORTED';
    case 4001:
      return 'ERROR_CODE_DECODER_INIT_FAILED';
    case 4002:
      return 'ERROR_CODE_DECODER_QUERY_FAILED';
    case 4003:
      return 'ERROR_CODE_DECODING_FAILED';
    case 4004:
      return 'ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES';
    case 4005:
      return 'ERROR_CODE_DECODING_FORMAT_UNSUPPORTED';
    case 5001:
      return 'ERROR_CODE_AUDIO_TRACK_INIT_FAILED';
    case 5002:
      return 'ERROR_CODE_AUDIO_TRACK_WRITE_FAILED';
    default:
      if (code == null) return '';
      // Plages contractuelles Media3 : un code futur reste classable.
      if (code >= 6000 && code < 7000) return 'ERROR_CODE_DRM_UNKNOWN_$code';
      if (code >= 5000 && code < 6000) return 'ERROR_CODE_AUDIO_UNKNOWN_$code';
      if (code >= 4000 && code < 5000) {
        return 'ERROR_CODE_DECODING_UNKNOWN_$code';
      }
      if (code >= 3000 && code < 4000) {
        return 'ERROR_CODE_PARSING_UNKNOWN_$code';
      }
      if (code >= 2000 && code < 3000) return 'ERROR_CODE_IO_UNKNOWN_$code';
      return '';
  }
}

/// « Code support » court (6 caractères, base 36) que le client peut LIRE AU
/// TÉLÉPHONE au revendeur : condense le dernier échec (code d'erreur) et le
/// build de l'app. Déterministe (même échec + même build = même code) →
/// le support peut le recouper. FONCTION PURE (hash FNV-1a, aucune dépendance).
String supportCode({
  String? errorCodeName,
  int? errorCode,
  required String build,
}) {
  final String seed = '${errorCodeName ?? ''}|${errorCode ?? ''}|$build';
  // FNV-1a 32 bits — simple, stable, suffisant pour un code de lecture orale.
  int hash = 0x811C9DC5;
  for (final int unit in seed.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(36).toUpperCase().padLeft(6, '0').substring(0, 6);
}

/// ABONNEMENT — la cause n°1 des « plus rien ne marche » (terrain
/// 2026-08-01 : compte expiré depuis 17 jours → le panel répondait
/// HTTP 404 sur CHAQUE chaîne, et le client cherchait le bug dans l'app).
///
/// Renvoie une phrase française à afficher TELLE QUELLE quand l'abonnement
/// lui-même est en cause, ou `null` si le compte est sain (l'échec vient
/// alors d'ailleurs : réseau, chaîne précise, codec…).
///
/// FONCTION PURE : [now] est injecté, aucun accès horloge/réseau → testable.
String? explainSubscriptionIssue({
  String? status,
  DateTime? expDate,
  required DateTime now,
}) {
  if (expDate != null && expDate.isBefore(now)) {
    final String d = '${expDate.day.toString().padLeft(2, '0')}/'
        '${expDate.month.toString().padLeft(2, '0')}/${expDate.year}';
    return 'Ton abonnement a expiré le $d — renouvelle-le chez ton '
        'fournisseur, les chaînes reviendront seules.';
  }
  final String s = (status ?? '').trim().toLowerCase();
  if (s.isEmpty || s == 'active') return null;
  if (s == 'expired') {
    return 'Ton abonnement est expiré — renouvelle-le chez ton fournisseur, '
        'les chaînes reviendront seules.';
  }
  if (s == 'banned' || s == 'disabled') {
    return 'Ton compte a été désactivé par le fournisseur — contacte-le.';
  }
  return 'Ton abonnement n\'est pas actif (état : $status) — contacte ton '
      'fournisseur.';
}
