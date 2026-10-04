// =========================================================
//  epg_targets_test.dart — appariement XMLTV → chaînes de l'app
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/epg/data/epg_targets.dart';

void main() {
  test('M3U : sans table, le programme va à la chaîne du même identifiant', () {
    expect(expandEpgTargets('TF1.fr', null), <String>['TF1.fr']);
  });

  test('Xtream : un epg_channel_id partagé par deux chaînes nourrit les deux', () {
    final Map<String, List<String>> map = buildEpgIdMap(<String, String>{
      'xtream-10': 'TF1.fr',
      'xtream-11': 'tf1.fr ', // autre casse, espace : même chaîne XMLTV
      'xtream-12': 'France2.fr',
      'xtream-13': '', // le serveur n'a rien donné : ignorée
    });
    expect(map.keys, containsAll(<String>['tf1.fr', 'france2.fr']));
    expect(map.containsKey(''), isFalse);
    expect(expandEpgTargets(normalizeEpgId('TF1.FR'), map),
        <String>['xtream-10', 'xtream-11']);
    expect(expandEpgTargets('france2.fr', map), <String>['xtream-12']);
    // Un identifiant XMLTV inconnu du serveur : rien à insérer.
    expect(expandEpgTargets('m6.fr', map), isEmpty);
  });
}
