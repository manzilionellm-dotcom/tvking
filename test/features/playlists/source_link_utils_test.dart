// =========================================================
//  source_link_utils_test.dart — Acceptation de TOUT lien M3U/Xtream
// =========================================================
//  Couvre les correctifs « le panel n'accepte pas tous les liens/codes » :
//  caractères invisibles de messagerie, schéma manquant, lien complet
//  collé dans le champ serveur, extraction des identifiants.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/source_link_utils.dart';

void main() {
  group('cleanInput', () {
    test('purge les caractères invisibles PARTOUT (pas juste aux bords)', () {
      // U+200B (espace sans chasse) au milieu, U+200E (marque LTR) au bord —
      // typique d'un lien copié depuis WhatsApp sur clavier arabe.
      const String dirty = '\u200Ehttp://ser\u200Bveur.com:8080\u200F ';
      expect(SourceLinkUtils.cleanInput(dirty), 'http://serveur.com:8080');
    });

    test('normalise les espaces insécables et trim', () {
      expect(SourceLinkUtils.cleanInput('\u00A0abc\u00A0'), 'abc');
    });
  });

  group('ensureScheme', () {
    test('complète http:// si absent', () {
      expect(SourceLinkUtils.ensureScheme('serveur.com:8080'),
          'http://serveur.com:8080');
    });

    test('ne touche pas un lien déjà schémé (http/https/rtmp)', () {
      expect(SourceLinkUtils.ensureScheme('https://s.com'), 'https://s.com');
      expect(SourceLinkUtils.ensureScheme('rtmp://s.com/live'),
          'rtmp://s.com/live');
    });

    test('lien protocole-relatif //hôte → http://hôte (pas http:////)', () {
      expect(SourceLinkUtils.ensureScheme('//serveur.com:8080'),
          'http://serveur.com:8080');
    });

    test('purge les invisibles avant de décider', () {
      expect(SourceLinkUtils.ensureScheme('\u200Bserveur.com'),
          'http://serveur.com');
    });
  });

  group('sanitizeXtreamServer', () {
    test('réduit un lien get.php complet au vrai serveur', () {
      expect(
        SourceLinkUtils.sanitizeXtreamServer(
            'http://serveur.com:8080/get.php?username=X&password=Y&type=m3u_plus'),
        'http://serveur.com:8080',
      );
    });

    test('réduit player_api.php / panel_api.php / portal.php', () {
      expect(
        SourceLinkUtils.sanitizeXtreamServer(
            'http://s.com:8080/player_api.php?username=a&password=b'),
        'http://s.com:8080',
      );
      expect(SourceLinkUtils.sanitizeXtreamServer('http://s.com/panel_api.php'),
          'http://s.com');
      expect(SourceLinkUtils.sanitizeXtreamServer('http://s.com/portal.php'),
          'http://s.com');
    });

    test('retire le chemin portail /c/ mais garde un vrai sous-chemin', () {
      expect(SourceLinkUtils.sanitizeXtreamServer('http://s.com:8080/c/'),
          'http://s.com:8080');
      // Panel installé sous un sous-chemin : le sous-chemin est conservé.
      expect(
        SourceLinkUtils.sanitizeXtreamServer(
            'http://s.com/xtream/get.php?username=a&password=b'),
        'http://s.com/xtream',
      );
    });

    test('entrée déjà propre → inchangée (slash final retiré)', () {
      expect(SourceLinkUtils.sanitizeXtreamServer('http://s.com:8080'),
          'http://s.com:8080');
      expect(SourceLinkUtils.sanitizeXtreamServer('http://s.com:8080/'),
          'http://s.com:8080');
    });

    test('complète le schéma manquant au passage', () {
      expect(SourceLinkUtils.sanitizeXtreamServer('s.com:8080/get.php?username=a&password=b'),
          'http://s.com:8080');
    });
  });

  group('tryExtractXtreamCredentials', () {
    test('extrait serveur + identifiants d\'un lien complet', () {
      final ({String server, String username, String password})? r =
          SourceLinkUtils.tryExtractXtreamCredentials(
              'http://serveur.com:8080/get.php?username=user1&password=pass1&type=m3u_plus');
      expect(r, isNotNull);
      expect(r!.server, 'http://serveur.com:8080');
      expect(r.username, 'user1');
      expect(r.password, 'pass1');
    });

    test('conserve le sous-chemin réel du panel', () {
      final ({String server, String username, String password})? r =
          SourceLinkUtils.tryExtractXtreamCredentials(
              'https://s.com/xtream/get.php?username=u&password=p');
      expect(r!.server, 'https://s.com/xtream');
    });

    test('renvoie null pour un lien sans identifiants', () {
      expect(
        SourceLinkUtils.tryExtractXtreamCredentials('http://s.com:8080'),
        isNull,
      );
      expect(SourceLinkUtils.tryExtractXtreamCredentials('pas un lien'),
          isNull);
    });
  });

  group('isAllowedSourceUrl (validation anti-injection)', () {
    test('accepte http et https (schéma explicite ou complété)', () {
      expect(SourceLinkUtils.isAllowedSourceUrl('http://s.com:8080'), isTrue);
      expect(SourceLinkUtils.isAllowedSourceUrl('https://s.com/list.m3u'),
          isTrue);
      // Sans schéma → complété en http:// → accepté.
      expect(SourceLinkUtils.isAllowedSourceUrl('s.com:8080/get.php'), isTrue);
    });

    test('refuse les schémas dangereux (file, gopher, javascript, data)', () {
      expect(SourceLinkUtils.isAllowedSourceUrl('file:///etc/passwd'), isFalse);
      expect(SourceLinkUtils.isAllowedSourceUrl('gopher://h/1'), isFalse);
      expect(
          SourceLinkUtils.isAllowedSourceUrl('javascript:alert(1)'), isFalse);
      expect(SourceLinkUtils.isAllowedSourceUrl('data:text/plain,hi'), isFalse);
    });

    test('refuse une entrée vide ou sans hôte', () {
      expect(SourceLinkUtils.isAllowedSourceUrl(''), isFalse);
      expect(SourceLinkUtils.isAllowedSourceUrl('http://'), isFalse);
    });
  });
}
