// =========================================================
//  black_box_line_test.dart — journal local : expurgé, fsync regroupé
// =========================================================
//  Audit octobre 2026. Avant : une exception Xtream recopiait l'adresse
//  `player_api.php?username=…&password=…` telle quelle dans le journal
//  sur la box, et chaque ligne faisait un fsync sur le fil UI.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/blackbox/black_box_line.dart';

void main() {
  final DateTime at = DateTime(2026, 10, 4, 13, 7, 9);

  test('le format de ligne est inchangé (date, niveau, étiquette)', () {
    expect(
      formatBlackBoxLine(at, BbLevel.warn, 'PLAYER', 'reconnexion', redact: true),
      '04/10 13:07:09 W [PLAYER] reconnexion\n',
    );
    expect(
      formatBlackBoxLine(at, BbLevel.fatal, 'EXIT', 'a\nb', redact: true),
      '04/10 13:07:09 F [EXIT] a b\n',
    );
  });

  test('une adresse Xtream avec identifiants ne reste pas dans le journal', () {
    final String line = formatBlackBoxLine(
      at,
      BbLevel.error,
      'IMPORT',
      'catégorie ignorée : ClientException uri=http://srv.example:8080/'
          'player_api.php?username=paul&password=secret123&action=get_live_streams',
      redact: true,
    );
    expect(line, isNot(contains('secret123')));
    expect(line, isNot(contains('username=paul')));
    expect(line, isNot(contains('srv.example')));
    expect(line, contains('[lien]'));
  });

  test('un chemin /live/compte/mot/ sans schéma est aussi masqué', () {
    final String line = formatBlackBoxLine(
      at,
      BbLevel.info,
      'PLAYER',
      'secours du direct : /live/paul/secret123/42.ts',
      redact: true,
    );
    expect(line, isNot(contains('secret123')));
    expect(line, contains('[masqué]'));
  });

  test('les lignes techniques [SON] passent mot pour mot', () {
    const String son =
        'Entrée : AAC-LC 48 kHz 2 voies · décodeur ffmpegLavc60.3.100-aac · '
        'sortie PCM 16 bits 48 kHz · passthrough : non · AudioTrack vivants 1';
    expect(
      formatBlackBoxLine(at, BbLevel.info, 'SON', son, redact: true),
      '04/10 13:07:09 I [SON] $son\n',
    );
  });

  test('le repli « brut » rétablit l\'ancien texte', () {
    const String msg = 'uri=http://srv.example/get.php?username=a&password=b';
    expect(
      formatBlackBoxLine(at, BbLevel.info, 'X', msg, redact: false),
      contains(msg),
    );
  });

  test('fsync immédiat seulement pour avertissement, erreur, fatal', () {
    expect(blackBoxFlushNow(BbLevel.info, fsyncAll: false), isFalse);
    expect(blackBoxFlushNow(BbLevel.warn, fsyncAll: false), isTrue);
    expect(blackBoxFlushNow(BbLevel.error, fsyncAll: false), isTrue);
    expect(blackBoxFlushNow(BbLevel.fatal, fsyncAll: false), isTrue);
    // Repli : l'ancien comportement, un fsync par ligne.
    expect(blackBoxFlushNow(BbLevel.info, fsyncAll: true), isTrue);
  });
}
