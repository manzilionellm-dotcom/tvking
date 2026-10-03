// =========================================================
//  home_source_link_test.dart — QR d'accueil, sans flux en dur
// =========================================================
//  Le lien ouvre la page déjà hébergée. Les adresses ici sont
//  bidons (exemple.invalid). Aucun mot de passe, aucune playlist.
// =========================================================

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/tv/data/home_source_pair.dart';
import 'package:tv_king/features/tv/domain/home_source_link.dart';
import 'package:tv_king/features/tv/presentation/tv_phone_source_qr.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  const String base = 'https://exemple.invalid';
  const String mac = 'mk:aa:bb:cc:dd:11';
  const String phrase =
      'Cette application ne vend aucune chaîne. Ajoutez votre propre abonnement.';

  test('le QR pointe vers la page existante, pas vers un flux', () {
    final String? url = homeSourcePortalUrl(
      baseUrl: '$base/',
      mac: mac,
      pair: 'k7mnpq',
    );
    expect(
      url,
      'https://exemple.invalid/mon-espace#mac=MK:AA:BB:CC:DD:11&pair=K7MNPQ',
    );
    expect(url, isNot(contains('get.php')));
    expect(url, isNot(contains('.m3u')));
    expect(url, isNot(contains('%3A')));

    expect(
      homeSourcePortalUrl(baseUrl: base, mac: mac),
      'https://exemple.invalid/mon-espace#mac=MK:AA:BB:CC:DD:11',
    );
    expect(homeSourcePortalUrl(baseUrl: 'ftp://exemple.invalid', mac: mac), isNull);
    expect(homeSourcePortalUrl(baseUrl: base, mac: 'pas-une-mac'), isNull);
    expect(homeSourcePairCodeOk('OOOOOO'), isFalse);
    expect(homeSourcePairCodeOk('K7MNPQ'), isTrue);

    final String minted = mintHomeSourcePairCode(Random(1));
    expect(minted.length, kHomeSourcePairLength);
    expect(homeSourcePairCodeOk(minted), isTrue);
  });

  test('code accepté seulement si le Worker répond oui', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final HomeSourceLink? yes = await publishHomeSourceLink(
      mac: mac,
      baseUrl: base,
      random: Random(2),
      post: (Uri uri, Map<String, String> headers, String body) async {
        expect(uri.path, '/api/source-pair');
        expect(body, contains('MK:AA:BB:CC:DD:11'));
        expect(headers['Content-Type'], 'application/json');
        return 200;
      },
    );
    expect(yes, isNotNull);
    expect(yes!.code, isNotNull);
    expect(yes.url, contains('pair=${yes.code}'));
    expect(yes.url, isNot(contains('.m3u')));

    final HomeSourceLink? no = await publishHomeSourceLink(
      mac: mac,
      baseUrl: base,
      random: Random(2),
      post: (Uri uri, Map<String, String> headers, String body) async => 401,
    );
    expect(no!.code, isNull);
    expect(no.url, isNot(contains('pair=')));
    expect(no.url, contains('#mac=MK:AA:BB:CC:DD:11'));

    final HomeSourceLink? down = await publishHomeSourceLink(
      mac: mac,
      baseUrl: base,
      post: (Uri uri, Map<String, String> headers, String body) async {
        throw Exception('réseau coupé');
      },
    );
    expect(down!.url, contains('/mon-espace#mac='));
    expect(down.code, isNull);
  });

  test('chaque langue a la phrase et le mode d\'emploi', () {
    final Directory dir = Directory('lib/l10n');
    final List<File> files = dir
        .listSync()
        .whereType<File>()
        .where((File f) => f.path.endsWith('.arb'))
        .toList();
    expect(files.length, greaterThanOrEqualTo(16));
    for (final File file in files) {
      final String text = file.readAsStringSync();
      expect(text, contains('"tvNoChannelsSold"'), reason: file.path);
      expect(text, contains('"tvScanSourceHelp"'), reason: file.path);
      expect(text, contains('"tvScanSourceCode"'), reason: file.path);
      expect(text, contains('{code}'), reason: file.path);
    }
    expect(File('lib/l10n/app_fr.arb').readAsStringSync(), contains(phrase));
  });

  testWidgets('l\'accueil vide affiche la phrase et le QR', (WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const String url =
        'https://exemple.invalid/mon-espace#mac=MK:AA:BB:CC:DD:11&pair=K7MNPQ';
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: TvOwnSourceQr(url: url, code: 'K7MNPQ'),
      ),
    ));
    await tester.pump();

    expect(find.text(phrase), findsOneWidget);
    expect(find.textContaining('appareil photo'), findsOneWidget);
    expect(find.text('Code : K7MNPQ'), findsOneWidget);
    // Le carré est bien dessiné. Son contenu est l'adresse du widget
    // (QrImageView garde cette chaîne privée) : on vérifie donc l'adresse
    // portée par l'écran, qui est celle passée au QR.
    final TvOwnSourceQr panel =
        tester.widget<TvOwnSourceQr>(find.byType(TvOwnSourceQr));
    expect(panel.url, url);
    expect(panel.url, isNot(contains('get.php')));
    expect(panel.url, isNot(contains('.m3u')));
    expect(find.byType(QrImageView), findsOneWidget);
  });
}
