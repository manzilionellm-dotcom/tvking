// =========================================================
//  source_input_normalizer_test.dart — Toutes les fautes réparées
// =========================================================
//  Fonctions PURES → tests instantanés, sans réseau ni Flutter. Chaque
//  groupe couvre une famille de fautes réelles observées à la
//  télécommande : espaces, virgules, schémas cassés, casse, ports sales,
//  et l'AUTO-DÉTECTION (extraction Xtream depuis get.php, m3u vs xtream).
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/source_input_normalizer.dart';

void main() {
  group('normalizeUrl — espaces et retours à la ligne', () {
    test('retire les espaces PARTOUT (jamais légitimes dans une URL)', () {
      final NormalizedInput n =
          SourceInputNormalizer.normalizeUrl(' http://ser ver.com /list.m3u ');
      expect(n.value, 'http://server.com/list.m3u');
      expect(n.fixes, contains('espaces retirés'));
    });

    test('retire les retours à la ligne (lien collé plié sur 2 lignes)', () {
      final NormalizedInput n = SourceInputNormalizer.normalizeUrl(
          'http://serveur.com:8080/get.php?user\nname=abc');
      expect(n.value, 'http://serveur.com:8080/get.php?username=abc');
    });

    test('espace avant le port retiré', () {
      final NormalizedInput n =
          SourceInputNormalizer.normalizeUrl('http://serveur.com :8080');
      expect(n.value, 'http://serveur.com:8080');
    });

    test('entrée vide → vide, sans correction', () {
      final NormalizedInput n = SourceInputNormalizer.normalizeUrl('   ');
      expect(n.value, '');
      expect(n.wasFixed, isFalse);
    });
  });

  group('normalizeUrl — schémas cassés', () {
    test('htp:// → http://', () {
      expect(SourceInputNormalizer.normalizeUrl('htp://serveur.com').value,
          'http://serveur.com');
    });

    test('http:/ (un seul slash) → http://', () {
      expect(SourceInputNormalizer.normalizeUrl('http:/serveur.com').value,
          'http://serveur.com');
    });

    test('http// (deux-points oubliés) → http://', () {
      expect(SourceInputNormalizer.normalizeUrl('http//serveur.com').value,
          'http://serveur.com');
    });

    test('https:/ → https:// (le s est conservé)', () {
      expect(SourceInputNormalizer.normalizeUrl('https:/serveur.com').value,
          'https://serveur.com');
    });

    test('ttp:// (h mangé) → http://', () {
      expect(SourceInputNormalizer.normalizeUrl('ttp://serveur.com').value,
          'http://serveur.com');
    });

    test('Http:// (casse) → http://, sans le signaler comme une faute', () {
      final NormalizedInput n =
          SourceInputNormalizer.normalizeUrl('Http://serveur.com');
      expect(n.value, 'http://serveur.com');
    });

    test('un schéma cassé est LISTÉ dans les corrections', () {
      final NormalizedInput n =
          SourceInputNormalizer.normalizeUrl('htp://serveur.com');
      expect(n.fixes.join(' '), contains('htp://'));
      expect(n.fixes.join(' '), contains('http://'));
    });

    test('schéma absent → http:// ajouté en silence (pas une faute)', () {
      final NormalizedInput n =
          SourceInputNormalizer.normalizeUrl('serveur.com:8080');
      expect(n.value, 'http://serveur.com:8080');
      expect(n.wasFixed, isFalse);
    });

    test('lien protocole-relatif //serveur.com → http://serveur.com', () {
      expect(SourceInputNormalizer.normalizeUrl('//serveur.com').value,
          'http://serveur.com');
    });

    test('un autre schéma valide (rtmp, ftp) n\'est JAMAIS touché', () {
      expect(SourceInputNormalizer.normalizeUrl('rtmp://serveur.com/live').value,
          'rtmp://serveur.com/live');
      expect(SourceInputNormalizer.normalizeUrl('ftp://serveur.com').value,
          'ftp://serveur.com');
    });

    test('http:// correct → identique, aucune correction', () {
      final NormalizedInput n =
          SourceInputNormalizer.normalizeUrl('http://serveur.com:8080');
      expect(n.value, 'http://serveur.com:8080');
      expect(n.wasFixed, isFalse);
    });
  });

  group('normalizeUrl — hôte', () {
    test('virgules → points (server,com)', () {
      final NormalizedInput n =
          SourceInputNormalizer.normalizeUrl('server,com:8080');
      expect(n.value, 'http://server.com:8080');
      expect(n.fixes.join(' '), contains('server,com'));
      expect(n.fixes.join(' '), contains('server.com'));
    });

    test('points doublés → un seul (serveur..com)', () {
      expect(SourceInputNormalizer.normalizeUrl('http://serveur..com').value,
          'http://serveur.com');
    });

    test('point final de l\'hôte retiré', () {
      expect(SourceInputNormalizer.normalizeUrl('http://serveur.com.').value,
          'http://serveur.com');
    });

    test('hôte mis en minuscules', () {
      expect(SourceInputNormalizer.normalizeUrl('HTTP://SERVEUR.COM:8080').value,
          'http://serveur.com:8080');
    });

    test('casse du CHEMIN et de la QUERY préservée (usernames Xtream)', () {
      final NormalizedInput n = SourceInputNormalizer.normalizeUrl(
          'HTTP://Serveur.COM/get.php?username=JeanDupont&password=AbC123');
      expect(n.value,
          'http://serveur.com/get.php?username=JeanDupont&password=AbC123');
    });
  });

  group('normalizeUrl — port', () {
    test(':8080. (point parasite) → :8080', () {
      final NormalizedInput n =
          SourceInputNormalizer.normalizeUrl('http://serveur.com:8080.');
      expect(n.value, 'http://serveur.com:8080');
    });

    test('deux-points sans port derrière → retirés', () {
      expect(SourceInputNormalizer.normalizeUrl('http://serveur.com:').value,
          'http://serveur.com');
    });

    test('le port ne mange pas le chemin', () {
      expect(
          SourceInputNormalizer
              .normalizeUrl('serveur.com:8080/get.php?username=a&password=b')
              .value,
          'http://serveur.com:8080/get.php?username=a&password=b');
    });
  });

  group('analyze — auto-détection du type', () {
    test('lien get.php complet → xtream, 3 champs extraits', () {
      final SourceInputAnalysis a = SourceInputNormalizer.analyze(
          'http://serveur.com:8080/get.php?username=Jean&password=Sec123'
          '&type=m3u_plus');
      expect(a.kind, SourceInputKind.xtream);
      expect(a.hasXtreamCredentials, isTrue);
      expect(a.xtreamServer, 'http://serveur.com:8080');
      expect(a.xtreamUsername, 'Jean'); // casse préservée
      expect(a.xtreamPassword, 'Sec123');
    });

    test('lien get.php PLEIN de fautes → réparé PUIS extrait', () {
      final SourceInputAnalysis a = SourceInputNormalizer.analyze(
          'htp://serveur,com:8080/get.php?username=Jean&password=Sec123');
      expect(a.kind, SourceInputKind.xtream);
      expect(a.xtreamServer, 'http://serveur.com:8080');
      expect(a.xtreamUsername, 'Jean');
      expect(a.fixes, isNotEmpty);
    });

    test('.m3u → m3u', () {
      final SourceInputAnalysis a =
          SourceInputNormalizer.analyze('serveur.com/tv/liste.m3u');
      expect(a.kind, SourceInputKind.m3u);
      expect(a.url, 'http://serveur.com/tv/liste.m3u');
    });

    test('.m3u8 → m3u (casse du suffixe ignorée)', () {
      final SourceInputAnalysis a =
          SourceInputNormalizer.analyze('http://serveur.com/Liste.M3U8');
      expect(a.kind, SourceInputKind.m3u);
    });

    test('get.php SANS identifiants → xtream, serveur seul pré-rempli', () {
      final SourceInputAnalysis a =
          SourceInputNormalizer.analyze('http://serveur.com:8080/get.php');
      expect(a.kind, SourceInputKind.xtream);
      expect(a.xtreamServer, 'http://serveur.com:8080');
      expect(a.hasXtreamCredentials, isFalse);
    });

    test('player_api.php → xtream (portail)', () {
      final SourceInputAnalysis a = SourceInputNormalizer
          .analyze('http://serveur.com:8080/player_api.php');
      expect(a.kind, SourceInputKind.xtream);
      expect(a.xtreamServer, 'http://serveur.com:8080');
    });

    test('portail /c (MAG/Stalker) → xtream, chemin portail retiré', () {
      final SourceInputAnalysis a =
          SourceInputNormalizer.analyze('http://serveur.com:8080/c/');
      expect(a.kind, SourceInputKind.xtream);
      expect(a.xtreamServer, 'http://serveur.com:8080');
    });

    test('domaine seul → unknown (l\'écran posera la question)', () {
      final SourceInputAnalysis a =
          SourceInputNormalizer.analyze('serveur.com:8080');
      expect(a.kind, SourceInputKind.unknown);
      expect(a.url, 'http://serveur.com:8080');
    });

    test('entrée vide → unknown, url vide', () {
      final SourceInputAnalysis a = SourceInputNormalizer.analyze('  ');
      expect(a.kind, SourceInputKind.unknown);
      expect(a.url, '');
    });

    test('les corrections remontent jusqu\'à l\'analyse (confiance)', () {
      final SourceInputAnalysis a =
          SourceInputNormalizer.analyze('server,com/liste.m3u');
      expect(a.kind, SourceInputKind.m3u);
      expect(a.fixes.join(' '), contains('server,com'));
    });
  });
}
