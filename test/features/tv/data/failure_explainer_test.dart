// =========================================================
//  failure_explainer_test.dart — La table du POURQUOI est un CONTRAT
// =========================================================
//  La Boîte noire doit « travailler même dix ans » : on verrouille par des
//  tests (1) que TOUS les codes ExoPlayer/Media3 courants ont un verdict
//  humain, (2) qu'un code INCONNU (version future) tombe sur le verdict
//  générique propre au lieu de casser, (3) que le repli numérique et
//  l'extraction du code HTTP restent tolérants. Fonctions pures : aucun
//  mock, aucune I/O.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/data/failure_explainer.dart';

void main() {
  group('extractHttpStatus — repêchage tolérant du code HTTP', () {
    test('trouve un 456 dans le message de cause Media3', () {
      expect(extractHttpStatus('Response code: 456'), 456);
    });
    test('trouve un 403 même dans une formulation différente', () {
      // Le texte change entre versions ExoPlayer — seul le NOMBRE compte.
      expect(extractHttpStatus('Erreur serveur HTTP 403 interdite'), 403);
    });
    test('null si aucun nombre 4xx/5xx', () {
      expect(extractHttpStatus('Unable to connect'), isNull);
      expect(extractHttpStatus('timeout after 30000 ms'), isNull);
      expect(extractHttpStatus(null), isNull);
      expect(extractHttpStatus(''), isNull);
    });
    test('ignore les nombres hors plage HTTP (ports, tailles)', () {
      expect(extractHttpStatus('port 8080 refused, 30000 ms'), isNull);
    });
  });

  group('explainPlaybackFailure — codes réseau (IO)', () {
    test('CONNECTION_FAILED → la box ne joint pas le serveur', () {
      final PlaybackFailureExplanation e = explainPlaybackFailure(
          errorCodeName: 'ERROR_CODE_IO_NETWORK_CONNECTION_FAILED');
      expect(e.why, contains('joindre le serveur'));
    });
    test('CONNECTION_FAILED + DNS KO → internet/DNS en cause', () {
      final PlaybackFailureExplanation e = explainPlaybackFailure(
        errorCodeName: 'ERROR_CODE_IO_NETWORK_CONNECTION_FAILED',
        dnsFailed: true,
      );
      expect(e.why, contains('DNS'));
    });
    test('CONNECTION_TIMEOUT après lecture OK → serveur lent/saturé', () {
      final PlaybackFailureExplanation e = explainPlaybackFailure(
        errorCodeName: 'ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT',
        everShownFrame: true,
      );
      expect(e.why, contains('saturé'));
    });
    test('chaque code IO connu a un verdict spécifique (pas le générique)',
        () {
      const List<String> codes = <String>[
        'ERROR_CODE_IO_UNSPECIFIED',
        'ERROR_CODE_IO_NETWORK_CONNECTION_FAILED',
        'ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT',
        'ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE',
        'ERROR_CODE_IO_BAD_HTTP_STATUS',
        'ERROR_CODE_IO_FILE_NOT_FOUND',
        'ERROR_CODE_IO_NO_PERMISSION',
        'ERROR_CODE_IO_CLEARTEXT_NOT_PERMITTED',
        'ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE',
      ];
      for (final String c in codes) {
        final PlaybackFailureExplanation e =
            explainPlaybackFailure(errorCodeName: c);
        expect(e.why, isNot(contains('Erreur du lecteur')),
            reason: '$c doit avoir son propre verdict');
        expect(e.advice, isNotEmpty, reason: '$c doit avoir un conseil');
      }
    });
  });

  group('explainPlaybackFailure — refus HTTP (BAD_HTTP_STATUS)', () {
    PlaybackFailureExplanation forStatus(int s) => explainPlaybackFailure(
        errorCodeName: 'ERROR_CODE_IO_BAD_HTTP_STATUS',
        cause: 'Response code: $s');

    test('456/458 → limite d\'écrans simultanés', () {
      expect(forStatus(456).why, contains('nombre d\'écrans'));
      expect(forStatus(458).why, contains('nombre d\'écrans'));
    });
    test('403/451 → blocage fournisseur/pays, VPN peut aider', () {
      expect(forStatus(403).why, contains('bloque'));
      expect(forStatus(403).advice, contains('VPN'));
      expect(forStatus(451).why, contains('bloque'));
    });
    test('401 → identifiants refusés', () {
      expect(forStatus(401).why, contains('identifiants'));
    });
    test('404 → chaîne disparue chez le fournisseur', () {
      expect(forStatus(404).why, contains('existe plus'));
    });
    test('429 → trop de demandes', () {
      expect(forStatus(429).why, contains('429'));
    });
    test('5xx → serveur du fournisseur en panne', () {
      expect(forStatus(500).why, contains('panne'));
      expect(forStatus(503).why, contains('panne'));
    });
    test('statut HTTP passé en paramètre PRIME sur la cause', () {
      final PlaybackFailureExplanation e = explainPlaybackFailure(
        errorCodeName: 'ERROR_CODE_IO_BAD_HTTP_STATUS',
        cause: 'Response code: 500',
        httpStatus: 456,
      );
      expect(e.why, contains('nombre d\'écrans'));
    });
    test('cause illisible → verdict propre, jamais de crash', () {
      final PlaybackFailureExplanation e = explainPlaybackFailure(
          errorCodeName: 'ERROR_CODE_IO_BAD_HTTP_STATUS',
          cause: 'Source error');
      expect(e.why, contains('refusé'));
    });
  });

  group('explainPlaybackFailure — flux abîmé / format (PARSING)', () {
    test('MALFORMED → flux abîmé côté fournisseur', () {
      for (final String c in <String>[
        'ERROR_CODE_PARSING_CONTAINER_MALFORMED',
        'ERROR_CODE_PARSING_MANIFEST_MALFORMED',
      ]) {
        expect(explainPlaybackFailure(errorCodeName: c).why,
            contains('abîmé'));
      }
    });
    test('UNSUPPORTED → format non géré', () {
      for (final String c in <String>[
        'ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED',
        'ERROR_CODE_PARSING_MANIFEST_UNSUPPORTED',
      ]) {
        expect(explainPlaybackFailure(errorCodeName: c).why,
            contains('pas géré'));
      }
    });
  });

  group('explainPlaybackFailure — décodage (la BOX ne suit pas)', () {
    test('DECODER/DECODING → codec non supporté par la box', () {
      for (final String c in <String>[
        'ERROR_CODE_DECODER_INIT_FAILED',
        'ERROR_CODE_DECODER_QUERY_FAILED',
        'ERROR_CODE_DECODING_FAILED',
        'ERROR_CODE_DECODING_FORMAT_UNSUPPORTED',
      ]) {
        expect(explainPlaybackFailure(errorCodeName: c).why,
            contains('décoder'),
            reason: c);
      }
    });
    test('EXCEEDS_CAPABILITIES → chaîne trop lourde (4K sur box 1080p)', () {
      final PlaybackFailureExplanation e = explainPlaybackFailure(
          errorCodeName: 'ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES');
      expect(e.why, contains('trop lourde'));
    });
  });

  group('explainPlaybackFailure — audio, live, DRM, génériques Media3', () {
    test('AUDIO_TRACK → sortie audio', () {
      for (final String c in <String>[
        'ERROR_CODE_AUDIO_TRACK_INIT_FAILED',
        'ERROR_CODE_AUDIO_TRACK_WRITE_FAILED',
      ]) {
        expect(
            explainPlaybackFailure(errorCodeName: c).why, contains('audio'));
      }
    });
    test('BEHIND_LIVE_WINDOW → le direct a décroché, l\'app se recale', () {
      final PlaybackFailureExplanation e = explainPlaybackFailure(
          errorCodeName: 'ERROR_CODE_BEHIND_LIVE_WINDOW');
      expect(e.why, contains('décroché'));
      expect(e.advice, contains('recale'));
    });
    test('DRM (toute la famille, même un code futur) → chaîne protégée', () {
      expect(
          explainPlaybackFailure(
                  errorCodeName: 'ERROR_CODE_DRM_LICENSE_ACQUISITION_FAILED')
              .why,
          contains('protégée'));
      expect(
          explainPlaybackFailure(errorCodeName: 'ERROR_CODE_DRM_FUTUR_2036')
              .why,
          contains('protégée'));
    });
    test('TIMEOUT / REMOTE_ERROR / FAILED_RUNTIME_CHECK couverts', () {
      for (final String c in <String>[
        'ERROR_CODE_TIMEOUT',
        'ERROR_CODE_REMOTE_ERROR',
        'ERROR_CODE_FAILED_RUNTIME_CHECK',
      ]) {
        final PlaybackFailureExplanation e =
            explainPlaybackFailure(errorCodeName: c);
        expect(e.why, isNot(contains('Erreur du lecteur')), reason: c);
      }
    });
  });

  group('explainPlaybackFailure — DIX ANS : codes inconnus/futurs', () {
    test('code totalement inconnu → verdict générique AVEC le code brut', () {
      final PlaybackFailureExplanation e = explainPlaybackFailure(
          errorCodeName: 'ERROR_CODE_QUANTUM_FLUX_2036');
      expect(e.why, contains('ERROR_CODE_QUANTUM_FLUX_2036'));
      expect(e.advice, contains('support'));
    });
    test('code IO futur inconnu → reste classé « réseau » par le préfixe', () {
      final PlaybackFailureExplanation e = explainPlaybackFailure(
          errorCodeName: 'ERROR_CODE_IO_FUTURE_THING');
      expect(e.why, contains('réseau'));
    });
    test('nom absent mais code numérique connu → même verdict que le nom', () {
      final PlaybackFailureExplanation byName = explainPlaybackFailure(
          errorCodeName: 'ERROR_CODE_DECODING_FAILED');
      final PlaybackFailureExplanation byCode =
          explainPlaybackFailure(errorCode: 4003);
      expect(byCode.why, byName.why);
    });
    test('code numérique futur → classé par PLAGE Media3 (contractuelle)',
        () {
      expect(explainPlaybackFailure(errorCode: 2099).why, contains('réseau'));
      expect(explainPlaybackFailure(errorCode: 4099).why,
          contains('décoder'));
      expect(explainPlaybackFailure(errorCode: 6099).why,
          contains('protégée'));
    });
    test('code numérique hors de toute plage → générique avec le code', () {
      final PlaybackFailureExplanation e =
          explainPlaybackFailure(errorCode: 99999);
      expect(e.why, contains('CODE_99999'));
    });
    test('aucun code, jamais d\'image → source vide/bloquée', () {
      final PlaybackFailureExplanation e = explainPlaybackFailure();
      expect(e.why, contains('jamais démarré'));
    });
    test('aucun code, coupure après lecture → serveur instable', () {
      final PlaybackFailureExplanation e =
          explainPlaybackFailure(everShownFrame: true);
      expect(e.why, contains('coupé en cours de lecture'));
    });
  });

  group('supportCode — code court lisible au téléphone', () {
    test('6 caractères, déterministe (même échec + même build)', () {
      final String a = supportCode(
          errorCodeName: 'ERROR_CODE_IO_BAD_HTTP_STATUS',
          errorCode: 2004,
          build: '42');
      final String b = supportCode(
          errorCodeName: 'ERROR_CODE_IO_BAD_HTTP_STATUS',
          errorCode: 2004,
          build: '42');
      expect(a, b);
      expect(a.length, 6);
    });
    test('change avec le code d\'erreur ou le build', () {
      final String base = supportCode(
          errorCodeName: 'ERROR_CODE_TIMEOUT', errorCode: 1003, build: '42');
      expect(
          supportCode(
              errorCodeName: 'ERROR_CODE_TIMEOUT',
              errorCode: 1003,
              build: '43'),
          isNot(base));
    });
    test('tolère l\'absence totale d\'échec (tout null)', () {
      expect(supportCode(build: '7').length, 6);
    });
  });
}
