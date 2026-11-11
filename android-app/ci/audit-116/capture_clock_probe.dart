// Sonde sans Flutter : une date civile figée ne doit pas bloquer les délais.
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final expected = DateTime.fromMillisecondsSinceEpoch(
    int.parse(Platform.environment['AUDIT116_CLOCK_EPOCH']!) * 1000,
    isUtc: true,
  );
  final before = DateTime.now().toUtc();
  final watch = Stopwatch()..start();
  await Future<void>.delayed(const Duration(milliseconds: 120));
  watch.stop();
  final after = DateTime.now().toUtc();
  final valid = before == expected &&
      after == expected &&
      watch.elapsedMilliseconds >= 100 &&
      watch.elapsedMilliseconds < 5000;
  stdout.writeln(jsonEncode({
    'executable': Platform.resolvedExecutable,
    'before': before.toIso8601String(),
    'after': after.toIso8601String(),
    'monotonicElapsedMs': watch.elapsedMilliseconds,
    'passed': valid,
  }));
  if (!valid) exitCode = 1;
}
