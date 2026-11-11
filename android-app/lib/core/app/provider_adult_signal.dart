import '../../features/channels/domain/channel_genre.dart';

/// Indications explicites d'un fournisseur, distinctes des noms et catégories.
/// Aucune note de film (`rating`, sur 5 ou 10) n'est interprétée comme un âge.
abstract final class ProviderAdultSignal {
  static bool positive(Object? value) =>
      value == true ||
      value == 1 ||
      (value is String &&
          const <String>{'1', 'true', 'yes'}
              .contains(value.trim().toLowerCase()));

  /// Xtream utilise notamment `is_adult`. Les attributs M3U ci-dessous sont
  /// acceptés seulement lorsqu'ils déclarent positivement cette information.
  /// Un zéro ne neutralise jamais un indice adulte présent dans les textes.
  static bool read(Object? fields) {
    if (fields is! Map) return false;
    for (final String key in const <String>[
      'is_adult',
      'is-adult',
      'adult',
      'tvg-adult',
    ]) {
      if (positive(fields[key])) return true;
    }
    return false;
  }

  /// Certains exports ne marquent que le nom alternatif ou le genre de la
  /// fiche détaillée. On conserve aussi ces indices, sans remplacer le titre
  /// ni la catégorie affichés et sans examiner les URLs ou les notes.
  static bool fromMetadata(Object? fields) {
    if (read(fields)) return true;
    if (fields is! Map) return false;
    for (final String key in const <String>[
      'tvg-name',
      'name',
      'title',
      'genre',
      'category',
      'category_name',
      'group-title',
      'group',
    ]) {
      final Object? value = fields[key];
      if (value is String && ChannelClassifier.isAdult(value, '')) return true;
      if (value is List &&
          value
              .whereType<String>()
              .any((String text) => ChannelClassifier.isAdult(text, '')))
        return true;
    }
    return false;
  }
}
