// Parcours réels : créer, choisir et alimenter un profil NOVATUBE.
// Les sources de test sont locales à SQLite ; aucune adresse n'est contactée.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/zuno_edition.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/cast/data/cast_platform.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/tv/presentation/tv_add_source_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_profile_picker.dart';
import 'package:tv_king/features/tv/presentation/tv_profiles_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_shell.dart';
import 'package:tv_king/features/tv/presentation/tv_sources_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

final _android = TargetPlatformVariant.only(TargetPlatform.android);
const _launchKey = ValueKey<String>('open-profile-picker');

Future<void> _installTestFonts() async {
  final String? root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) throw StateError('FLUTTER_ROOT nécessaire pour Ahem');
  final ByteData fallback = ByteData.sublistView(
    File('$root/packages/flutter_tools/static/Ahem.ttf').readAsBytesSync(),
  );
  final String? fontDir = Platform.environment['ZUNO_TOUCH_FONT_DIR'];
  if (fontDir != null) {
    final FontLoader icons = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytesSync())));
    await icons.load();
  }
  final Map<String, ByteData> fonts = <String, ByteData>{};
  for (final String family in <String>['Inter', 'Oswald', 'JetBrainsMono']) {
    final File? real = fontDir == null ? null : File('$fontDir/$family.ttf');
    final ByteData bytes = real?.existsSync() == true
        ? ByteData.sublistView(real!.readAsBytesSync())
        : fallback;
    for (final String weight in <String>[
      'Thin',
      'ExtraLight',
      'Light',
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
      'Black',
    ]) {
      fonts['fonts/$family-$weight.ttf'] = bytes;
    }
  }
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMessageHandler('flutter/assets', (ByteData? message) async {
    final String key = utf8.decode(message!.buffer.asUint8List(
      message.offsetInBytes,
      message.lengthInBytes,
    ));
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, Object>{
        for (final String asset in fonts.keys)
          asset: <Map<String, String>>[
            <String, String>{'asset': asset}
          ],
      });
    }
    if (key == 'AssetManifest.json') {
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode(
        <String, List<String>>{
          for (final String asset in fonts.keys) asset: <String>[asset],
        },
      ))));
    }
    if (fonts.containsKey(key)) return fonts[key];
    return messenger.delegate.send('flutter/assets', message);
  });
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  // SQLite FFI et les préférences peuvent terminer hors de l'horloge des
  // animations. Un tour d'événements réel suffit, sans temporisation longue.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

Future<void> _waitForRoute(WidgetTester tester, Finder route) async {
  // Une opération SQLite peut finir après les animations. La route attendue
  // prouve aussi que son appelant a repris après le rechargement du profil.
  for (int i = 0; i < 40; i++) {
    await _settle(tester);
    if (route.evaluate().isNotEmpty) {
      await _settle(tester);
      return;
    }
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 10)));
  }
  expect(route, findsOneWidget,
      reason: 'L’activation doit terminer avant le retour de navigation.');
}

Future<void> _tapWithIo(WidgetTester tester, Finder target) async {
  // Le gestionnaire de clic ouvre de vrais appels FFI. Les lancer hors de
  // FakeAsync évite qu’une file SQLite survive dans l’horloge du test précédent.
  await tester.runAsync(() => tester.tap(target));
}

Future<void> _pump(WidgetTester tester, Widget child,
    {Size size = const Size(390, 844), double scale = 1}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ));
  await _settle(tester);
  await tester.runAsync(GoogleFonts.pendingFonts);
  await _settle(tester);
}

Future<void> _picker(WidgetTester tester, {Size size = const Size(390, 844)}) async {
  await _pump(tester, Builder(builder: (context) => Center(
    child: ElevatedButton(
      key: _launchKey,
      onPressed: () => Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
        builder: (_) => const TvProfilePickerScreen(),
      )),
      child: const Text('Accueil'),
    ),
  )), size: size);
  await tester.tap(find.byKey(_launchKey));
  await _settle(tester);
}

