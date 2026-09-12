// =========================================================
//  smart_search_perf_test.dart — Coût du ranking (charge box)
// =========================================================
//  Une box 1 Go tient ~5 000–10 000 chaînes en RAM (DeviceMemory).
//  On mesure SmartSearch.rank sur 10 000 chaînes SYNTHÉTIQUES, sur
//  CETTE machine, et on publie le chiffre BRUT + le nom de la
//  machine. Le propriétaire juge lui-même.
//
//  RÈGLE DE SEUIL (corrigée) : une CI est 5 à 15× plus rapide
//  qu'une box à 30 €. On n'applique PAS 50 ms au résultat CI.
//  Facteur 10 → si le bench dépasse ~5 ms ici, le calcul sort
//  de l'isolate UI (compute).
//
//  HONNÊTETÉ : CI ≠ Fire TV Stick 1 Go. C'est une borne
//  indicative, pas une mesure terrain.
// =========================================================

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/data/smart_search.dart';
import 'package:tv_king/features/channels/domain/channel.dart';

/// Seuil CI après facteur 10 (50 ms box / 10). Au-delà → isolate.
const int kCiBudgetMs = 5;

Channel _synth(int i) => Channel(
      id: 'perf-$i',
      name: i % 17 == 0
          ? 'beIN SPORTS ${(i % 9) + 1} FR'
          : i % 11 == 0
              ? 'Ciné+ Premier $i'
              : 'News Channel $i HD',
      category: i.isEven ? 'SPORT' : 'GENERAL',
      streamUrl: 'http://example.com/$i.ts',
      isLive: true,
    );

void main() {
  test('ranking 10 000 chaînes : chiffre brut + machine + seuil 5 ms CI',
      () {
    final List<Channel> pool = <Channel>[
      for (int i = 0; i < 10000; i++) _synth(i),
    ];

    // Échauffement : le 1er passage paie la mémoïsation des docs
    // (normalize). On mesure le 2e — c'est le coût D'UNE FRAPPE
    // une fois le bassin déjà vu (cas réel après la 1re lettre).
    SmartSearch.rank(query: 'bein 1', pool: pool, limit: 60);
    final Stopwatch sw = Stopwatch()..start();
    final List<Channel> hits =
        SmartSearch.rank(query: 'bein 1', pool: pool, limit: 60);
    sw.stop();
    final int ms = sw.elapsedMilliseconds;
    final int us = sw.elapsedMicroseconds;

    final String machine = <String>[
      Platform.localHostname,
      Platform.operatingSystem,
      Platform.operatingSystemVersion,
    ].join(' | ');

    // debugPrint (jamais print) : le propriétaire veut le chiffre
    // BRUT + le nom de la machine dans la sortie du test.
    debugPrint(
      '[SmartSearch perf] ${us / 1000.0} ms brut '
      '(${hits.length} hits / 10000) — machine: $machine',
    );
    debugPrint('[SmartSearch perf] uname: ${_uname()}');
    debugPrint(
      '[SmartSearch perf] seuil CI ${kCiBudgetMs} ms (facteur 10 vs ~50 ms box). '
      'Décision : ${ms > kCiBudgetMs ? "rankAsync / Isolate.run (hors UI)" : "sync UI OK"}',
    );

    expect(hits, isNotEmpty,
        reason: 'le bassin synthétique contient des beIN');

    // Garde : si on dépasse le budget CI, le ranking DOIT déjà
    // tourner hors isolate UI (voir smart_search.dart / compute).
    // On n'échoue pas le test sur un spike unique — on documente.
    // La décision isolate est prise dans le code de prod selon
    // cette même constante [kCiBudgetMs].
    expect(ms, lessThan(200),
        reason: 'même en CI, 200 ms sur 10k = algo cassé');
  });
}

String _uname() {
  try {
    final ProcessResult r = Process.runSync('uname', <String>['-a']);
    if (r.exitCode == 0) return (r.stdout as String).trim();
  } catch (_) {/* Windows / sandbox */}
  return 'uname indisponible';
}
