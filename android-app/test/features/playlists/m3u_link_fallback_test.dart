// =========================================================
//  m3u_link_fallback_test.dart — Après l'API Xtream, repli M3U ou pas ?
// =========================================================
//  Mesuré le 05/10/2026 : un mot de passe déformé par le clavier du
//  téléphone (apostrophe typographique). Si le serveur répond
//  « identifiants refusés », retenter le fichier M3U avec les mêmes
//  identifiants ne sert à rien et peut coûter deux minutes de silence.
// =========================================================
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/playlists/data/xtream_client.dart';

void main() {
  test('identifiants refusés : pas de repli M3U', () {
    expect(
      RemoteSourceRepository.shouldFallbackToM3u(
        XtreamAuthException('Identifiants refusés (auth=0).'),
      ),
      isFalse,
    );
  });

  test('pas d\'API, serveur muet, HTML, autre erreur : repli M3U', () {
    expect(
      RemoteSourceRepository.shouldFallbackToM3u(
        XtreamException('Serveur Xtream injoignable (srv.example.test).'),
      ),
      isTrue,
    );
    expect(
      RemoteSourceRepository.shouldFallbackToM3u(
        TimeoutException('aucune réponse', const Duration(seconds: 20)),
      ),
      isTrue,
    );
    expect(RemoteSourceRepository.shouldFallbackToM3u(Exception('HTML')), isTrue);
    expect(RemoteSourceRepository.shouldFallbackToM3u(null), isTrue);
  });
}
