// =========================================================
//  black_box_test.dart — Enregistreur persistant + analyse
// =========================================================
//  La boîte noire doit : capturer le StructuredLogger et le
//  CrashReporting, persister sur disque (post-mortem de crash),
//  tourner ses fichiers, et produire des constats automatiques
//  corrects sur des signatures de pannes connues.
// =========================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/crash/crash_reporting.dart';
import 'package:tv_king/core/observability/black_box.dart';
import 'package:tv_king/core/observability/structured_logger.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('blackbox_test_');
    // NB : pas de clearSinks() ici — la boîte noire ne s'abonne au
    // logger qu'UNE fois par process (revue 2026-07-09, MINEUR 4) ;
    // vider les sinks la débrancherait pour tous les tests suivants.
  });

  tearDown(() async {
    await BlackBox.instance.dispose();
    try {
      await tmp.delete(recursive: true);
    } on Exception {/* best effort */}
  });

  test('capture logger + crash, persiste, et relit le post-mortem',
      () async {
    await BlackBox.instance.initialize(directory: tmp);

    StructuredLogger.instance.info(
      domain: 'cast',
      event: 'google.load_media',
      ctx: <String, Object?>{'path': 'local_hls_relay'},
    );
    CrashReporting.instance.recordError(
      StateError('boum'),
      StackTrace.current,
      context: 'test',
      fatal: true,
    );

    final List<String> recent = BlackBox.instance.recent();
    expect(recent.any((String l) => l.contains('google.load_media')), isTrue);
    expect(recent.any((String l) => l.contains('fatal_error')), isTrue);

    // Persistance : après flush, le fichier contient les mêmes lignes.
    await BlackBox.instance.flushNow();
    final File f = File('${tmp.path}/black_box/blackbox.jsonl');
    expect(await f.exists(), isTrue);
    final String onDisk = await f.readAsString();
    expect(onDisk, contains('google.load_media'));
    expect(onDisk, contains('fatal_error'));

    // Post-mortem : une nouvelle « session » (re-init) retrouve la
    // queue de la précédente.
    await BlackBox.instance.dispose();
    await BlackBox.instance.initialize(directory: tmp);
    expect(BlackBox.instance.previousSessionTail, isNotEmpty);
    expect(
      BlackBox.instance.previousSessionTail.join('\n'),
      contains('fatal_error'),
    );
  });

  test('analyse : signatures proxy bloqué / crash / domaine bruyant',
      () async {
    await BlackBox.instance.initialize(directory: tmp);

    // Proxy cloud rejeté par le fournisseur (456).
    StructuredLogger.instance.info(
      domain: 'cast',
      event: 'proxy.verify',
      ctx: <String, Object?>{'status': 502, 'upstream: 456': true},
    );
    // NB : le ctx réel est {'status':..,'upstream':'456'} → on émet la
    // vraie forme aussi.
    StructuredLogger.instance.info(
      domain: 'cast',
      event: 'proxy.verify',
      ctx: <String, Object?>{'status': 502, 'upstream': '456'},
    );
    CrashReporting.instance
        .recordError(StateError('x'), null, fatal: true);
    for (int i = 0; i < 6; i++) {
      StructuredLogger.instance.warn(
        domain: 'relay',
        event: 'stream_broken',
        ctx: <String, Object?>{'i': i},
      );
    }

    final List<BlackBoxFinding> findings = BlackBox.instance.analyze();
    final String all = findings.map((BlackBoxFinding f) => f.toString()).join('\n');
    expect(all, contains('Proxy cloud refusé'));
    expect(all, contains('Crash de l\'application'));
    expect(all, contains('Domaine bruyant : relay'));
    // Tri : critique avant info.
    expect(findings.first.severity, 'critique');
  });

  test('rapport complet : constats + journal + sections', () async {
    await BlackBox.instance.initialize(directory: tmp);
    StructuredLogger.instance.error(
      domain: 'player',
      event: 'open_failed',
      ctx: <String, Object?>{'why': 'test'},
    );
    final String report = BlackBox.instance.buildReport();
    expect(report, contains('=== BOÎTE NOIRE — 7 MOTION ==='));
    expect(report, contains('--- Constats automatiques'));
    expect(report, contains('--- Journal boîte noire'));
    expect(report, contains('open_failed'));
  });

  test('rotation du fichier au-delà de la taille max', () async {
    await BlackBox.instance.initialize(directory: tmp);
    // Gonfle artificiellement le fichier au-delà de kMaxFileBytes.
    final String bigCtx = 'x' * 4096;
    for (int i = 0; i < 300; i++) {
      BlackBox.instance.record(
        domain: 'test',
        event: 'bulk',
        ctx: <String, Object?>{'pad': bigCtx, 'i': i},
      );
      if (i % 50 == 0) await BlackBox.instance.flushNow();
    }
    await BlackBox.instance.flushNow();
    final File gen1 = File('${tmp.path}/black_box/blackbox.1.jsonl');
    final File cur = File('${tmp.path}/black_box/blackbox.jsonl');
    expect(await gen1.exists(), isTrue, reason: 'rotation attendue');
    // Le fichier courant est reparti sous la limite.
    if (await cur.exists()) {
      expect(await cur.length(), lessThan(BlackBox.kMaxFileBytes));
    }
    // Les lignes restent du JSON valide.
    final List<String> lines = await gen1.readAsLines();
    expect(lines, isNotEmpty);
    jsonDecode(lines.first);
  });
}
