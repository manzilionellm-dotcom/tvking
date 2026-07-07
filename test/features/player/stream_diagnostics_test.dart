// =========================================================
//  stream_diagnostics_test.dart — Boîte noire de lecture
// =========================================================
//  Deux choses à garantir :
//    1. Le masquage des identifiants Xtream dans les URLs (un
//       screenshot / rapport copié du debug ne doit JAMAIS fuiter
//       le compte de l'utilisateur).
//    2. Le cycle de session : beginSession réinitialise bien
//       l'instantané, les enregistrements remplissent les bons
//       champs, le journal est borné.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/stream_diagnostics.dart';

void main() {
  group('StreamDiagnostics.maskCredentials', () {
    test('masque user/pass du schéma Xtream live avec préfixe', () {
      expect(
        StreamDiagnostics.maskCredentials(
            'http://host.tv:8080/live/monuser/monpass/12345.ts'),
        'http://host.tv:8080/live/%E2%80%A2%E2%80%A2%E2%80%A2/'
        '%E2%80%A2%E2%80%A2%E2%80%A2/12345.ts',
      );
    });

    test('masque user/pass du schéma court (sans /live/)', () {
      final String masked = StreamDiagnostics.maskCredentials(
          'http://host.tv/monuser/monpass/99.m3u8');
      expect(masked, isNot(contains('monuser')));
      expect(masked, isNot(contains('monpass')));
      expect(masked, endsWith('/99.m3u8'));
    });

    test('masque les paramètres de query sensibles, garde les autres', () {
      final String masked = StreamDiagnostics.maskCredentials(
          'http://host.tv/player_api.php?username=u1&password=p1&action=get');
      expect(masked, isNot(contains('u1')));
      expect(masked, isNot(contains('p1')));
      expect(masked, contains('action=get'));
    });

    test('URL sans schéma Xtream reconnaissable : inchangée', () {
      expect(
        StreamDiagnostics.maskCredentials('http://cdn.tv/stream.m3u8'),
        'http://cdn.tv/stream.m3u8',
      );
    });

    test('entrée non parsable : renvoyée telle quelle (pas de crash)', () {
      expect(StreamDiagnostics.maskCredentials('::pas une url::'),
          '::pas une url::');
    });
  });

  group('StreamDiagnostics — cycle de session', () {
    test('beginSession réinitialise l\'instantané mais garde le journal', () {
      final StreamDiagnostics d = StreamDiagnostics.instance;
      d.beginSession(url: 'http://a/1.ts', userAgent: 'UA-1', title: 'Un');
      d.recordHttp(status: 200, mime: 'video/mp2t');
      d.recordCodecs(video: 'h264', audio: 'aac', resolution: '1920×1080');
      d.recordPlayerError('Failed to open stream');

      expect(d.httpStatus, 200);
      expect(d.videoCodec, 'h264');
      expect(d.lastPlayerError, 'Failed to open stream');
      final int journalAvant = d.events.length;

      d.beginSession(url: 'http://b/2.ts', userAgent: 'UA-2');
      expect(d.httpStatus, isNull);
      expect(d.videoCodec, isNull);
      expect(d.lastPlayerError, isNull);
      expect(d.streamUrl, 'http://b/2.ts');
      expect(d.userAgent, 'UA-2');
      // Le journal n'est pas vidé (l'événement d'ouverture s'y ajoute).
      expect(d.events.length, journalAvant + 1);
    });

    test('un warning ne remplace pas la dernière erreur fatale', () {
      final StreamDiagnostics d = StreamDiagnostics.instance;
      d.beginSession(url: 'http://c/3.ts', userAgent: 'UA');
      d.recordPlayerError('erreur fatale', fatal: true);
      d.recordPlayerError('demuxer warning', fatal: false);
      expect(d.lastPlayerError, 'erreur fatale');
    });

    test('le rapport masque l\'URL et contient les champs clés', () {
      final StreamDiagnostics d = StreamDiagnostics.instance;
      d.beginSession(
        url: 'http://host.tv/live/secretuser/secretpass/7.ts',
        userAgent: 'VLC/3.0.18 LibVLC/3.0.18',
        title: 'Chaîne 7',
      );
      d.recordHttp(status: 403);
      final String report = d.buildReport();
      expect(report, isNot(contains('secretuser')));
      expect(report, isNot(contains('secretpass')));
      expect(report, contains('VLC/3.0.18'));
      expect(report, contains('403'));
      expect(report, contains('Chaîne 7'));
    });
  });
}
