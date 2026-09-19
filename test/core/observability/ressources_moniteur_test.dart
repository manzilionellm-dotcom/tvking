// =========================================================
//  ressources_moniteur_test.dart — RAM / CPU réels, pic sur l'heure
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (19/09/2026) : « remonte la RAM et le CPU
//  réels dans le heartbeat — Mo utilisés, pic sur l'heure — pour savoir
//  quelles box vivent au bord. »
//
//  Ce que ces tests verrouillent :
//    • la lecture de /proc/self/stat survit à un nom de processus avec
//      espaces et parenthèses (le piège classique du split naïf) ;
//    • le pourcentage est celui de l'APPAREIL (divisé par les cœurs),
//      borné 0..100, null quand il ne se calcule pas ;
//    • le pic est celui de l'HEURE glissante, pas depuis le boot ;
//    • sans relevé, le paquet est VIDE (pas un 0 inventé).
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/observability/ressources_moniteur.dart';

void main() {
  group('ticksCpuDepuisStat', () {
    test('ligne proc(5) ordinaire : utime + stime', () {
      // pid (comm) state ppid pgrp session tty tpgid flags minflt cminflt
      // majflt cmajflt utime stime …
      const String stat =
          '1234 (tv_king) S 1 1234 1234 0 -1 4194560 100 0 0 0 250 50 0 0 20 0 30 0 1000 0 0';
      expect(ticksCpuDepuisStat(stat), 300);
    });

    test('nom de processus avec espaces et parenthèses', () {
      const String stat =
          '1234 (7 MOTION (tv)) S 1 1234 1234 0 -1 4194560 100 0 0 0 40 10 0 0 20 0 30 0 1000 0 0';
      expect(ticksCpuDepuisStat(stat), 50);
    });

    test('ligne tronquée ou vide → null', () {
      expect(ticksCpuDepuisStat('1234 (x) S 1 2'), isNull);
      expect(ticksCpuDepuisStat(''), isNull);
      expect(ticksCpuDepuisStat('pas une ligne stat'), isNull);
    });
  });

  group('pourcentCpu', () {
    test('un cœur plein sur quatre pendant une minute = 25 % de l\'appareil',
        () {
      // 60 s × 100 ticks/s = 6 000 ticks de CPU sur 60 s murales, 4 cœurs.
      expect(
        pourcentCpu(
          ticksAvant: 1000,
          ticksApres: 7000,
          ecoule: const Duration(minutes: 1),
          coeurs: 4,
        ),
        25,
      );
    });

    test('rien consommé → 0 ; tout consommé → 100, jamais plus', () {
      expect(
        pourcentCpu(
            ticksAvant: 5, ticksApres: 5,
            ecoule: const Duration(minutes: 1), coeurs: 2),
        0,
      );
      expect(
        pourcentCpu(
            ticksAvant: 0, ticksApres: 99999,
            ecoule: const Duration(minutes: 1), coeurs: 2),
        100,
      );
    });

    test('intervalle nul, ticks qui reculent, zéro cœur → null', () {
      expect(
        pourcentCpu(
            ticksAvant: 0, ticksApres: 10, ecoule: Duration.zero, coeurs: 4),
        isNull,
      );
      expect(
        pourcentCpu(
            ticksAvant: 10, ticksApres: 5,
            ecoule: const Duration(minutes: 1), coeurs: 4),
        isNull,
      );
      expect(
        pourcentCpu(
            ticksAvant: 0, ticksApres: 10,
            ecoule: const Duration(minutes: 1), coeurs: 0),
        isNull,
      );
    });
  });

  group('fenêtre d\'une heure', () {
    final RessourcesMoniteur m = RessourcesMoniteur.instance;
    setUp(m.reinitialiser);
    tearDown(m.reinitialiser);

    test('sans relevé : paquet vide, pas un zéro inventé', () {
      expect(m.toJson(), isEmpty);
      expect(m.memMo, isNull);
      expect(m.cpuPct, isNull);
    });

    test('le pic est celui de l\'heure écoulée, pas depuis le boot', () {
      final DateTime t0 = DateTime(2026, 9, 19, 20, 0);
      // Il y a 90 min : gros import à 900 Mo. Hors fenêtre au dernier relevé.
      m.injecter(EchantillonRessources(
          a: t0.subtract(const Duration(minutes: 90)), memMo: 900, cpuPct: 80));
      m.injecter(EchantillonRessources(
          a: t0.subtract(const Duration(minutes: 30)), memMo: 420, cpuPct: 12));
      m.injecter(EchantillonRessources(a: t0, memMo: 310, cpuPct: 7));
      expect(m.memMo, 310);
      expect(m.memPicMo, 420, reason: 'le 900 Mo d\'il y a 90 min est sorti');
      expect(m.cpuPct, 7);
      expect(m.cpuPicPct, 12);
      expect(m.toJson(), <String, Object?>{
        'mem_mb': 310,
        'mem_peak_mb': 420,
        'cpu_pct': 7,
        'cpu_peak_pct': 12,
      });
    });

    test('un relevé pile à une heure reste dans la fenêtre', () {
      final DateTime t0 = DateTime(2026, 9, 19, 20, 0);
      m.injecter(EchantillonRessources(
          a: t0.subtract(const Duration(hours: 1)), memMo: 500));
      m.injecter(EchantillonRessources(a: t0, memMo: 300));
      expect(m.memPicMo, 500);
    });

    test('CPU inconnu (Windows, premier relevé) : la RAM part quand même',
        () {
      m.injecter(EchantillonRessources(a: DateTime(2026, 9, 19), memMo: 200));
      expect(m.toJson(), <String, Object?>{'mem_mb': 200, 'mem_peak_mb': 200});
    });

    test('le dernier CPU connu est celui qu\'on envoie, pas un null récent',
        () {
      final DateTime t0 = DateTime(2026, 9, 19, 20, 0);
      m.injecter(EchantillonRessources(
          a: t0.subtract(const Duration(minutes: 1)), memMo: 200, cpuPct: 33));
      m.injecter(EchantillonRessources(a: t0, memMo: 210));
      expect(m.cpuPct, 33);
    });
  });
}
