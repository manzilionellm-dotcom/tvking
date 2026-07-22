// =========================================================
//  source_preflight.dart — Tester la source AVANT de l'ajouter
// =========================================================
//  « Tester et ajouter » : plutôt que d'insérer une source en base et
//  d'échouer 30 s plus tard avec un message technique, on fait un
//  PRÉ-VOL rapide et annulable :
//
//    • M3U : on télécharge SEULEMENT LE DÉBUT du fichier (Range +
//      lecture plafonnée à quelques Ko — anti-OOM, une playlist peut
//      peser des dizaines de Mo) et on vérifie que ça ressemble à une
//      vraie liste (#EXTM3U / #EXTINF).
//    • Xtream : XtreamClient.verifyCredentials (déjà existant) — appelé
//      par l'écran avec un client annulable.
//
//  Et surtout : humanize() traduit TOUTE erreur technique en français
//  SIMPLE et ACTIONNABLE. Jamais de « 404 », « timeout » ou
//  « SocketException » à l'écran — le client doit savoir QUOI vérifier.
// =========================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'iptv_http.dart';
import 'playlist_import_limits.dart';
import 'source_link_utils.dart';
import 'xtream_client.dart';

/// Erreur de pré-vol DÉJÀ formulée pour un humain : son [message] peut
/// s'afficher tel quel (humanize la laisse passer sans la traduire).
class SourcePreflightException implements Exception {
  SourcePreflightException(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract final class SourcePreflight {
  /// On ne lit que les premiers Ko : LARGEMENT assez pour trouver
  /// `#EXTM3U`/`#EXTINF`, et borné en mémoire quel que soit le serveur
  /// (beaucoup ignorent l'en-tête Range et renvoient tout le fichier —
  /// on coupe alors le flux nous-mêmes).
  static const int maxProbeBytes = 64 * 1024;

  static const Duration _timeout = Duration(seconds: 20);

  /// Vérifie qu'une URL M3U répond ET ressemble à une liste de chaînes.
  /// Ne télécharge JAMAIS le fichier entier (cf. [maxProbeBytes]).
  ///
  /// [httpClient] : passe un client que tu gardes sous la main pour
  /// pouvoir ANNULER le test (client.close() → l'attente s'interrompt).
  /// Lève une [SourcePreflightException] (message humain) si KO.
  static Future<void> probeM3u(String url, {http.Client? httpClient}) async {
    final String cleaned = SourceLinkUtils.ensureScheme(url);
    final Uri? uri = Uri.tryParse(cleaned);
    if (uri == null || uri.host.isEmpty) {
      throw SourcePreflightException(
          'Cette adresse ne ressemble pas à un lien — vérifie les points '
          'et les deux-points.');
    }
    // VALIDATION D'ENTRÉE (anti-injection) : une source de playlist doit être
    // http(s). On refuse tout autre schéma (file://, gopher://…) AVANT de
    // fetcher — sinon un lien hostile pourrait faire lire un fichier local ou
    // sonder un service interne (cf. SourceLinkUtils.isAllowedSourceUrl).
    if (!SourceLinkUtils.isAllowedSourceUrl(cleaned)) {
      throw SourcePreflightException(
          'Seuls les liens http:// ou https:// sont acceptés pour une source.');
    }
    final http.Client client = httpClient ?? createIptvHttpClient();
    final bool owns = httpClient == null;
    try {
      final http.Request req = http.Request('GET', uri)
        // Poliment : on ne demande que le début. Beaucoup de serveurs IPTV
        // ignorent Range → la lecture plafonnée ci-dessous fait le reste.
        ..headers['Range'] = 'bytes=0-${maxProbeBytes - 1}'
        // Signature VLC : la plus universellement acceptée par les panels
        // (certains rejettent les User-Agent inconnus, cf. M3uFetcher).
        ..headers['User-Agent'] = 'VLC/3.0.20 LibVLC/3.0.20';

      final http.StreamedResponse resp =
          await client.send(req).timeout(_timeout);

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        throw SourcePreflightException(
            'Le serveur a refusé l\'accès à ce lien — vérifie le nom '
            'd\'utilisateur et le mot de passe contenus dans l\'adresse.');
      }
      if (resp.statusCode >= 400) {
        throw SourcePreflightException(
            'Le serveur répond, mais cette adresse exacte n\'existe pas — '
            'vérifie la fin du lien (le nom du fichier).');
      }

      // Lecture PLAFONNÉE : on sort de la boucle dès le plafond atteint
      // (l'abonnement au flux est alors annulé → rien de plus ne descend).
      final BytesBuilder head = BytesBuilder(copy: false);
      Future<void> read() async {
        await for (final List<int> chunk in resp.stream) {
          head.add(chunk);
          if (head.length >= maxProbeBytes) break;
        }
      }

      await read().timeout(_timeout);

      final String text = utf8.decode(
        head.takeBytes().take(maxProbeBytes).toList(growable: false),
        allowMalformed: true,
      );
      if (!text.contains('#EXTM3U') && !text.contains('#EXTINF')) {
        throw SourcePreflightException(
            'Ce lien répond, mais ce n\'est pas une liste de chaînes — '
            'vérifie que c\'est bien le lien M3U donné par ton fournisseur.');
      }
    } finally {
      if (owns) client.close();
    }
  }

  /// Traduit n'importe quelle erreur (réseau, Xtream, parsing…) en une
  /// phrase FRANÇAISE simple et actionnable. Aucune sortie ne contient de
  /// jargon (« 404 », « timeout », « SocketException »).
  static String humanize(Object error) {
    // Déjà formulée pour un humain : on la laisse passer telle quelle.
    if (error is SourcePreflightException) return error.message;

    if (error is PlaylistImportTooLarge) {
      return 'Cette liste est trop volumineuse pour cet appareil — '
          'demande à ton fournisseur une liste filtrée.';
    }

    if (error is XtreamException) {
      final String m = error.message.toLowerCase();
      if (m.contains('identifiants') || m.contains('refus')) {
        return 'Le serveur n\'a pas reconnu ce nom d\'utilisateur ou ce '
            'mot de passe. Vérifie-les lettre par lettre (majuscules '
            'comprises).';
      }
      if (m.contains('non-actif') || m.contains('status=')) {
        return 'Ce compte existe mais il est désactivé ou expiré chez ton '
            'fournisseur — contacte-le.';
      }
      if (m.contains('non-json') || m.contains('json')) {
        return 'Cette adresse répond, mais ce n\'est pas un serveur de '
            'listes — vérifie l\'adresse du serveur (sans rien après le '
            'port, ex. http://serveur.com:8080).';
      }
      if (m.contains('injoignable')) {
        return 'Adresse introuvable — vérifie les points et les '
            'deux-points de l\'adresse, puis réessaie.';
      }
      return 'Le serveur a répondu quelque chose d\'inattendu — vérifie '
          'l\'adresse et réessaie.';
    }

    if (error is TimeoutException) {
      return 'Le serveur met trop de temps à répondre. Vérifie ta '
          'connexion Internet, puis réessaie.';
    }

    if (error is HandshakeException || error is TlsException) {
      return 'La connexion sécurisée a échoué — essaie la même adresse en '
          'http:// au lieu de https://.';
    }

    if (error is SocketException) {
      final String m = error.message.toLowerCase();
      final String os = error.osError?.message.toLowerCase() ?? '';
      if (m.contains('lookup') || os.contains('lookup') ||
          m.contains('host') || os.contains('name or service')) {
        return 'Adresse introuvable — vérifie les points et les '
            'deux-points de l\'adresse (ex. serveur.com:8080).';
      }
      if (m.contains('refused') || os.contains('refused')) {
        return 'Le serveur existe mais n\'a pas ouvert la porte — vérifie '
            'le numéro juste après les deux-points (ex. :8080).';
      }
      return 'Connexion impossible. Vérifie ta connexion Internet et '
          'l\'adresse, puis réessaie.';
    }

    if (error is FormatException) {
      return 'Cette adresse ne ressemble pas à un lien valide — vérifie '
          'les points et les deux-points.';
    }

    // http.ClientException « Connection closed » = souvent notre propre
    // annulation (client.close()) ou une coupure réseau franche.
    if (error is http.ClientException) {
      return 'La connexion s\'est interrompue. Vérifie ta connexion '
          'Internet, puis réessaie.';
    }

    // Filet final : certains messages techniques remontent en Exception
    // générique (ex. M3uFetcher). On reste humain quoi qu'il arrive.
    final String m = error.toString().toLowerCase();
    if (m.contains('lookup') || m.contains('unreachable')) {
      return 'Adresse introuvable — vérifie les points et les deux-points '
          'de l\'adresse, puis réessaie.';
    }
    if (m.contains('aucune chaîne')) {
      return 'Ce lien répond, mais aucune chaîne n\'a été trouvée dedans — '
          'vérifie que c\'est bien le lien donné par ton fournisseur.';
    }
    return 'Connexion impossible. Vérifie l\'adresse et réessaie.';
  }
}
