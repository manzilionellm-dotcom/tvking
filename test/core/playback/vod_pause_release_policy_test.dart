// =========================================================
//  vod_pause_release_policy_test.dart — « pause longue = connexion rendue »
// =========================================================
//  Demande exploitant (19/08, ligne Xtream 1-connexion) : un film en pause
//  plus de ~20 s doit rendre sa connexion au panel ; la reprise ré-ouvre et
//  seek. Ces tests verrouillent le « quand » : seulement un VOD réseau en
//  pause volontaire, une seule fois par pause, jamais le direct ni un
//  fichier local.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/playback/vod_pause_release_policy.dart';

void main() {
  final DateTime t0 = DateTime(2026, 8, 19, 20);
  DateTime after(Duration d) => t0.add(d);

  test('un film en pause rend la connexion après le seuil, UNE seule fois',
      () {
    final VodPauseReleasePolicy p =
        VodPauseReleasePolicy(threshold: const Duration(seconds: 20));
    expect(p.onTick(now: t0, isVod: true, pausedOnNetwork: true), isFalse);
    expect(
        p.onTick(
            now: after(const Duration(seconds: 16)),
            isVod: true,
            pausedOnNetwork: true),
        isFalse,
        reason: 'sous le seuil : on ne coupe pas une pause « je lis le résumé »');
    expect(
        p.onTick(
            now: after(const Duration(seconds: 20)),
            isVod: true,
            pausedOnNetwork: true),
        isTrue,
        reason: 'seuil atteint : la connexion doit être rendue MAINTENANT');
    expect(p.released, isTrue);
    expect(
        p.onTick(
            now: after(const Duration(seconds: 24)),
            isVod: true,
            pausedOnNetwork: true),
        isFalse,
        reason: 'déjà rendue : ne jamais redemander un stop');
  });

  test('le direct n\'est JAMAIS concerné (rien à reprendre)', () {
    final VodPauseReleasePolicy p =
        VodPauseReleasePolicy(threshold: const Duration(seconds: 20));
    expect(p.onTick(now: t0, isVod: false, pausedOnNetwork: true), isFalse);
    expect(
        p.onTick(
            now: after(const Duration(minutes: 5)),
            isVod: false,
            pausedOnNetwork: true),
        isFalse);
    expect(p.released, isFalse);
  });

  test('une lecture qui reprend avant le seuil ré-arme le compteur', () {
    final VodPauseReleasePolicy p =
        VodPauseReleasePolicy(threshold: const Duration(seconds: 20));
    p.onTick(now: t0, isVod: true, pausedOnNetwork: true);
    // Reprise (lecture en cours) à 15 s : plus de pause.
    p.onTick(
        now: after(const Duration(seconds: 15)),
        isVod: true,
        pausedOnNetwork: false);
    // Nouvelle pause : le seuil repart de ZÉRO (pas de cumul entre pauses).
    expect(
        p.onTick(
            now: after(const Duration(seconds: 16)),
            isVod: true,
            pausedOnNetwork: true),
        isFalse);
    expect(
        p.onTick(
            now: after(const Duration(seconds: 30)),
            isVod: true,
            pausedOnNetwork: true),
        isFalse,
        reason: '14 s de pause seulement depuis la reprise');
    expect(
        p.onTick(
            now: after(const Duration(seconds: 37)),
            isVod: true,
            pausedOnNetwork: true),
        isTrue);
  });

  test('la reprise de lecture remet released à zéro (prochaine pause propre)',
      () {
    final VodPauseReleasePolicy p =
        VodPauseReleasePolicy(threshold: const Duration(seconds: 20));
    p.onTick(now: t0, isVod: true, pausedOnNetwork: true);
    expect(
        p.onTick(
            now: after(const Duration(seconds: 21)),
            isVod: true,
            pausedOnNetwork: true),
        isTrue);
    // Le film rejoue (ré-ouvert + seek) : l'état se ré-arme tout seul.
    p.onTick(
        now: after(const Duration(seconds: 30)),
        isVod: true,
        pausedOnNetwork: false);
    expect(p.released, isFalse);
  });

  test('reset (zap / épisode suivant) repart d\'un état neuf', () {
    final VodPauseReleasePolicy p =
        VodPauseReleasePolicy(threshold: const Duration(seconds: 20));
    p.onTick(now: t0, isVod: true, pausedOnNetwork: true);
    p.onTick(
        now: after(const Duration(seconds: 21)),
        isVod: true,
        pausedOnNetwork: true);
    expect(p.released, isTrue);
    p.reset();
    expect(p.released, isFalse);
    expect(
        p.onTick(
            now: after(const Duration(seconds: 25)),
            isVod: true,
            pausedOnNetwork: true),
        isFalse,
        reason: 'après reset, le seuil repart de zéro');
  });
}
