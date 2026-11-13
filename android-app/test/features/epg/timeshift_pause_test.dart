import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/epg/domain/timeshift_pause.dart';

Channel _ch({
  required String url,
  bool catchup = false,
  String? source,
}) {
  return Channel(
    id: 'c1',
    name: 'Démo',
    category: 'Test',
    streamUrl: url,
    isLive: true,
    catchupSupported: catchup,
    catchupSource: source,
  );
}

void main() {
  final DateTime pause = DateTime(2026, 11, 4, 20, 15, 10);

  test('Xtream : pause longue → timeshift à la minute, sans second flux', () {
    final Channel channel = _ch(
      url: 'http://example.invalid:8080/live/demo/secret/55.ts',
    );
    expect(TimeshiftPause.supports(channel), isTrue);
    expect(
      TimeshiftPause.resumeUrl(
        channel: channel,
        pausedAt: pause,
        resumedAt: pause.add(const Duration(seconds: 20)),
        live: true,
        alreadyTimeshift: false,
      ),
      isNull,
    );
    final String? url = TimeshiftPause.resumeUrl(
      channel: channel,
      pausedAt: pause,
      resumedAt: pause.add(const Duration(seconds: 70)),
      live: true,
      alreadyTimeshift: false,
    );
    // Route Xtream réelle : /timeshift/… (corrigé le 12/11/2026). L'ancienne
    // attente « /live/timeshift/… » décrivait le défaut du constructeur : sur
    // un serveur Xtream, /live/(user)/(pass)/(id) y lit un faux identifiant.
    expect(
      url,
      'http://example.invalid:8080/timeshift/demo/secret/1/2026-11-04:20-15/55.ts',
    );
  });

  test('sans catch-up déclaré et sans forme Xtream : on ne fabrique rien', () {
    final Channel channel = _ch(url: 'http://example.invalid/chaine/direct');
    expect(TimeshiftPause.supports(channel), isFalse);
    expect(
      TimeshiftPause.resumeUrl(
        channel: channel,
        pausedAt: pause,
        resumedAt: pause.add(const Duration(minutes: 5)),
        live: true,
        alreadyTimeshift: false,
      ),
      isNull,
    );
  });

  test('modèle catch-up explicite, pas un direct déjà en rattrapage', () {
    final Channel channel = _ch(
      url: 'http://example.invalid/flux.ts',
      catchup: true,
      source: 'http://example.invalid/cu?utc=\${utc}&lutc=\${lutc}',
    );
    expect(TimeshiftPause.supports(channel), isTrue);
    final String? url = TimeshiftPause.resumeUrl(
      channel: channel,
      pausedAt: pause,
      resumedAt: pause.add(const Duration(minutes: 3)),
      live: true,
      alreadyTimeshift: false,
    );
    expect(url, contains('utc='));
    expect(
      TimeshiftPause.resumeUrl(
        channel: channel,
        pausedAt: pause,
        resumedAt: pause.add(const Duration(minutes: 3)),
        live: true,
        alreadyTimeshift: true,
      ),
      isNull,
    );
    expect(
      TimeshiftPause.resumeUrl(
        channel: channel,
        pausedAt: pause,
        resumedAt: pause.add(const Duration(minutes: 3)),
        live: false,
        alreadyTimeshift: false,
      ),
      isNull,
    );
  });
}
