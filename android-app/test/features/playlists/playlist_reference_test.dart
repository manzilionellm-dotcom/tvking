// =========================================================
//  playlist_reference_test.dart — Référence affichée dans « Mes sources »
// =========================================================
//  On vérifie que l'écran montre l'identifiant et le serveur, et JAMAIS le
//  mot de passe.
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';

void main() {
  test('Xtream : username + hôte:port, sans mot de passe', () {
    const Playlist p = Playlist(
      id: 1,
      name: 'Mon abonnement',
      type: PlaylistType.xtream,
      createdAt: 0,
      xtreamServer: 'http://line.example.com:8080/',
      xtreamUsername: ' client42 ',
      xtreamPassword: 'secret',
    );
    expect(p.reference.user, 'client42');
    expect(p.reference.host, 'line.example.com:8080');
    expect('${p.reference}', isNot(contains('secret')));
  });

  test('M3U : username tiré de l\'URL, hôte sans port par défaut', () {
    const Playlist p = Playlist(
      id: 2,
      name: 'Liste',
      type: PlaylistType.m3u,
      createdAt: 0,
      m3uUrl:
          'https://panel.example.net/get.php?username=bob&password=pw&type=m3u_plus',
    );
    expect(p.reference.user, 'bob');
    expect(p.reference.host, 'panel.example.net');
    expect('${p.reference}', isNot(contains('pw')));
  });

  test('M3U sans identifiant : seulement l\'hôte', () {
    const Playlist p = Playlist(
      id: 3,
      name: 'Liste',
      type: PlaylistType.m3u,
      createdAt: 0,
      m3uUrl: 'http://cdn.example.org/list.m3u',
    );
    expect(p.reference.user, isNull);
    expect(p.reference.host, 'cdn.example.org');
  });

  test('désactivation : lue et écrite en base (colonne hidden)', () {
    final Playlist p = Playlist.fromMap(<String, Object?>{
      'id': 4,
      'name': 'X',
      'type': 'xtream',
      'created_at': 0,
      'hidden': 1,
    });
    expect(p.hidden, isTrue);
    expect(p.toMap()['hidden'], 1);
    expect(p.copyWith(channelCount: 5).hidden, isTrue);
  });
}
