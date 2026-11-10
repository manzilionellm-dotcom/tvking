import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_session_diagnostic.dart';

void main() {
  test('URL Xtream, compte HTTP et query encodée ne partagent aucun secret',
      () {
    for (final url in <String>[
      'https://account:secret@provider.invalid/live/username/password/123.ts?token=bearer',
      'http://provider.invalid/username/password/123.ts',
      'https://provider.invalid/get.php?username=username&password=password',
      'https://provider.invalid/cs/dXNlcm5hbWU6cGFzc3dvcmQ.ts',
      'https://proxy.invalid/cast-proxy?u=https%3A%2F%2Fprovider.invalid%2Flive%2Fusername%2Fpassword%2F123.ts&t=signature',
    ]) {
      final safe = redactStreamUrl(url);
      for (final secret in <String>[
        'secret',
        'account',
        '/username/',
        '/password/',
        '=username',
        '=password',
        'bearer',
        'signature',
        'dXNlcm5hbWU6cGFzc3dvcmQ'
      ]) {
        expect(safe, isNot(contains(secret)), reason: safe);
      }
      expect(safe, contains('.invalid'));
    }
  });

  test('exception et URL doublement encodée sont filtrées avant export', () {
    const url =
        'https://provider.invalid/live/mylogin/mypassword/12.ts?token=mytoken';
    final raw =
        'HttpException: ${Uri.encodeComponent(Uri.encodeComponent(url))} '
        'password=mypassword Authorization: Bearer mybearer';
    final safe = redactCastText(raw);
    for (final secret in <String>[
      'mylogin',
      'mypassword',
      'mytoken',
      'mybearer'
    ]) {
      expect(safe, isNot(contains(secret)), reason: safe);
    }
  });

  test('erreur de tentative et erreur probe filtrées dans JSON public', () {
    const url = 'https://provider.invalid/usersecret/passsecret/12.ts';
    final attempt = AttemptResult(
        strategyIndex: 0,
        strategyName: 'direct',
        urlKind: 'direct',
        metadataMode: 'none',
        durationMs: 1,
        success: false,
        errorMessage: 'HttpException $url');
    final probe = ProbeSummary(
        success: false,
        finalUrl: url,
        redirectCount: 0,
        timeToFirstByteMs: 0,
        errorReason: 'SocketException $url');
    for (final value in <String>[
      attempt.toJson().toString(),
      probe.toJson().toString()
    ]) {
      expect(value, isNot(contains('usersecret')));
      expect(value, isNot(contains('passsecret')));
    }
  });
}
