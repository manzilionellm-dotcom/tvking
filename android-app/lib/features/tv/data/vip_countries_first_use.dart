import 'package:shared_preferences/shared_preferences.dart';

/// Repère distinct de l'ancien onboarding : il n'est consommé que lorsque
/// le sélecteur peut réellement être découvert, et appartient au profil.
class VipCountriesFirstUse {
  VipCountriesFirstUse();
  static final instance = VipCountriesFirstUse();
  final Set<String> _seen = <String>{};

  static String keyFor(String profileId) =>
      'zuno.vip.countries.hint.seen.v1.$profileId';

  Future<bool> hasSeen(String profileId) async {
    if (_seen.contains(profileId)) return true;
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(keyFor(profileId)) ?? false;
    if (seen) _seen.add(profileId);
    return seen;
  }

  Future<void> markSeen(String profileId) async {
    _seen.add(profileId);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(keyFor(profileId), true)) {
      throw StateError('Repère pays non mémorisé');
    }
  }
}
