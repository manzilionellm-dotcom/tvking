import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/subscription/data/activation_hint.dart';
import 'package:tv_king/features/subscription/data/source_privacy.dart';

void main() {
  test('une URL M3U ne part qu\'avec l\'hôte', () {
    final String server = heartbeatServerField(
      xtream: false,
      serverOrUrl:
          'http://user:secret@cdn.exemple.test:8080/get.php?username=u&password=p',
    );
    expect(server, 'cdn.exemple.test:8080');
    expect(server.contains('secret'), isFalse);
    expect(server.contains('password'), isFalse);
  });

  test('Xtream : hôte seul, pas le mot de passe', () {
    expect(
      heartbeatServerField(
        xtream: true,
        serverOrUrl: 'http://user:secret@panel.exemple.test:80',
      ),
      'panel.exemple.test',
    );
  });

  test('les trois messages d\'activation', () {
    expect(activationHintFr('offline'), contains('Pas de réseau'));
    expect(activationHintFr('expired'), contains('pas activé'));
    expect(activationHintFr('frozen'), contains('gelé'));
    expect(activationHintFr('banned'), contains('bloqué'));
    expect(activationHintFr(null), isNull);
  });
}