Future<void> _createFromPicker(WidgetTester tester, String name) async {
  final Finder add = find.byKey(const ValueKey<String>('novatube-add-profile'));
  await tester.ensureVisible(add);
  await _tapWithIo(tester, add);
  await _settle(tester);
  await tester.enterText(
    find.byKey(const ValueKey<String>('zuno-touch-profile-name')), name,
  );
  tester.testTextInput.hide();
  final Finder save = find.byKey(const ValueKey<String>('zuno-touch-profile-save'));
  await tester.ensureVisible(save);
  await _tapWithIo(tester, save);
  // L’animation du nom peut finir avant SQLite. Attendre la vraie navigation
  // permet de vérifier le contrat « profil activé avant ouverture des sources ».
  await _waitForRoute(tester, find.byType(TvSourcesScreen));
}

Future<void> _seedSources(int count, String prefix) async {
  final Database db = await PlaylistDatabase.instance.database;
  final String owner = ProfileRepository.instance.active.id;
  for (int i = 0; i < count; i++) {
    await db.insert('playlists', Playlist(
      id: null,
      name: '$prefix $i',
      type: PlaylistType.m3u,
      createdAt: i + 1,
      profileId: owner,
      m3uUrl: 'https://example.invalid/$owner/$i.m3u',
      isActive: true,
    ).toMap());
  }
  await PlaylistRepository.instance.reloadForActiveProfile();
}

