// =========================================================
//  subscription_backend_origin_test.dart — le heartbeat ne fuit plus
// =========================================================
//  Une URL M3U porte presque toujours `username=…&password=…`. Avant, le
//  heartbeat l'envoyait telle quelle comme « server » de la source, à rebours
//  du commentaire « SANS mot de passe ». On ne remonte plus que l'origine.
//  Ce test verrouille la règle : jamais de chemin, jamais de requête.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/subscription/data/subscription_backend.dart';

void main() {
  test('URL M3U avec identifiants → origine seule', () {
    expect(
      SubscriptionBackend.originOnly(
          'http://panel.example:8080/get.php?username=u&password=p&type=m3u'),
      'http://panel.example:8080',
    );
  });

  test('sans port explicite → schéma + hôte', () {
    expect(
      SubscriptionBackend.originOnly('https://cdn.example/playlist.m3u8'),
      'https://cdn.example',
    );
  });

  test('chaîne qui n\'est pas une URL → vide', () {
    expect(SubscriptionBackend.originOnly(''), '');
    expect(SubscriptionBackend.originOnly('pas une url'), '');
    expect(SubscriptionBackend.originOnly('/sdcard/liste.m3u'), '');
  });

  test('jamais un identifiant dans le résultat', () {
    final String out = SubscriptionBackend.originOnly(
        'http://user:secret@panel.example/get.php?password=p');
    expect(out.contains('secret'), isFalse);
    expect(out.contains('password'), isFalse);
    expect(out, 'http://panel.example');
  });
}
