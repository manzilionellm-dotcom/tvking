// Adresses de catch-up (retour sur un programme passé). Ce fichier n'avait
// aucun test avant le 12/11/2026. Hôtes *.invalid et identifiants fictifs.
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/epg/data/catchup_url_builder.dart';
import 'package:tv_king/features/epg/domain/epg_program.dart';
import 'package:tv_king/features/playlists/data/xtream_server_clock.dart';

Channel _channel(
  String url, {
  bool declared = false,
  String? source,
}) =>
    Channel(
      id: 'c1',
      name: 'Chaîne',
      category: 'Cat',
      streamUrl: url,
      isLive: true,
      catchupSupported: declared,
      catchupSource: source,
    );

/// Programme du 10 novembre 2026, 19:00 → 20:30 UTC (90 minutes).
final int _start = DateTime.utc(2026, 11, 10, 19).millisecondsSinceEpoch;
final EpgProgram _program = EpgProgram(
  channelId: 'c1',
  startTime: _start,
  stopTime: _start + 90 * 60 * 1000,
  title: 'Le film',
);

String _two(int n) => n.toString().padLeft(2, '0');

/// Heure du programme dans le fuseau de la machine de test (ancien repli).
String _localStamp() {
  final DateTime l = DateTime.fromMillisecondsSinceEpoch(_start);
  return '${l.year}-${_two(l.month)}-${_two(l.day)}:${_two(l.hour)}-${_two(l.minute)}';
}