OutlinedButton _sourceAddButton(WidgetTester tester, String key) =>
    tester.widget<OutlinedButton>(find.descendant(
      of: find.byKey(ValueKey<String>(key)),
      matching: find.byWidgetPredicate((Widget widget) => widget is OutlinedButton),
    ));

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ProfileRepository profiles = ProfileRepository.instance;
  final PlaylistRepository sources = PlaylistRepository.instance;

  setUpAll(() async {
    await _installTestFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    PlaylistDatabase.debugFilePath = inMemoryDatabasePath;
    await PlaylistDatabase.instance.database;
  });
  setUp(() async {
    FlavorConfig.setCurrent(FlavorConfig.novatube);
    CastPlatform.configureZuno(ZunoEdition.touch);
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final Database db = await PlaylistDatabase.instance.database;
    await db.delete('playlists');
    await db.delete('deleted_sources');
    await profiles.resetForTesting();
    await profiles.load();
    PlaylistRepository.mergeAllPlaylists = true;
    await sources.reloadForActiveProfile();
  });
  tearDown(CastPlatform.resetForTesting);
  tearDownAll(() async {
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  testWidgets('Qui regarde crée et sélectionne un profil puis ouvre ses sources vides',
      (tester) async {
    await tester.runAsync(() => _seedSources(1, 'Source existante'));
    await _picker(tester, size: const Size(320, 568));
    await _createFromPicker(tester, 'Lea');
    expect(profiles.catalog.profiles, hasLength(2));
    expect(profiles.active.name, 'Lea');
    expect(profiles.active.id, isNot(ProfileIds.origin));
    expect(find.byType(TvSourcesScreen), findsOneWidget);
    expect(sources.currentPlaylists, isEmpty);
    expect(find.text('Source existante 0'), findsNothing);

    // Le bouton de ce nouveau profil conduit aux vrais champs Xtream/M3U.
    final Finder add = find.byKey(const ValueKey<String>('novatube-add-xtream'));
    await tester.ensureVisible(add);
    await _tapWithIo(tester, add);
    await _settle(tester);
    expect(find.byType(TvAddSourceScreen), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
    final AppLocalizations words = AppLocalizations.of(
      tester.element(find.byType(TvAddSourceScreen)),
    )!;
    await tester.ensureVisible(find.text(words.playlistTypeM3u));
    await tester.tap(find.text(words.playlistTypeM3u));
    await _settle(tester);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  }, variant: _android);

  testWidgets('choisir un profil recharge ses sources avant de fermer le sélecteur',
      (tester) async {
    late FamilyProfile target;
    await tester.runAsync(() async {
      await _seedSources(1, 'Source origine');
      target = (await profiles.addProfile(name: 'Ari', isKids: false))!;
      await profiles.activate(target.id, leaveAllowed: true);
      await _seedSources(1, 'Source Ari');
      await profiles.activate(ProfileIds.origin, leaveAllowed: true);
    });
    await _picker(tester);
    await _tapWithIo(tester,
        find.byKey(ValueKey<String>('zuno-touch-profile-${target.id}')));
    await _waitForRoute(tester, find.byKey(_launchKey));
    expect(find.byType(TvProfilePickerScreen), findsNothing);
    expect(find.byKey(_launchKey), findsOneWidget);
    expect(profiles.active.id, target.id);
    expect(sources.currentPlaylists.map((Playlist p) => p.name), <String>['Source Ari 0']);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  }, variant: _android);

  testWidgets('le dixième profil peut être créé et le onzième reste désactivé',
      (tester) async {
    await tester.runAsync(() async {
      for (int i = 1; i < ProfileCatalog.maxProfiles - 1; i++) {
        await profiles.addProfile(name: 'Personne $i', isKids: false);
      }
    });
    expect(profiles.catalog.profiles, hasLength(9));
    await _picker(tester);
    await _createFromPicker(tester, 'Dixieme');
    expect(profiles.catalog.profiles, hasLength(10));
    expect(profiles.active.name, 'Dixieme');
    expect(find.byType(TvSourcesScreen), findsOneWidget);
    // pageBack() cherche le tooltip anglais « Back » ; l’interface est en FR.
    await _tapWithIo(tester, find.byType(BackButton));
    await _waitForRoute(tester, find.byKey(_launchKey));
    expect(find.byKey(_launchKey), findsOneWidget);
    await tester.tap(find.byKey(_launchKey));
    await _settle(tester);
    final Finder add = find.byKey(const ValueKey<String>('novatube-add-profile'));
    await tester.ensureVisible(add);
    expect(tester.widget<FilledButton>(add).onPressed, isNull);
    final AppLocalizations words = AppLocalizations.of(tester.element(add))!;
    expect(find.text(words.tvProfileLimit(10)), findsOneWidget);
    // Atteindre la limite n'empêche pas de sélectionner un autre profil.
    final Finder origin = find.byKey(const ValueKey<String>('zuno-touch-profile-p1'));
    await tester.ensureVisible(origin);
    await _tapWithIo(tester, origin);
    await _waitForRoute(tester, find.byKey(_launchKey));
    expect(profiles.active.id, ProfileIds.origin);
    expect(profiles.catalog.profiles, hasLength(10));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  }, variant: _android);

  testWidgets('la gestion des profils ouvre les sources du profil sélectionné',
      (tester) async {
    late FamilyProfile target;
    await tester.runAsync(() async {
      target = (await profiles.addProfile(name: 'Noa', isKids: false))!;
      await profiles.activate(target.id, leaveAllowed: true);
      await _seedSources(1, 'Source Noa');
    });
    await _pump(tester, const TvShell(child: TvProfilesScreen()));
    final Finder action = find.byKey(const ValueKey<String>('novatube-profile-sources'));
    await tester.ensureVisible(action);
    await _tapWithIo(tester, action);
    await _settle(tester);
    expect(find.byType(TvSourcesScreen), findsOneWidget);
    expect(profiles.active.id, target.id);
    expect(find.text('Source Noa 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  }, variant: _android);

  testWidgets('dix sources bloquent les ajouts et une suppression libère une place',
      (tester) async {
    await tester.runAsync(() => _seedSources(10, 'Source personnelle'));
    await _pump(tester, const TvShell(child: TvSourcesScreen()));
    expect(_sourceAddButton(tester, 'novatube-add-xtream').onPressed, isNull);
    expect(_sourceAddButton(tester, 'novatube-add-m3u').onPressed, isNull);
    final AppLocalizations words = AppLocalizations.of(
      tester.element(find.byType(TvSourcesScreen)),
    )!;
    expect(find.text(words.tvSourceCount(10, 10)), findsOneWidget);
    expect(find.text(words.tvSourceLimitReached(10)), findsOneWidget);
    final int removeId = sources.currentPlaylists.last.id!;
    await tester.runAsync(() => sources.deletePlaylist(removeId));
    await _settle(tester);
    expect(find.text(words.tvSourceCount(9, 10)), findsOneWidget);
    expect(_sourceAddButton(tester, 'novatube-add-xtream').onPressed, isNotNull);
    expect(_sourceAddButton(tester, 'novatube-add-m3u').onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  }, variant: _android);
}
