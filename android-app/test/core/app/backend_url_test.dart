import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/app/build_info.dart';
import 'package:tv_king/features/subscription/data/gold_trial_backend.dart';
import 'package:tv_king/features/subscription/data/subscription_backend.dart';

void main() {
  test(
    'le backend de production utilise api.zuno8k.com par défaut',
    () => expect(kSubscriptionBaseUrl, 'https://api.zuno8k.com'),
    // Un build de staging doit pouvoir conserver sa surcharge explicite.
    skip: const bool.hasEnvironment('BACKEND_URL'),
  );

  test(
    'l\'essai partage le backend et le téléchargement utilise le nouveau domaine',
    () {
      expect(kGoldTrialBaseUrl, kSubscriptionBaseUrl);
      expect(kDownloadUrl, 'https://api.zuno8k.com/vip');
    },
  );

  test('le Dart maintenu à la main ne contient aucun ancien domaine backend', () {
    // Les .arb sont exclus du changement demandé. Leur code généré reste
    // également intact ; les écrans légaux remplacent le domaine au rendu.
    final List<File> sources = Directory('lib')
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((File file) =>
            file.path.endsWith('.dart') &&
            !file.path.replaceAll('\\', '/').startsWith('lib/l10n/generated/'))
        .toList();
    expect(sources, isNotEmpty);

    final List<String> violations = <String>[];
    for (final File file in sources) {
      final String source = file.readAsStringSync();
      for (final String domain in <String>['app.7themotion.com', 'workers.dev']) {
        if (source.contains(domain)) violations.add('${file.path}: $domain');
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
