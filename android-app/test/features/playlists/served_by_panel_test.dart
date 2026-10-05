// =========================================================
//  served_by_panel_test.dart — « Mes sources » sait qu'une liste vient du panel
// =========================================================
//  Mesuré le 05/10/2026 : le propriétaire supprimait une liste sur la télé,
//  elle revenait cinq minutes plus tard, parce que le panel la sert toujours.
//  La règle testée ici décide quand la télé doit prévenir avant de supprimer.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/playlists/domain/source_fingerprint.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('règle pure : une empreinte servie suffit', () {
    expect(
      RemoteSourceRepository.servedByPanel(
        remembered: <String>{'xtream|http://srv.example.invalid|u1'},
        fingerprints: <String>['xtream|http://srv.example.invalid|u1', 'm3u|http://x'],
      ),
      isTrue,
    );
    expect(
      RemoteSourceRepository.servedByPanel(
        remembered: <String>{'xtream|http://srv.example.invalid|u1'},
        fingerprints: <String>['m3u|http://autre.example.invalid/l.m3u'],
      ),
      isFalse,
    );
    expect(
      RemoteSourceRepository.servedByPanel(remembered: <String>{}, fingerprints: <String>[]),
      isFalse,
    );
  });

  test('liste Xtream posée par le panel → prévenue ; liste ajoutée sur la télé → non', () async {
    final Playlist panel = Playlist(
      id: 1,
      name: 'Panel',
      type: PlaylistType.xtream,
      createdAt: 1791234612000,
      xtreamServer: 'http://srv.example.invalid',
      xtreamUsername: 'u1',
    );
    final Playlist mine = Playlist(
      id: 2,
      name: 'Perso',
      type: PlaylistType.m3u,
      createdAt: 1791234612000,
      m3uUrl: 'http://perso.example.invalid/l.m3u',
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      RemoteSourceRepository.rememberedKey: SourceFingerprint.ofPlaylist(panel),
    });
    expect(await RemoteSourceRepository.isServedByPanel(panel), isTrue);
    expect(await RemoteSourceRepository.isServedByPanel(mine), isFalse);
  });

  test('rien de mémorisé → jamais prévenue', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final Playlist p = Playlist(
      id: 3,
      name: 'X',
      type: PlaylistType.m3u,
      createdAt: 1791234612000,
      m3uUrl: 'http://l.example.invalid/l.m3u',
    );
    expect(await RemoteSourceRepository.isServedByPanel(p), isFalse);
  });
}
