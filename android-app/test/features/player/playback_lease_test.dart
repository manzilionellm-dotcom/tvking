// =========================================================
//  playback_lease_test.dart — un seul son, sessions périmées
// =========================================================
//  Pas de flux, pas de box. On vérifie la règle : prendre le son
//  coupe les autres, et un jeton d'avant le zap ne compte plus.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/playback_lease.dart';

void main() {
  test('un nouveau jeton invalide l\'ancien', () {
    final PlaybackSession session = PlaybackSession();
    final int first = session.open();
    final int second = session.open();
    expect(session.isCurrent(first), isFalse);
    expect(session.isCurrent(second), isTrue);
    expect(session.isCurrent(0), isFalse);
  });

  test('prendre le son coupe tous les autres lecteurs', () {
    final ExclusiveAudio audio = ExclusiveAudio();
    final List<int> silenced = <int>[];
    final int a = audio.register(() => silenced.add(1));
    final int b = audio.register(() => silenced.add(2));
    final int c = audio.register(() => silenced.add(3));
    audio.claim(b);
    expect(audio.owner, b);
    expect(silenced, <int>[1, 3]);
    silenced.clear();
    audio.claim(a);
    expect(audio.owner, a);
    expect(silenced, <int>[2, 3]);
    audio.unregister(c);
    expect(audio.registeredCount, 2);
  });

  test('20 prises de son d\'affilée : un seul propriétaire à la fin', () {
    final ExclusiveAudio audio = ExclusiveAudio();
    final List<bool> audible = <bool>[true, true];
    final int left = audio.register(() => audible[0] = false);
    final int right = audio.register(() => audible[1] = false);
    final Stopwatch watch = Stopwatch()..start();
    int last = left;
    for (int i = 0; i < 20; i++) {
      last = i.isEven ? left : right;
      audible[0] = last == left;
      audible[1] = last == right;
      audio.claim(last);
    }
    watch.stop();
    debugPrint('MESURE zap_20_microsecondes=${watch.elapsedMicroseconds}');
    expect(watch.elapsedMicroseconds, lessThan(50000));
    expect(audio.owner, last);
    expect(audible.where((bool v) => v).length, 1);
    expect(last, right, reason: 'le 20e zap (indice 19) est le lecteur de droite');
  });

  test('le plein écran bloque l\'aperçu, puis le libère', () {
    ForegroundPlayback.debugReset();
    expect(ForegroundPlayback.locked, isFalse);
    ForegroundPlayback.lock();
    ForegroundPlayback.lock();
    expect(ForegroundPlayback.locked, isTrue);
    ForegroundPlayback.unlock();
    expect(ForegroundPlayback.locked, isTrue);
    ForegroundPlayback.unlock();
    expect(ForegroundPlayback.locked, isFalse);
    ForegroundPlayback.debugReset();
  });
}
