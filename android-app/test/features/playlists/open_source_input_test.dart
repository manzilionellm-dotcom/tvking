// =========================================================
//  open_source_input_test.dart — Saisie ouverte, sans catalogue
// =========================================================
//  On vérifie les trois façons d'ajouter une source, les phrases
//  françaises, et qu'aucun hôte n'est refusé. Les adresses sont
//  bidons (exemple.invalid). Aucun mot de passe réel.
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/features/playlists/data/default_servers.dart';
import 'package:tv_king/features/playlists/domain/open_source_input.dart';
import 'package:tv_king/features/tv/presentation/tv_add_source_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  test('M3U et M3U8 : avec ou sans identifiants, n\'importe quel hôte', () {
    final OpenSourceParse plain =
        OpenSourceInput.playlistLink('https://fournisseur.invalid/liste.m3u');
    expect(plain.isValid, isTrue);
    expect(plain.draft!.kind, OpenSourceKind.m3u);
    expect(plain.draft!.m3uUrl, 'https://fournisseur.invalid/liste.m3u');

    final OpenSourceParse hls =
        OpenSourceInput.playlistLink('http://autre.invalid/direct.m3u8');
    expect(hls.draft!.kind, OpenSourceKind.m3u);

    // Identifiants dans l'adresse : on les garde, on ne les retire pas.
    final OpenSourceParse withUser = OpenSourceInput.playlistLink(
      'http://demo:jeton@boite.invalid:8080/liste.m3u',
    );
    expect(withUser.isValid, isTrue);
    expect(withUser.draft!.m3uUrl, contains('demo:jeton@'));

    // Schéma oublié : on comprend quand même.
    final OpenSourceParse bare =
        OpenSourceInput.playlistLink('boite.invalid/liste.m3u8');
    expect(bare.draft!.m3uUrl, 'http://boite.invalid/liste.m3u8');
  });

  test('Xtream : trois champs, ou get.php collé dans le serveur', () {
    final OpenSourceParse ok = OpenSourceInput.xtream(
      server: 'panel.invalid:8080',
      username: 'demo',
      password: 'jeton',
    );
    expect(ok.draft!.kind, OpenSourceKind.xtream);
    expect(ok.draft!.serverUrl, 'http://panel.invalid:8080');
    expect(ok.draft!.username, 'demo');
    expect(ok.draft!.password, 'jeton');

    final OpenSourceParse fromLink = OpenSourceInput.xtream(
      server:
          'http://panel.invalid:8080/get.php?username=demo&password=jeton&type=m3u_plus',
      username: '',
      password: '',
    );
    expect(fromLink.draft!.serverUrl, 'http://panel.invalid:8080');
    expect(fromLink.draft!.username, 'demo');
    expect(fromLink.draft!.password, 'jeton');

    final OpenSourceParse missing = OpenSourceInput.xtream(
      server: 'http://panel.invalid',
      username: 'demo',
      password: '',
    );
    expect(missing.isValid, isFalse);
    expect(missing.error, OpenSourceInput.errNeedXtream);
  });

  test('lien lecteur get.php : complet, incomplet, ou simple liste', () {
    final OpenSourceParse player = OpenSourceInput.playerLink(
      'https://lecteur.invalid/get.php?username=demo&password=jeton',
    );
    expect(player.draft!.kind, OpenSourceKind.xtream);
    expect(player.draft!.serverUrl, 'https://lecteur.invalid');
    expect(player.draft!.username, 'demo');

    final OpenSourceParse api = OpenSourceInput.playerLink(
      'http://lecteur.invalid:8000/player_api.php?username=demo&password=jeton',
    );
    expect(api.draft!.serverUrl, 'http://lecteur.invalid:8000');

    final OpenSourceParse incomplete = OpenSourceInput.playerLink(
      'http://lecteur.invalid/get.php?type=m3u_plus',
    );
    expect(incomplete.error, OpenSourceInput.errNeedPlayerCreds);

    // Mauvais onglet : une liste M3U reste acceptée.
    final OpenSourceParse asList =
        OpenSourceInput.playerLink('http://lecteur.invalid/liste.m3u8');
    expect(asList.draft!.kind, OpenSourceKind.m3u);
  });

  test('adresse vide, schéma interdit, deux sources différentes', () {
    expect(OpenSourceInput.playlistLink('   ').error, OpenSourceInput.errNeedUrl);
    expect(
      OpenSourceInput.playlistLink('ftp://fichiers.invalid/liste.m3u').error,
      OpenSourceInput.errBadScheme,
    );

    // Plusieurs sources : chacune est jugée seule, sans liste imposée.
    final OpenSourceParse a =
        OpenSourceInput.playlistLink('http://un.invalid/a.m3u');
    final OpenSourceParse b = OpenSourceInput.xtream(
      server: 'http://deux.invalid',
      username: 'demo',
      password: 'jeton',
    );
    expect(a.draft!.m3uUrl, isNot(b.draft!.serverUrl));
    expect(a.isValid && b.isValid, isTrue);
  });

  test('un serveur déjà enregistré se retrouve, sans être proposé', () {
    const List<DefaultServer> known = <DefaultServer>[
      DefaultServer(
        id: 'ancien',
        label: 'Serveur 1',
        url: 'http://ancien.invalid:8080',
      ),
    ];
    expect(
      urlForRegisteredServer(known, 'ancien'),
      'http://ancien.invalid:8080',
    );
    expect(urlForRegisteredServer(known, 'inconnu'), isNull);
    expect(urlForRegisteredServer(known, '  '), isNull);
  });

  testWidgets('l\'écran TV ne montre pas de liste Serveur 1', (WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(
      locale: Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: TvAddSourceScreen()),
    ));
    await tester.pump();

    expect(find.text('Serveur 1'), findsNothing);
    expect(find.text('Choisis ton serveur'), findsNothing);
    expect(find.text('Ajouter ma source'), findsOneWidget);
    expect(find.text('Lien lecteur'), findsOneWidget);

    // Validation avant tout réseau : phrase française, pas d'appel.
    await tester.tap(find.text('Valider et charger ma liste'));
    await tester.pump();
    expect(find.text(OpenSourceInput.errNeedXtream), findsOneWidget);
  });
}
