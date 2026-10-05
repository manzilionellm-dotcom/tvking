// =========================================================
//  m3u_link_test.dart — Un lien get.php devient un compte Xtream ;
//  tout autre lien reste un M3U. Adresses en example.test.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/domain/m3u_link.dart';

void main() {
  test('lien get.php classique : serveur, identifiant, mot de passe', () {
    final XtreamAccount? a = xtreamFromM3uLink(
      'http://srv.example.test:8080/get.php?username=u1&password=p1&type=m3u_plus&output=ts',
    );
    expect(a, isNotNull);
    expect(a!.serverUrl, 'http://srv.example.test:8080');
    expect(a.username, 'u1');
    expect(a.password, 'p1');
  });

  test('port par défaut (:80 en http) : Dart le retire, le serveur reste le même', () {
    final XtreamAccount? a = xtreamFromM3uLink(
      'http://srv.example.test:80/get.php?username=u1&password=p1',
    );
    expect(a, isNotNull);
    expect(a!.serverUrl, 'http://srv.example.test');
  });

  test('sans port, en https, dans un sous-dossier, casse différente', () {
    final XtreamAccount? a = xtreamFromM3uLink(
      'HTTPS://Srv.Example.test/iptv/GET.PHP?password=p2&username=u2',
    );
    expect(a, isNotNull);
    expect(a!.serverUrl, 'https://srv.example.test');
    expect(a.username, 'u2');
    expect(a.password, 'p2');
  });

  test('pas un get.php, ou identifiants absents : on garde le M3U', () {
    expect(xtreamFromM3uLink('http://srv.example.test/liste.m3u'), isNull);
    expect(xtreamFromM3uLink('http://srv.example.test/get.php?username=u'), isNull);
    expect(xtreamFromM3uLink('http://srv.example.test/get.php?password=p'), isNull);
    expect(xtreamFromM3uLink('http://srv.example.test/get.php'), isNull);
    expect(xtreamFromM3uLink('ftp://srv.example.test/get.php?username=u&password=p'), isNull);
    expect(xtreamFromM3uLink(''), isNull);
    expect(xtreamFromM3uLink(null), isNull);
    expect(xtreamFromM3uLink('pas un lien'), isNull);
  });
}
