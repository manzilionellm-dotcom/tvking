// =========================================================
//  track_memory.dart — Mémoire des pistes audio/sous-titres PAR CHAÎNE
// =========================================================
//  Le choix d'une piste (VF, VO, sous-titres…) était PERDU au zap : le
//  natif repart sur ses pistes par défaut à chaque ouverture. Ici, on
//  mémorise le choix de l'utilisateur PAR chaîne et on le réapplique
//  automatiquement dès que les pistes du flux sont connues.
//
//  Clé de correspondance : la LANGUE d'abord (stable d'un jour à
//  l'autre même si l'ordre des pistes change), repli sur l'INDEX si la
//  piste n'a pas de langue déclarée (fréquent en IPTV).
//
//  Stockage : SharedPreferences, une map JSON bornée (300 chaînes max,
//  éviction des plus anciennes) — quelques Ko, zéro I/O en lecture
//  après le premier load. Logique de matching PURE → testée
//  unitairement. Aucune dépendance au cast.
// =========================================================

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Choix mémorisé pour une chaîne. `audio`/`sub` valent :
///   - une langue (ex. 'fr', 'eng') si la piste en déclarait une ;
///   - 'idx:N' sinon (repli positionnel) ;
///   - pour `sub` uniquement : 'off' = sous-titres coupés explicitement.
class TrackChoice {
  const TrackChoice({this.audio, this.sub});

  final String? audio;
  final String? sub;

  Map<String, String> toJson() => <String, String>{
        if (audio != null) 'a': audio!,
        if (sub != null) 's': sub!,
      };

  static TrackChoice? fromJson(Object? j) {
    if (j is! Map) return null;
    final String? a = j['a'] as String?;
    final String? s = j['s'] as String?;
    if (a == null && s == null) return null;
    return TrackChoice(audio: a, sub: s);
  }
}

class TrackMemory {
  TrackMemory._();
  static final TrackMemory instance = TrackMemory._();

  static const String _kKey = 'tv.track_memory.v1';
  static const int _kMax = 300;

  final Map<String, TrackChoice> _mem = <String, TrackChoice>{};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_kKey);
      if (raw == null) return;
      final Object? parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic>) return;
      parsed.forEach((String id, Object? v) {
        final TrackChoice? c = TrackChoice.fromJson(v);
        if (c != null) _mem[id] = c;
      });
    } catch (_) {
      // best-effort : une mémoire illisible = pas de mémoire.
    }
  }

  TrackChoice? recall(String channelId) => _mem[channelId];

  /// Encode le choix d'une piste : langue si déclarée, sinon index.
  static String encodeChoice(int index, String language) =>
      language.trim().isNotEmpty ? language.trim().toLowerCase() : 'idx:$index';

  /// Retrouve l'index à réappliquer dans [languages] (liste des langues
  /// des pistes courantes, '' si inconnue) pour un choix mémorisé.
  /// null = introuvable (flux différent aujourd'hui → on ne force rien).
  /// Pur → testé unitairement.
  static int? matchIndex(String choice, List<String> languages) {
    if (choice.startsWith('idx:')) {
      final int? i = int.tryParse(choice.substring(4));
      return (i != null && i >= 0 && i < languages.length) ? i : null;
    }
    for (int i = 0; i < languages.length; i++) {
      if (languages[i].trim().toLowerCase() == choice) return i;
    }
    return null;
  }

  Future<void> saveAudio(String channelId, int index, String language) =>
      _merge(channelId, audio: encodeChoice(index, language));

  Future<void> saveSub(String channelId, int index, String language) =>
      _merge(channelId, sub: encodeChoice(index, language));

  Future<void> saveSubOff(String channelId) => _merge(channelId, sub: 'off');

  Future<void> _merge(String channelId, {String? audio, String? sub}) async {
    final TrackChoice prev = _mem[channelId] ?? const TrackChoice();
    _mem.remove(channelId); // ré-insertion en fin = « plus récent »
    _mem[channelId] =
        TrackChoice(audio: audio ?? prev.audio, sub: sub ?? prev.sub);
    while (_mem.length > _kMax) {
      _mem.remove(_mem.keys.first); // éviction du plus ancien
    }
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kKey,
          jsonEncode(_mem.map((String k, TrackChoice v) =>
              MapEntry<String, Object>(k, v.toJson()))));
    } catch (_) {
      // best-effort
    }
  }
}
