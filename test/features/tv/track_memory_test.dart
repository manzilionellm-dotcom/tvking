// Tests de la mémoire des pistes PAR CHAÎNE (n°40) : encodage du choix
// (langue prioritaire, repli index), matching pur, persistance
// SharedPreferences (mock), éviction des plus anciennes entrées.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/tv/data/track_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TrackMemory.encodeChoice', () {
    test('langue déclarée → langue normalisée (minuscules, trim)', () {
      expect(TrackMemory.encodeChoice(2, 'FR '), 'fr');
      expect(TrackMemory.encodeChoice(0, 'eng'), 'eng');
    });

    test('pas de langue → repli positionnel idx:N', () {
      expect(TrackMemory.encodeChoice(3, ''), 'idx:3');
      expect(TrackMemory.encodeChoice(0, '   '), 'idx:0');
    });
  });

  group('TrackMemory.matchIndex', () {
    test('retrouve la piste par langue, insensible à la casse/ordre', () {
      expect(TrackMemory.matchIndex('fr', <String>['eng', 'FR', 'spa']), 1);
      expect(TrackMemory.matchIndex('spa', <String>['spa']), 0);
    });

    test('langue absente aujourd\'hui → null (on ne force rien)', () {
      expect(TrackMemory.matchIndex('deu', <String>['eng', 'fr']), isNull);
    });

    test('repli idx:N borné à la liste du jour', () {
      expect(TrackMemory.matchIndex('idx:1', <String>['', '', '']), 1);
      expect(TrackMemory.matchIndex('idx:5', <String>['', '']), isNull);
      expect(TrackMemory.matchIndex('idx:-1', <String>['', '']), isNull);
      expect(TrackMemory.matchIndex('idx:abc', <String>['', '']), isNull);
    });

    test('liste vide → null', () {
      expect(TrackMemory.matchIndex('fr', <String>[]), isNull);
      expect(TrackMemory.matchIndex('idx:0', <String>[]), isNull);
    });
  });

  group('TrackChoice.fromJson', () {
    test('lit a/s, tolère l\'absence de l\'un des deux', () {
      final TrackChoice? c =
          TrackChoice.fromJson(<String, Object?>{'a': 'fr', 's': 'off'});
      expect(c, isNotNull);
      expect(c!.audio, 'fr');
      expect(c.sub, 'off');
      expect(TrackChoice.fromJson(<String, Object?>{'a': 'eng'})!.audio, 'eng');
    });

    test('entrée illisible ou vide → null (jamais de crash)', () {
      expect(TrackChoice.fromJson('pas une map'), isNull);
      expect(TrackChoice.fromJson(null), isNull);
      expect(TrackChoice.fromJson(<String, Object?>{}), isNull);
    });
  });

  group('TrackMemory persistance (SharedPreferences mock)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('save puis recall : audio et sous-titres fusionnés par chaîne',
        () async {
      final TrackMemory mem = TrackMemory.instance;
      await mem.load();
      await mem.saveAudio('ch1', 1, 'fr');
      await mem.saveSubOff('ch1');
      final TrackChoice? c = mem.recall('ch1');
      expect(c, isNotNull);
      expect(c!.audio, 'fr');
      expect(c.sub, 'off');
      // saveSub écrase le 'off', l'audio reste.
      await mem.saveSub('ch1', 0, 'eng');
      expect(mem.recall('ch1')!.sub, 'eng');
      expect(mem.recall('ch1')!.audio, 'fr');
    });

    test('chaîne inconnue → null', () async {
      final TrackMemory mem = TrackMemory.instance;
      await mem.load();
      expect(mem.recall('jamais-vue'), isNull);
    });

    test('éviction : au-delà de 300 chaînes, les plus anciennes partent',
        () async {
      final TrackMemory mem = TrackMemory.instance;
      await mem.load();
      for (int i = 0; i < 305; i++) {
        await mem.saveAudio('ch$i', 0, 'fr');
      }
      // Les 5 premières ont été évincées, les dernières restent.
      expect(mem.recall('ch0'), isNull);
      expect(mem.recall('ch4'), isNull);
      expect(mem.recall('ch5'), isNotNull);
      expect(mem.recall('ch304'), isNotNull);
    });

    test('re-sauvegarder une vieille chaîne la rafraîchit (pas évincée)',
        () async {
      final TrackMemory mem = TrackMemory.instance;
      await mem.load();
      await mem.saveAudio('vip', 0, 'fr');
      for (int i = 0; i < 299; i++) {
        await mem.saveAudio('x$i', 0, 'eng');
      }
      // 'vip' est la plus ancienne ; on la re-touche → elle redevient récente.
      await mem.saveSub('vip', 1, 'fr');
      await mem.saveAudio('y1', 0, 'eng');
      await mem.saveAudio('y2', 0, 'eng');
      expect(mem.recall('vip'), isNotNull);
    });
  });
}
