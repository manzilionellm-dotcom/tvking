// Accès direct à deux services publics sans clé. Aucun secret supplémentaire
// dans l'app ou le panel. Les hôtes sont fixes, les compétitions une liste fermée.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/app/repair_flags.dart';
import '../../../core/blackbox/black_box.dart';
import '../domain/football_feed.dart';
import 'sports_repository.dart';

class FootballFeedResult {
  const FootballFeedResult({this.matches = const <FootballMatch>[], this.failure,
    this.receivedAt, this.disabled = false});
  final List<FootballMatch> matches;
  final SportsFailure? failure;
  final DateTime? receivedAt;
  final bool disabled;
}

class FootballFeedRepository {
  FootballFeedRepository()
      : _openLiga = Uri.parse('https://api.openligadb.de/'),
        _openFootball = Uri.parse('https://raw.githubusercontent.com/openfootball/football.json/master/');

  /// Seules les adresses changent : les tests utilisent le même client HTTP
  /// et le même décodeur que la box, avec un serveur sur 127.0.0.1.
  @visibleForTesting
  FootballFeedRepository.forTesting(Uri openLiga, Uri openFootball)
      : _openLiga = openLiga, _openFootball = openFootball;
  final Uri _openLiga;
  final Uri _openFootball;
  static const int maxResponseBytes = 1024 * 1024;

  Future<FootballFeedResult> load(FootballCompetition competition,
      {DateTime? now}) async {
    // Repli : ancien Sport, sans ce service et sans aucun appel réseau.
    if (RepairFlags.sportsCommunityOff) return const FootballFeedResult(disabled: true);
    final DateTime date = now ?? DateTime.now();
    final int season = date.month < 7 ? date.year - 1 : date.year;
    final Uri uri = competition.source == FootballSource.openLigaDb
        ? _openLiga.resolve('getmatchdata/${competition.code}')
        : _openFootball.resolve('$season-${(season + 1).toString().substring(2)}/${competition.code}.json');
    final http.Client client = http.Client();
    final Stopwatch elapsed = Stopwatch()..start();
    try {
      final String body = await _download(client, uri).timeout(const Duration(seconds: 20));
      final List<FootballMatch> matches = await compute(decodeFootballFeed,
          (competition.source, body));
      BlackBox.instance.info('SPORT',
          'calendrier chargé en ${elapsed.elapsedMilliseconds} ms (${matches.length} match(s))');
      return FootballFeedResult(matches: matches, receivedAt: DateTime.now());
    } catch (error) {
      final SportsFailure failure = error is SportsFailure ? error
          : SportsFailure(error is http.ClientException ? SportsFailureKind.network
              : error is FormatException || error is TypeError ? SportsFailureKind.invalidResponse
              : error is TimeoutException ? SportsFailureKind.timeout : SportsFailureKind.unavailable);
      BlackBox.instance.warn('SPORT', 'calendrier : ${failure.diagnostic}');
      return FootballFeedResult(failure: failure);
    } finally {
      client.close();
    }
  }

  Future<String> _download(http.Client client, Uri uri) async {
    final http.StreamedResponse response = await client.send(http.Request('GET', uri)
      ..headers['Accept'] = 'application/json');
    if (response.statusCode != 200) {
      throw SportsFailure(SportsFailureKind.http, statusCode: response.statusCode);
    }
    if ((response.contentLength ?? 0) > maxResponseBytes) {
      throw const FormatException('Calendrier trop volumineux');
    }
    final List<int> bytes = <int>[];
    await for (final List<int> chunk in response.stream) {
      if (bytes.length + chunk.length > maxResponseBytes) {
        throw const FormatException('Calendrier trop volumineux');
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }
}
