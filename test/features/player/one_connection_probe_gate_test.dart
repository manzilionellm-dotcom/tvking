// =========================================================
//  one_connection_probe_gate_test.dart — pas de salve de sondes sur 1-conn
// =========================================================
//  FAIT TERRAIN (journal de vol du 19/08 23:38, ligne à 1 connexion) : la
//  salve multi-signatures (9 UA) puis la cascade se sont déclenchées sur un
//  compte max_connections=1 — seule une panne DNS les a empêchées d'ouvrir
//  leurs connexions. Chaque sonde est une connexion ouverte/fermée sur LE
//  créneau unique, pile pendant qu'on attend qu'il se libère.
//
//  Contrat verrouillé ici : quand la Boîte noire sait que le compte est à
//  1 connexion, le diagnostic sonde l'URL d'origine avec UNE SEULE
//  signature (la courante) et la cascade reste mono-signature. Sur un
//  compte multi-connexions (ou inconnu), la salve complète est conservée.
// =========================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/player/data/stream_blocked_fallback.dart';
import 'package:tv_king/features/player/data/stream_diagnostics.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';

String _journal() => StreamDiagnostics.instance.events
    .map((StreamDiagEvent e) => e.toString())
    .join('\n');

int _probedUaCount() =>
    RegExp(r'\[probe\] UA "').allMatches(_journal()).length;

void main() {
  test(
      'compte 1-connexion connu → UNE seule signature sondée '
      '(pas de salve multi-signatures sur le créneau unique)', () async {
    // Panel mocké : 404 partout — on ne teste pas la victoire d'une
    // variante, uniquement le NOMBRE de signatures essayées.
    final HttpServer dead =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    dead.listen((HttpRequest req) async {
      req.response.statusCode = 404;
      await req.response.close();
    });
    final String tsUrl = 'http://127.0.0.1:${dead.port}/USER/PASS/7.ts';
    PlaylistRepository.instance.debugSeedPlaylists(<Playlist>[
      Playlist(
        id: 78,
        name: 'Panel 1-connexion',
        type: PlaylistType.xtream,
        createdAt: 0,
        xtreamServer: 'http://127.0.0.1:${dead.port}',
        xtreamUsername: 'USER',
        xtreamPassword: 'PASS',
      ),
    ]);
    final Channel channel = Channel(
      id: 'chan-1conn',
      playlistId: 78,
      name: 'Game One (test)',
      category: 'x',
      streamUrl: tsUrl,
      isLive: true,
    );

    // LE FAIT : la Boîte noire connaît le compte — max_connections = 1.
    StreamDiagnostics.instance.recordXtreamAccount(
      status: 'Active',
      expDate: DateTime.now().add(const Duration(days: 30)),
      maxConnections: 1,
      activeCons: 0,
    );
    addTearDown(() => StreamDiagnostics.instance.recordXtreamAccount());

    final List<String> blockedMessages = <String>[];
    final StreamBlockedFallback fallback = StreamBlockedFallback(
      getChannel: () => channel,
      getOverrideUrl: () => null,
      getEffectiveUrl: () => tsUrl,
      isAlive: () => true,
      hasDecodedFrames: () => false,
      getAdoptedAltUrl: () => null,
      setAdoptedAltUrl: (_) {},
      resetWatchdogBudget: () {},
      reopen: (_) {},
      showBlocked: blockedMessages.add,
    );

    final int uaBefore = _probedUaCount();
    await fallback.run();
    await dead.close(force: true);

    final String journal = _journal();
    expect(journal, contains('[1-connexion]'),
        reason: 'la garde doit être journalisée (diagnostic à distance)');
    expect(_probedUaCount() - uaBefore, 1,
        reason: 'UNE seule signature sondée sur l\'URL d\'origine — chaque '
            'sonde supplémentaire est une connexion de plus sur une ligne '
            'qui n\'en autorise qu\'une');
    // Le diagnostic garde sa valeur : la cascade de FORMATS tourne quand
    // même (mono-signature) — c'est elle qui trouve le bon conteneur.
    expect(journal, contains('[cascade] DÉMARRAGE'),
        reason: 'la cascade de formats reste indispensable sur 1-connexion');
  });

  test('compte multi-connexions (ou inconnu) → salve multi-signatures '
      'conservée (comportement historique)', () async {
    final HttpServer dead =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    dead.listen((HttpRequest req) async {
      req.response.statusCode = 404;
      await req.response.close();
    });
    final String tsUrl = 'http://127.0.0.1:${dead.port}/USER/PASS/8.ts';
    PlaylistRepository.instance.debugSeedPlaylists(const <Playlist>[]);
    final Channel channel = Channel(
      id: 'chan-multi',
      name: 'Multi (test)',
      category: 'x',
      streamUrl: tsUrl,
      isLive: true,
    );
    // Compte à 2 connexions : la salve complète reste permise.
    StreamDiagnostics.instance.recordXtreamAccount(
      status: 'Active',
      maxConnections: 2,
      activeCons: 0,
    );
    addTearDown(() => StreamDiagnostics.instance.recordXtreamAccount());

    final List<String> blockedMessages = <String>[];
    final StreamBlockedFallback fallback = StreamBlockedFallback(
      getChannel: () => channel,
      getOverrideUrl: () => null,
      getEffectiveUrl: () => tsUrl,
      isAlive: () => true,
      hasDecodedFrames: () => false,
      getAdoptedAltUrl: () => null,
      setAdoptedAltUrl: (_) {},
      resetWatchdogBudget: () {},
      reopen: (_) {},
      showBlocked: blockedMessages.add,
    );

    final int uaBefore = _probedUaCount();
    await fallback.run();
    await dead.close(force: true);

    // NB : pas d'assertion négative sur « [1-connexion] » ici — le journal
    // de la Boîte noire est un tampon GLOBAL partagé avec le test précédent.
    // Le compte de signatures (> 1) suffit à prouver que la garde est OFF.
    expect(_probedUaCount() - uaBefore, greaterThan(1),
        reason: 'sur un compte multi-connexions, le diagnostic complet '
            'multi-signatures reste le comportement attendu');
  });
}
