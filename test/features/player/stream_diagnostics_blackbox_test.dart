// =========================================================
//  stream_diagnostics_blackbox_test.dart — Les échecs de
//  lecture doivent finir dans la boîte noire
// =========================================================
//  Terrain 2026-08-03. Le client signale un écran noir en mode démo,
//  envoie sa boîte noire deux fois de suite… et elle ne contient RIEN
//  sur la lecture : ni codec, ni erreur, ni playlist. Les traces du
//  lecteur vivaient uniquement dans l'écran « Diagnostic flux », qu'il
//  faut penser à ouvrir AU BON MOMENT, sur le bon appareil, avant de
//  quitter la chaîne. Autant dire jamais.
//
//  Résultat : deux allers-retours de diagnostic à l'aveugle, et une
//  correction déduite au lieu d'être constatée.
//
//  Ces tests protègent le pont. Ils vérifient les trois décisions qui
//  le rendent utile plutôt que bruyant :
//    1. les échecs (warn/error) passent — sinon on est revenu au
//       silence de départ ;
//    2. le bavardage (info) NE passe pas — une boîte noire noyée sous
//       le debug est aussi inutile qu'une boîte noire vide ;
//    3. les codecs passent quand même, en clair — c'est LE
//       renseignement qui manquait pour trancher « des octets
//       arrivent, pas d'image » ;
//    4. le mot de passe du client ne fuite pas. La boîte noire est
//       faite pour être ENVOYÉE : une URL Xtream y porterait les
//       identifiants en clair.
// =========================================================
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/observability/structured_logger.dart';
import 'package:tv_king/features/player/data/stream_diagnostics.dart';

void main() {
  late List<Map<String, Object?>> captured;

  setUp(() {
    captured = <Map<String, Object?>>[];
    StructuredLogger.instance.clearSinks();
    StructuredLogger.instance.addSink((String line) {
      captured.add(jsonDecode(line) as Map<String, Object?>);
    });
    StreamDiagnostics.instance.beginSession(
      url: 'http://exemple.test/flux.m3u8',
      userAgent: 'test',
    );
    captured.clear(); // on ne teste pas la ligne d'ouverture
  });

  tearDown(StructuredLogger.instance.clearSinks);

  Iterable<Map<String, Object?>> lecture() =>
      captured.where((Map<String, Object?> l) => l['domain'] == 'lecture');

  test('une erreur de lecture atterrit dans la boîte noire', () {
    StreamDiagnostics.instance.recordPlayerError('Failed to recognize format');

    final Iterable<Map<String, Object?>> lines = lecture();
    expect(lines, isNotEmpty,
        reason: 'sans ça, un écran noir ne laisse aucune trace exploitable');
    expect(lines.first['lvl'], 'error');
    expect(lines.first['event'], 'stream.player');
    expect(
      (lines.first['ctx']! as Map<String, Object?>)['msg'],
      contains('Failed to recognize format'),
    );
  });

  test('un avertissement passe aussi', () {
    StreamDiagnostics.instance
        .recordEvent('hls', 'Playlist sans #EXTM3U', level: 'warn');

    final Iterable<Map<String, Object?>> lines = lecture();
    expect(lines.length, 1);
    expect(lines.first['lvl'], 'warn');
    expect(lines.first['event'], 'stream.hls');
  });

  test('le bavardage « info » ne passe PAS', () {
    // Le lecteur trace énormément en info (relais, sonde, redirections).
    // Tout déverser noierait les vraies pièces à conviction.
    StreamDiagnostics.instance.recordEvent('hls', 'HLS détecté → mpv direct');
    StreamDiagnostics.instance.recordEvent('relais', 'session ouverte');

    expect(
      lecture().where((Map<String, Object?> l) => l['event'] != 'codecs'),
      isEmpty,
      reason: 'une boîte noire noyée sous le debug est aussi inutile '
          'qu\'une boîte noire vide',
    );
  });

  test('les codecs passent, eux, même quand tout va bien', () {
    // C'est la ligne qui manquait : un flux qui se télécharge mais dont
    // aucun codec n'est négocié dit tout de suite que le décodeur n'a
    // rien accepté — le cas « des octets arrivent, pas d'image ».
    StreamDiagnostics.instance
        .recordCodecs(video: 'hevc', audio: 'aac', resolution: '1920x1080');

    final Map<String, Object?> codecs =
        lecture().firstWhere((Map<String, Object?> l) => l['event'] == 'codecs');
    final Map<String, Object?> ctx = codecs['ctx']! as Map<String, Object?>;
    expect(ctx['video'], 'hevc');
    expect(ctx['audio'], 'aac');
    expect(ctx['res'], '1920x1080');
  });

  test('un échec emporte le codec avec lui', () {
    // Une erreur SEULE ne dit pas grand-chose ; une erreur accompagnée
    // du codec réellement négocié tranche le diagnostic d'un coup.
    StreamDiagnostics.instance.recordCodecs(video: 'hevc');
    StreamDiagnostics.instance.recordPlayerError('0 frame décodée');

    final Map<String, Object?> err = lecture()
        .lastWhere((Map<String, Object?> l) => l['lvl'] == 'error');
    expect((err['ctx']! as Map<String, Object?>)['video'], 'hevc');
  });

  test('l\'URL est masquée : la boîte noire part chez le support', () {
    StreamDiagnostics.instance.beginSession(
      url: 'http://panel.example.com/live/jean/motdepasse123/42.ts',
      userAgent: 'test',
      title: 'Chaîne',
    );
    StreamDiagnostics.instance.recordPlayerError('timeout');

    final String tout = jsonEncode(captured);
    expect(tout.contains('motdepasse123'), isFalse,
        reason: 'un rapport envoyé au support ne doit jamais porter '
            'le mot de passe de l\'abonné');
  });
}
