import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../profiles/data/active_profile.dart';
import '../domain/vip_countries.dart';

/// Un tiroir par profil. Chaque lecture/écriture capture son propriétaire :
/// changer de profil pendant un await ne peut pas transférer ses préférences.
class VipCountriesRepository extends ChangeNotifier {
  VipCountriesRepository();
  static final instance = VipCountriesRepository();
  List<String> _current = const [];
  List<String> get current => _current;
  int _generation = 0;

  static String keyFor(String profileId) => 'zuno.vip.countries.v1.$profileId';

  Future<void> load() async {
    final generation = ++_generation;
    final id = ActiveProfile.instance.id;
    // Effacement immédiat : aucune préférence du profil précédent à l'écran.
    _current = const [];
    notifyListeners();
    List<String> codes;
    try {
      final prefs = await SharedPreferences.getInstance();
      codes = VipCountries.normalize(prefs.getStringList(keyFor(id)) ?? []);
    } catch (error) {
      debugPrint('[VIP] Lecture des pays indisponible : $error');
      codes = const [];
    }
    if (generation != _generation || id != ActiveProfile.instance.id) return;
    _current = codes;
    notifyListeners();
  }

  Future<void> save(List<String> codes, {required String profileId}) async {
    final next = VipCountries.normalize(codes);
    final prefs = await SharedPreferences.getInstance();
    // Écriture terminée avant de fermer le sélecteur ; une erreur reste visible.
    final saved = await prefs.setStringList(keyFor(profileId), next);
    if (!saved) throw StateError('Préférences non enregistrées');
    if (profileId != ActiveProfile.instance.id) return;
    ++_generation;
    _current = next;
    notifyListeners();
  }
}