void main() {
  setUp(XtreamServerClock.debugReset);
  tearDown(XtreamServerClock.debugReset);

  group('Xtream', () {
    test('forme /USER/PASS/ID.ts → /timeshift/USER/PASS/MIN/DATE/ID.ts', () {
      final String? url = CatchupUrlBuilder.build(
        channel: _channel('http://tv.invalid:8080/user/pass/1234.ts', declared: true),
        program: _program,
      );
      expect(url, 'http://tv.invalid:8080/timeshift/user/pass/90/${_localStamp()}/1234.ts');
    });

    test('forme /live/USER/PASS/ID : plus de /live/timeshift (route inexistante)', () {
      final String? url = CatchupUrlBuilder.build(
        channel: _channel('https://tv.invalid/live/user/pass/1234.m3u8', declared: true),
        program: _program,
      );
      expect(url, 'https://tv.invalid/timeshift/user/pass/90/${_localStamp()}/1234.ts');
      expect(url, isNot(contains('/live/')));
    });

    test('heure écrite dans le fuseau du SERVEUR quand il est connu', () {
      XtreamServerClock.debugSetZone('http://tv.invalid:8080', 'Europe/Paris');
      // 19:00 UTC en novembre = 20:00 à Paris (hiver, UTC+1).
      expect(
        CatchupUrlBuilder.build(
          channel: _channel('http://tv.invalid:8080/user/pass/1234.ts', declared: true),
          program: _program,
        ),
        'http://tv.invalid:8080/timeshift/user/pass/90/2026-11-10:20-00/1234.ts',
      );
      // Heure d'été : 19:00 UTC le 10 juillet = 21:00 à Paris (UTC+2).
      final int summer = DateTime.utc(2026, 7, 10, 19).millisecondsSinceEpoch;
      expect(
        CatchupUrlBuilder.build(
          channel: _channel('http://tv.invalid:8080/user/pass/1234.ts', declared: true),
          program: EpgProgram(
            channelId: 'c1', startTime: summer, stopTime: summer + 3600000, title: 'Été',
          ),
        ),
        'http://tv.invalid:8080/timeshift/user/pass/60/2026-07-10:21-00/1234.ts',
      );
      // Passage de minuit : 23:30 UTC = 08:30 le lendemain à Tokyo.
      XtreamServerClock.debugSetZone('http://tv.invalid:8080', 'Asia/Tokyo');
      final int late = DateTime.utc(2026, 11, 10, 23, 30).millisecondsSinceEpoch;
      expect(
        CatchupUrlBuilder.build(
          channel: _channel('http://tv.invalid:8080/user/pass/7.ts', declared: true),
          program: EpgProgram(
            channelId: 'c1', startTime: late, stopTime: late + 1800000, title: 'Nuit',
          ),
        ),
        'http://tv.invalid:8080/timeshift/user/pass/30/2026-11-11:08-30/7.ts',
      );
    });

    test('le fuseau est retenu par serveur (hôte:port), pas pour un autre', () {
      XtreamServerClock.debugSetZone('http://autre.invalid:8080', 'Asia/Tokyo');
      expect(
        CatchupUrlBuilder.build(
          channel: _channel('http://tv.invalid:8080/user/pass/1234.ts', declared: true),
          program: _program,
        ),
        contains('/${_localStamp()}/'),
      );
    });

    test('fuseau inconnu de la base → repli sur l’heure de la box, sans erreur', () {
      XtreamServerClock.debugSetZone('http://tv.invalid:8080', 'Nulle/Part');
      expect(
        CatchupUrlBuilder.build(
          channel: _channel('http://tv.invalid:8080/user/pass/1234.ts', declared: true),
          program: _program,
        ),
        contains('/${_localStamp()}/'),
      );
    });

    test('chaîne Xtream non déclarée : tentée quand même ; adresse non Xtream : null', () {
      expect(
        CatchupUrlBuilder.build(
          channel: _channel('http://tv.invalid/user/pass/55.ts'),
          program: _program,
        ),
        startsWith('http://tv.invalid/timeshift/user/pass/90/'),
      );
      expect(
        CatchupUrlBuilder.build(
          channel: _channel('http://tv.invalid/chaines/sport/direct.m3u8'),
          program: _program,
        ),
        isNull,
      );
    });
  });

  group('fuseau annoncé par le serveur', () {
    test('server_info.timezone valide retenu, valeurs douteuses refusées', () async {
      await XtreamServerClock.remember(
          'http://tv.invalid:8080/', <String, Object?>{'timezone': 'Europe/Paris'});
      expect(XtreamServerClock.zoneOf('http://tv.invalid:8080/u/p/1.ts'), 'Europe/Paris');
      for (final Object? bad in <Object?>[
        null,
        'texte',
        <String, Object?>{},
        <String, Object?>{'timezone': ''},
        <String, Object?>{'timezone': 'Europe/Paris; rm -rf'},
        <String, Object?>{'timezone': 42},
      ]) {
        await XtreamServerClock.remember('http://refus.invalid', bad);
        expect(XtreamServerClock.zoneOf('http://refus.invalid/u/p/1.ts'), isNull,
            reason: '$bad');
      }
    });
  });

  group('gabarit catchup-source', () {
    final int s = _start ~/ 1000;
    final int e = s + 90 * 60;

    test('écritures \${…} et {…} donnent le même résultat', () {
      final String a = CatchupUrlBuilder.build(
        channel: _channel('http://tv.invalid/a.m3u8',
            declared: true,
            source: r'http://arch.invalid/a?start=${start}&end=${end}&d=${duration}'),
        program: _program,
      )!;
      final String b = CatchupUrlBuilder.build(
        channel: _channel('http://tv.invalid/a.m3u8',
            declared: true,
            source: 'http://arch.invalid/a?start={utc}&end={utcend}&d={duration}'),
        program: _program,
      )!;
      expect(a, 'http://arch.invalid/a?start=$s&end=$e&d=5400');
      expect(b, a);
    });

    test('date UTC, durée divisée et variable inconnue laissée telle quelle', () {
      final String url = CatchupUrlBuilder.build(
        channel: _channel('http://tv.invalid/a.m3u8',
            declared: true,
            source:
                'http://arch.invalid/{Y}/{m}/{d}/{H}-{M}-{S}.m3u8?min={duration:60}&t=\${start-time}&x={inconnu}'),
        program: _program,
      )!;
      expect(url,
          'http://arch.invalid/2026/11/10/19-00-00.m3u8?min=90&t=20261110T190000&x={inconnu}');
    });

    test('{lutc}, {now}, {timestamp} = maintenant ; {offset:1} = retard sur le direct', () {
      final int before = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final Uri uri = Uri.parse(CatchupUrlBuilder.build(
        channel: _channel('http://tv.invalid/a.m3u8',
            declared: true,
            source:
                'http://arch.invalid/a?l={lutc}&n=\${now}&t=\${timestamp}&o={offset:1}'),
        program: _program,
      )!);
      final int after = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      for (final String key in <String>['l', 'n', 't']) {
        final int value = int.parse(uri.queryParameters[key]!);
        expect(value, inInclusiveRange(before, after), reason: key);
      }
      expect(int.parse(uri.queryParameters['o']!),
          inInclusiveRange(before - s, after - s));
    });

    test('gabarit relatif (?utc=…) AJOUTÉ à l’adresse du flux', () {
      expect(
        CatchupUrlBuilder.build(
          channel: _channel('http://tv.invalid/direct.m3u8',
              declared: true, source: '?utc={utc}&fin={utcend}'),
          program: _program,
        ),
        'http://tv.invalid/direct.m3u8?utc=$s&fin=$e',
      );
      // Le flux a déjà des paramètres : on enchaîne avec « & ».
      expect(
        CatchupUrlBuilder.build(
          channel: _channel('http://tv.invalid/direct.m3u8?token=abc',
              declared: true, source: '?utc={utc}'),
          program: _program,
        ),
        'http://tv.invalid/direct.m3u8?token=abc&utc=$s',
      );
    });
  });

  test('M3U déclaré sans gabarit ni forme Xtream : ?utc=…&lutc=…', () {
    final String url = CatchupUrlBuilder.build(
      channel: _channel('http://tv.invalid/chaines/direct.m3u8', declared: true),
      program: _program,
    )!;
    expect(url, startsWith('http://tv.invalid/chaines/direct.m3u8?utc=${_start ~/ 1000}&lutc='));
  });
}
