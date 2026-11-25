/// Choix stable et borné : dix pays, sans doublon, dans l'ordre de l'usager.
/// La politique ne dépend pas de Flutter et ne réordonne jamais une playlist.
abstract final class VipCountries {
  static const int limit = 10;

  static List<String> normalize(Iterable<String> codes) {
    final result = <String>[];
    for (final raw in codes) {
      final code = raw.trim().toLowerCase();
      if (!RegExp(r'^[a-z]{2}$').hasMatch(code) || result.contains(code))
        continue;
      result.add(code);
      if (result.length == limit) break;
    }
    return List<String>.unmodifiable(result);
  }

  /// Déplacement explicite, jamais de réorganisation suivant l'audience.
  static List<String> move(List<String> codes, int from, int to) {
    final result = normalize(codes).toList();
    if (from < 0 || from >= result.length || to < 0 || to >= result.length) {
      return result;
    }
    result.insert(to, result.removeAt(from));
    return List<String>.unmodifiable(result);
  }
}
