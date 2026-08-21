// =========================================================
//  remote_text_translator.dart — traduction des textes REVENDEUR
// =========================================================
//  L'app est traduite en 8 langues, mais certains textes sont écrits À LA
//  MAIN par le revendeur dans SA langue : les messages temps réel du panel
//  (bandeau AdminMessageBanner) arrivaient tels quels chez un client
//  arabophone ou suédois. Demande du 21/08 : « même les petites annonces,
//  ça se traduit automatiquement ».
//
//  Le gros du travail vit côté Worker (GET /api/translate : Mistral +
//  cache définitif par empreinte de texte — un même message n'est traduit
//  qu'une fois par langue pour tout le parc). Ici : un appel best-effort
//  avec un petit cache mémoire de session. Toute erreur → null, et
//  l'appelant garde le texte original — une traduction est un bonus,
//  jamais bloquante.
// =========================================================
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../features/subscription/data/subscription_backend.dart';
import 'l10n_now.dart';

class RemoteTextTranslator {
  RemoteTextTranslator._();

  /// Cache mémoire de session : « lang|texte original » → traduction.
  /// Les bandeaux sont courts et peu nombreux — pas besoin de persistance,
  /// le Worker a déjà son cache définitif.
  static final Map<String, String> _cache = <String, String>{};

  /// Traduit [text] dans la langue COURANTE de l'app (celle de l'appareil,
  /// ou le choix explicite des Réglages). Renvoie `null` si rien de mieux
  /// que l'original n'est disponible (erreur réseau, texte déjà dans la
  /// bonne langue, service muet) — l'appelant garde alors l'original.
  static Future<String?> translate(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    try {
      final String lang = l10nNow.localeName.split('_').first;
      final String key = '$lang|$trimmed';
      final String? hit = _cache[key];
      if (hit != null) return hit == trimmed ? null : hit;
      final http.Response r = await http
          .get(Uri.parse('$kSubscriptionBaseUrl/api/translate'
              '?lang=$lang&text=${Uri.encodeQueryComponent(trimmed)}'))
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return null;
      final Object? decoded = jsonDecode(r.body);
      if (decoded is! Map<String, dynamic>) return null;
      final String out = (decoded['text'] ?? '').toString().trim();
      if (out.isEmpty) return null;
      _cache[key] = out;
      return out == trimmed ? null : out;
    } catch (e) {
      if (kDebugMode) debugPrint('[Translate] $e');
      return null;
    }
  }
}
