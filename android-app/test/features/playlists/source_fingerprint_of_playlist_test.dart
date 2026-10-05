// =========================================================
//  source_fingerprint_of_playlist_test.dart — Une liste Xtream venue
//  d'un lien get.php du panel répond à ses DEUX empreintes.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/playlists/domain/source_fingerprint.dart';

void main() {
  const String link = 'http://srv.example.test:80/get.php?username=u1&password=p1';

  test('liste M3U classique : une empreinte, celle du lien', () {
    const Playlist p = Playlist(
      id: 1, name: 'A', type: PlaylistType.m3u, createdAt: 0, m3uUrl: link,
    );
    expect(SourceFingerprint.ofPlaylist(p), <String>['m3u|$link']);
  });

  test('compte Xtream saisi à la main : une empreinte Xtream', () {
    const Playlist p = Playlist(
      id: 2, name: 'B', type: PlaylistType.xtream, createdAt: 0,
      xtreamServer: 'http://srv.example.test:80', xtreamUsername: 'u1',
      xtreamPassword: 'p1',
    );
    expect(SourceFingerprint.ofPlaylist(p), <String>['xtream|http://srv.example.test:80|u1']);
  });

  test('compte Xtream issu d\'un lien get.php : les deux empreintes', () {
    const Playlist p = Playlist(
      id: 3, name: 'C', type: PlaylistType.xtream, createdAt: 0,
      m3uUrl: link,
      xtreamServer: 'http://srv.example.test:80', xtreamUsername: 'u1',
      xtreamPassword: 'p1',
    );
    final List<String> fps = SourceFingerprint.ofPlaylist(p);
    expect(fps, contains('xtream|http://srv.example.test:80|u1'));
    expect(fps, contains('m3u|$link'));
    // Le panel retire « par le lien » : la liste est retrouvée.
    final Set<String> drop = <String>{'m3u|$link'};
    expect(fps.any(drop.contains), isTrue);
  });

  test('sans rien d\'identifiable : aucune empreinte', () {
    const Playlist p = Playlist(id: 4, name: 'D', type: PlaylistType.m3u, createdAt: 0);
    expect(SourceFingerprint.ofPlaylist(p), isEmpty);
  });
}
