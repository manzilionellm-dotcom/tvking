// =========================================================
//  playback_failure_log_test.dart — Le journal durable est un CONTRAT
// =========================================================
//  Verrouille le contrat « dix ans » du journal des échecs de lecture :
//    • schéma v1 écrit tel quel (clé "v" présente) ;
//    • lecture TOLÉRANTE : champ inconnu ignoré, champ manquant → défaut,
//      entrée illisible → sautée SANS crash ;
//    • borné à 50 entrées (éviction des plus anciennes) ;
//    • vie privée : on stocke un HÔTE, jamais une URL complète (vérifié par
//      le champ, pas par une règle magique — le lecteur passe déjà l'hôte).
//  SharedPreferences mockées, comme les tests existants (boot_guard_test).
// =========================================================
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/tv/data/playback_failure_log.dart';

PlaybackFailureEntry entry({
  String channel = 'beIN Sports 1',
  String host = 'iptv.example.com',
  String? codeName = 'ERROR_CODE_IO_BAD_HTTP_STATUS',
  int? code = 2004,
  String verdict = 'Ton fournisseur limite le nombre d\'écrans.',
  DateTime? ts,
}) =>
    PlaybackFailureEntry(
      timestamp: ts ?? DateTime(2026, 7, 10, 21, 30),
      channelName: channel,
      streamHost: host,
      errorCodeName: codeName,
      errorCode: code,
      cause: 'Response code: 456',
      uaTriedCount: 3,
      verdict: verdict,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PlaybackFailureLog.instance.resetForTest();
  });

  group('écriture — schéma v1', () {
    test('chaque entrée écrite porte "v": 1 et les clés du contrat',
        () async {
      await PlaybackFailureLog.instance.record(entry());
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Object? decoded =
          jsonDecode(prefs.getString('playback_failure_log.v1')!);
      final Map<String, Object?> m =
          ((decoded! as List<Object?>).single! as Map<String, Object?>);
      expect(m['v'], PlaybackFailureEntry.schemaVersion);
      expect(m['channel'], 'beIN Sports 1');
      expect(m['host'], 'iptv.example.com');
      expect(m['codeName'], 'ERROR_CODE_IO_BAD_HTTP_STATUS');
      expect(m['code'], 2004);
      expect(m['uaTried'], 3);
      expect(m['verdict'], isNotEmpty);
      expect(m['ts'], isA<String>());
    });

    test('les entrées ressortent du plus récent au plus ancien', () async {
      await PlaybackFailureLog.instance
          .record(entry(channel: 'A', ts: DateTime(2026, 1, 1)));
      await PlaybackFailureLog.instance
          .record(entry(channel: 'B', ts: DateTime(2026, 1, 2)));
      final List<PlaybackFailureEntry> out =
          PlaybackFailureLog.instance.entries;
      expect(out.first.channelName, 'B');
      expect(out.last.channelName, 'A');
    });
  });

  group('lecture TOLÉRANTE (contrat dix ans)', () {
    test('champ INCONNU (écrit par une version future) → ignoré', () {
      final PlaybackFailureEntry? e = PlaybackFailureEntry.tryParse(
          <String, Object?>{
            'v': 2,
            'ts': '2036-01-01T00:00:00.000',
            'channel': 'Chaîne du futur',
            'host': 'h',
            'verdict': 'v',
            'champInventeEn2036': <String, Object?>{'nested': true},
          });
      expect(e, isNotNull);
      expect(e!.channelName, 'Chaîne du futur');
      expect(e.v, 2); // la version lue est conservée, pas écrasée
    });

    test('champ MANQUANT → valeur par défaut, jamais d\'exception', () {
      final PlaybackFailureEntry? e =
          PlaybackFailureEntry.tryParse(<String, Object?>{});
      expect(e, isNotNull);
      expect(e!.channelName, '');
      expect(e.streamHost, '');
      expect(e.errorCodeName, isNull);
      expect(e.errorCode, isNull);
      expect(e.uaTriedCount, 0);
      expect(e.verdict, '');
      expect(e.timestamp, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('mauvais TYPE de champ → défaut (pas de cast qui explose)', () {
      final PlaybackFailureEntry? e = PlaybackFailureEntry.tryParse(
          <String, Object?>{
            'ts': 12345, // devrait être une chaîne ISO
            'channel': <int>[1, 2, 3], // devrait être une chaîne
            'code': 'pas un nombre',
            'uaTried': 2.9, // num accepté, tronqué en int
          });
      expect(e, isNotNull);
      expect(e!.channelName, '');
      expect(e.errorCode, isNull);
      expect(e.uaTriedCount, 2);
    });

    test('entrée illisible (pas un objet) → null, l\'appelant la saute', () {
      expect(PlaybackFailureEntry.tryParse('du texte'), isNull);
      expect(PlaybackFailureEntry.tryParse(42), isNull);
      expect(PlaybackFailureEntry.tryParse(null), isNull);
    });

    test('prefs CORROMPUES : entrée cassée sautée, les saines survivent',
        () async {
      final String good = jsonEncode(entry(channel: 'Saine').toMap());
      SharedPreferences.setMockInitialValues(<String, Object>{
        // 1 entrée valide + 1 texte + 1 objet à types cassés
        'playback_failure_log.v1':
            '[$good, "je ne suis pas un objet", {"ts": 42}]',
      });
      PlaybackFailureLog.instance.resetForTest();
      await PlaybackFailureLog.instance.ensureLoaded();
      final List<PlaybackFailureEntry> out =
          PlaybackFailureLog.instance.entries;
      // L'entrée texte est sautée ; l'objet à types cassés reste lisible
      // (tous ses champs retombent sur les défauts) — AUCUN crash.
      expect(out.any((PlaybackFailureEntry e) => e.channelName == 'Saine'),
          isTrue);
      expect(out.length, 2);
    });

    test('prefs totalement illisibles (pas du JSON) → journal vide, pas de '
        'crash', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'playback_failure_log.v1': '{{{pas du json',
      });
      PlaybackFailureLog.instance.resetForTest();
      await PlaybackFailureLog.instance.ensureLoaded();
      expect(PlaybackFailureLog.instance.entries, isEmpty);
    });
  });

  group('borne anti-bloat (50 entrées max)', () {
    test('éviction des plus anciennes au-delà de 50', () async {
      for (int i = 0; i < 60; i++) {
        await PlaybackFailureLog.instance.record(
            entry(channel: 'C$i', ts: DateTime(2026, 1, 1).add(Duration(minutes: i))));
      }
      final List<PlaybackFailureEntry> out =
          PlaybackFailureLog.instance.entries;
      expect(out.length, PlaybackFailureLog.kMaxEntries);
      expect(out.first.channelName, 'C59'); // la plus récente
      // Les 10 plus anciennes (C0..C9) ont été évincées.
      expect(out.any((PlaybackFailureEntry e) => e.channelName == 'C9'),
          isFalse);
      expect(out.last.channelName, 'C10');
    });

    test('borne aussi appliquée en LECTURE (vieux surplus sur disque)',
        () async {
      final List<Map<String, Object?>> tooMany = <Map<String, Object?>>[
        for (int i = 0; i < 70; i++)
          entry(channel: 'D$i', ts: DateTime(2026, 1, 1).add(Duration(minutes: i)))
              .toMap(),
      ];
      SharedPreferences.setMockInitialValues(<String, Object>{
        'playback_failure_log.v1': jsonEncode(tooMany),
      });
      PlaybackFailureLog.instance.resetForTest();
      await PlaybackFailureLog.instance.ensureLoaded();
      final List<PlaybackFailureEntry> out =
          PlaybackFailureLog.instance.entries;
      expect(out.length, PlaybackFailureLog.kMaxEntries);
      expect(out.first.channelName, 'D69'); // on garde les plus récentes
    });
  });

  group('aller-retour disque', () {
    test('record → relecture depuis prefs = mêmes valeurs', () async {
      await PlaybackFailureLog.instance.record(entry());
      PlaybackFailureLog.instance.resetForTest();
      await PlaybackFailureLog.instance.ensureLoaded();
      final PlaybackFailureEntry e =
          PlaybackFailureLog.instance.entries.single;
      expect(e.channelName, 'beIN Sports 1');
      expect(e.streamHost, 'iptv.example.com');
      expect(e.errorCodeName, 'ERROR_CODE_IO_BAD_HTTP_STATUS');
      expect(e.errorCode, 2004);
      expect(e.cause, 'Response code: 456');
      expect(e.uaTriedCount, 3);
      expect(e.verdict, contains('écrans'));
      expect(e.timestamp, DateTime(2026, 7, 10, 21, 30));
    });

    test('clear() vide le journal et le disque', () async {
      await PlaybackFailureLog.instance.record(entry());
      await PlaybackFailureLog.instance.clear();
      expect(PlaybackFailureLog.instance.entries, isEmpty);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('playback_failure_log.v1'), isNull);
    });
  });
}
