// =========================================================
//  profile_source_switches_test.dart — Les listes de chaque profil
// =========================================================
//  Règle : le profil 1 garde la colonne `hidden` de la base (rien ne
//  change pour lui). Les autres profils ont un carnet des listes
//  éteintes. Carnet vide ou abîmé = tout est allumé.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/playlists/data/profile_source_switches.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('carnet vide ou abîmé : rien n\'est éteint', () {
    expect(ProfileSourceSwitches.decode(null), isEmpty);
    expect(ProfileSourceSwitches.decode(''), isEmpty);
    expect(ProfileSourceSwitches.decode('pas du json'), isEmpty);
    expect(ProfileSourceSwitches.decode('{"a":1}'), isEmpty);
    expect(ProfileSourceSwitches.decode('[3,"x",-2,0,7]'), <int>{3, 7});
  });

  test('le filtre SQL ne contient que des entiers triés', () {
    expect(ProfileSourceSwitches.sqlFilter(<int>{}), '');
    expect(ProfileSourceSwitches.sqlFilter(<int>{9, 2, -1}),
        ' AND playlist_id NOT IN (2,9)');
  });

  test('le profil 1 n\'a pas de carnet : la base décide', () async {
    await ProfileSourceSwitches.write('p1', 4, off: true);
    expect(await ProfileSourceSwitches.read('p1'), isNull);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });

  test('chaque profil a ses propres interrupteurs', () async {
    await ProfileSourceSwitches.write('p2', 4, off: true);
    await ProfileSourceSwitches.write('p3', 5, off: true);
    expect(await ProfileSourceSwitches.read('p2'), <int>{4});
    expect(await ProfileSourceSwitches.read('p3'), <int>{5});
    await ProfileSourceSwitches.write('p2', 4, off: false);
    expect(await ProfileSourceSwitches.read('p2'), isEmpty);
    expect(await ProfileSourceSwitches.read('p3'), <int>{5});
  });

  test('ordre du panel et liste supprimée : tous les carnets suivent',
      () async {
    await ProfileSourceSwitches.write('p2', 4, off: true);
    await ProfileSourceSwitches.write('p3', 5, off: true);
    await ProfileSourceSwitches.writeAll(8, off: true);
    expect(await ProfileSourceSwitches.read('p2'), <int>{4, 8});
    expect(await ProfileSourceSwitches.read('p3'), <int>{5, 8});
    await ProfileSourceSwitches.writeAll(8, off: false);
    await ProfileSourceSwitches.writeAll(4, off: false);
    expect(await ProfileSourceSwitches.read('p2'), isEmpty);
    expect(await ProfileSourceSwitches.read('p3'), <int>{5});
  });

  test('profil supprimé : son carnet est effacé', () async {
    await ProfileSourceSwitches.write('p2', 4, off: true);
    await ProfileSourceSwitches.drop('p2');
    expect(await ProfileSourceSwitches.read('p2'), isEmpty);
  });
}
