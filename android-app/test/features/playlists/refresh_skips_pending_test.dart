// =========================================================
//  refresh_skips_pending_test.dart — La passe « nouvelles chaînes » laisse
//  tranquille une liste dont l'ajout est en cours
// =========================================================
//  Une liste jamais synchronisée (`lastSyncedAt` nul) est un ajout en cours :
//  la re-télécharger en parallèle doublait la mémoire (50 000 chaînes × 2)
//  sur une box 1 Go. Règle pure `PlaylistRepository.shouldRefreshPlaylist`.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';

Playlist _p({int? lastSyncedAt, bool hidden = false}) => Playlist(
      id: 1,
      name: 'L',
      type: PlaylistType.m3u,
      m3uUrl: 'http://127.0.0.1/l.m3u',
      createdAt: 1791234612000,
      lastSyncedAt: lastSyncedAt,
      hidden: hidden,
    );

void main() {
  const int now = 1791300000000;
  const int sixHoursAgo = now - 6 * 3600 * 1000;

  test('jamais synchronisée = ajout en cours → ignorée', () {
    expect(
      PlaylistRepository.shouldRefreshPlaylist(_p(), freshAfter: sixHoursAgo, pendingLegacy: false),
      isFalse,
    );
    expect(
      PlaylistRepository.shouldRefreshPlaylist(_p(), freshAfter: null, pendingLegacy: false),
      isFalse,
    );
  });

  test('repli zuno.refresh.pending_legacy : ancien comportement, elle est re-téléchargée', () {
    expect(
      PlaylistRepository.shouldRefreshPlaylist(_p(), freshAfter: sixHoursAgo, pendingLegacy: true),
      isTrue,
    );
  });

  test('à jour depuis moins que la fenêtre → ignorée ; plus vieille → actualisée', () {
    expect(
      PlaylistRepository.shouldRefreshPlaylist(_p(lastSyncedAt: now - 60000),
          freshAfter: sixHoursAgo, pendingLegacy: false),
      isFalse,
    );
    expect(
      PlaylistRepository.shouldRefreshPlaylist(_p(lastSyncedAt: sixHoursAgo - 1),
          freshAfter: sixHoursAgo, pendingLegacy: false),
      isTrue,
    );
    expect(
      PlaylistRepository.shouldRefreshPlaylist(_p(lastSyncedAt: sixHoursAgo - 1),
          freshAfter: null, pendingLegacy: false),
      isTrue,
    );
  });

  test('liste cachée : jamais', () {
    expect(
      PlaylistRepository.shouldRefreshPlaylist(_p(lastSyncedAt: 1, hidden: true),
          freshAfter: null, pendingLegacy: true),
      isFalse,
    );
  });
}
