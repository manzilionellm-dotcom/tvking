// =========================================================
//  player_one_connection_guards_test.dart — Gardes P0/P1 lecteur mobile
// =========================================================
//  Owner : JAMAIS redémarrer en boucle, 1 connexion, pas d'écran noir.
//  Le lecteur s'appuie sur mpv : ces tests lisent le SOURCE (même patron
//  que exit_guards_wave2_test.dart) pour empêcher le retrait d'une garde.
// =========================================================
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source sans les lignes de commentaire (elles citent les noms qu'on
/// cherche pour expliquer, et fausseraient la recherche).
String _code(File f) => f
    .readAsStringSync()
    .split('\n')
    .where((String l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  final File mobile =
      File('lib/features/player/presentation/video_player_screen.dart');
  late String code;

  setUpAll(() {
    expect(mobile.existsSync(), isTrue,
        reason: 'chemin du lecteur mobile changé');
    code = _code(mobile);
  });

  test('P0 demuxer HLS : reset auto en tête de _openMediaInner, hls seulement sur playlist',
      () {
    final int inner = code.indexOf('Future<void> _openMediaInner(');
    expect(inner, greaterThan(-1));
    final int firstOpen = code.indexOf('await _player.open(', inner);
    expect(firstOpen, greaterThan(inner));
    final String head = code.substring(inner, firstOpen);
    expect(head, contains("demuxer-lavf-format', 'auto'"),
        reason: 'un zap HLS→TS laissait le démuxeur collé à hls → écran noir');
    expect(head, isNot(contains("demuxer-lavf-format', 'hls'")),
        reason: 'forcer hls en tête casserait le chemin TS/relais');
    expect(code, contains("demuxer-lavf-format', 'hls'"),
        reason: 'le chemin playlist HLS doit toujours forcer hls');
  });

  test('P0 FFmpeg reconnect borné (pas de 4xx, pas EOF)', () {
    expect(code, contains('reconnect_at_eof=0'));
    expect(code, contains('reconnect_on_http_error=5xx,408,429'));
    expect(code, isNot(contains('reconnect_on_http_error=4xx')));
    expect(code, isNot(contains('reconnect_at_eof=1')),
        reason: '4xx inclut 458 et ouvre une 2e socket ; EOF live = Dart/relais');
  });

  test('P0 EOF live via relais : pas de _openMedia, budget → _hasError', () {
    final int completed = code.indexOf('_player.stream.completed.listen');
    final int error = code.indexOf('_player.stream.error.listen');
    expect(completed, greaterThan(-1));
    expect(error, greaterThan(completed));
    final String bloc = code.substring(completed, error);
    expect(bloc, contains('_hasError = true'),
        reason: 'budget watchdog épuisé : erreur visible, pas un return silencieux');
    expect(bloc, contains('if (_liveViaRelay) return;'),
        reason: 'le relais reconnecte déjà — rouvrir mpv = 2e socket');
    expect(bloc, contains('_openMedia(_effectiveUrl)'),
        reason: 'HLS live (hors relais) garde la reprise silencieuse');
  });

  test('P0 tous les _player.open sont awaités + garde de génération', () {
    final Iterable<RegExpMatch> bare =
        RegExp(r'(?<!await )_player\.open\(').allMatches(code);
    expect(bare, isEmpty, reason: 'open non awaité → course zap / 2e socket');
    final Iterable<RegExpMatch> opens =
        RegExp(r'await _player\.open\(').allMatches(code);
    expect(opens.length, 5, reason: '5 chemins d\'open (override, HLS, VOD, relais, repli)');
    for (final RegExpMatch m in opens) {
      final String after = code.substring(m.end, m.end + 180);
      expect(after, contains('if (!mounted || gen != _openGeneration) return;'),
          reason: 'après open, un zap plus récent ne doit pas continuer');
    }
  });

  test('P1 watchdog VOD : ne relance pas un film fini', () {
    final int tick = code.indexOf('void _watchdogTick()');
    final int recover = code.indexOf('void _watchdogRecover()');
    expect(tick, greaterThan(-1));
    expect(recover, greaterThan(tick));
    final String bloc = code.substring(tick, recover);
    expect(bloc, contains('if (!_currentChannel.isLive) return;'));
  });

  test('P1 logs mpv : credentials masqués avant recordEvent', () {
    final int log = code.indexOf('_player.stream.log.listen');
    expect(log, greaterThan(-1));
    final String bloc = code.substring(log, log + 450);
    expect(bloc, contains('StreamDiagnostics.maskCredentials('),
        reason: 'les logs mpv portent souvent l\'URL Xtream complète');
  });
}
