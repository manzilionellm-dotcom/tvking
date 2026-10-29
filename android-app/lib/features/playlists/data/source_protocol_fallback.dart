// Compatibilité des liens collés par le client. Le protocole HTTPS reste
// prioritaire ; seul un échec de négociation qui indique explicitement un
// service HTTP autorise une tentative HTTP, sur la même adresse.
import 'dart:io';

import 'package:http/http.dart' as http;

class SourceProtocolResult<T> {
  const SourceProtocolResult(this.url, this.value);

  final String url;
  final T value;
}

/// Marque une tentative de compatibilité déjà consommée. Le chemin « get.php
/// vers Xtream puis M3U » doit la propager, sans lancer une seconde tentative.
class SourceProtocolFallbackFailure implements Exception {
  const SourceProtocolFallbackFailure(this.cause);

  final Object cause;

  @override
  String toString() =>
      'La connexion HTTP de compatibilité a échoué. Vérifie le lien fourni.';
}

abstract final class SourceProtocolFallback {
  /// Identités que l'ajout MANUEL peut rétablir, en une transaction avant
  /// le réseau. Cette liste n'autorise pas à changer de protocole sans
  /// erreur TLS, ni à lever une suppression reçue pendant le téléchargement.
  static List<String> possibleUrls(String url, {bool allowHttpCompatibility = false}) {
    final Uri? parsed = Uri.tryParse(url);
    return <String>[
      url,
      if (allowHttpCompatibility && parsed != null &&
          parsed.scheme.toLowerCase() == 'https' && parsed.host.isNotEmpty)
        'http${url.substring(5)}',
    ];
  }

  /// Une erreur de certificat, un délai dépassé, une réponse HTTP ou un
  /// contenu invalide ne prouvent jamais que le fournisseur exige HTTP.
  static bool isProtocolMismatch(Object error) {
    final String message;
    if (error is HandshakeException) {
      message = '${error.message} ${error.osError?.message ?? ''}';
    } else if (error is http.ClientException &&
        error.message.toLowerCase().contains('handshakeexception')) {
      message = error.message;
    } else {
      return false;
    }
    final String normalized = message.toUpperCase().replaceAll(' ', '_');
    return normalized.contains('WRONG_VERSION_NUMBER') &&
        !normalized.contains('CERTIFICATE');
  }

  /// [singleAttempt] est vrai uniquement pour la connexion HTTP de repli :
  /// l'appelant désactive alors sa rotation de signatures User-Agent.
  /// Les imports automatiques/panel restent exclus par défaut.
  static Future<SourceProtocolResult<T>> connect<T>({
    required String url,
    required Future<T> Function(String url, bool singleAttempt) attempt,
    bool allowHttpCompatibility = false,
  }) async {
    try {
      return SourceProtocolResult<T>(url, await attempt(url, false));
    } catch (error) {
      final Uri? parsed = Uri.tryParse(url);
      if (!allowHttpCompatibility ||
          parsed == null ||
          parsed.scheme.toLowerCase() != 'https' ||
          parsed.host.isEmpty ||
          !isProtocolMismatch(error)) {
        rethrow;
      }
      // Remplacer uniquement le préfixe conserve exactement le port écrit,
      // le chemin, l'encodage et les paramètres (dont les identifiants).
      final String httpUrl = 'http${url.substring(5)}';
      try {
        return SourceProtocolResult<T>(
          httpUrl,
          await attempt(httpUrl, true),
        );
      } catch (fallbackError) {
        throw SourceProtocolFallbackFailure(fallbackError);
      }
    }
  }
}
