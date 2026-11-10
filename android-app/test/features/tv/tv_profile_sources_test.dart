import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/playlists/data/import_progress.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/playlists/domain/open_source_input.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/tv/data/local_m3u_picker.dart';
import 'package:tv_king/features/tv/presentation/tv_add_source_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_components.dart';
import 'package:tv_king/features/tv/presentation/tv_profile_picker.dart';
import 'package:tv_king/features/tv/presentation/tv_profiles_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_scaled_viewport.dart';
import 'package:tv_king/features/tv/presentation/tv_shell.dart';
import 'package:tv_king/features/tv/presentation/tv_source_entry_form.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

FamilyProfile _profile(String id, {bool kids = false}) => FamilyProfile(
      id: id,
      name: id,
      avatar: 1,
      isKids: kids,
      createdAtMs: 1,
      playlistIds: const <int>[],
    );

ProfileCatalog _catalog(
        {String active = 'p2', bool kids = false, bool second = true}) =>
    ProfileCatalog(
      profiles: <FamilyProfile>[
        FamilyProfile.origin(),
        if (second) _profile('p2', kids: kids),
        _profile('p3'),
      ],
      activeId: active,
      askOnStartup: null,
    );

Playlist _saved(int id, {PlaylistType type = PlaylistType.xtream}) => Playlist(
      id: id,
      name: 'Liste de test',
      type: type,
      createdAt: 1,
    );

Finder _field(String key) => find.descendant(
      of: find.byKey(ValueKey<String>('tv-source-$key')),
      matching: find.byType(TextField),
    );

void _submit(WidgetTester tester) => tester
    .widget<TvCtaButton>(
      find.byKey(const ValueKey<String>('tv-source-submit')),
    )
    .onSelect!();

Future<void> _fill(WidgetTester tester, OpenEntryMode mode) async {
  if (mode == OpenEntryMode.xtream) {
    await tester.enterText(_field('server'), 'https://fixture.invalid');
    await tester.enterText(_field('user'), 'fixture-user');
    await tester.enterText(_field('password'), 'fixture-password');
  } else {
    await tester.enterText(_field('m3u'), 'https://fixture.invalid/list.m3u');
  }
}

Future<GlobalKey<NavigatorState>> _show(
  WidgetTester tester,
  Widget child, {
  ProfileCatalog? catalog,
  Size size = const Size(1280, 800),
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  ProfileRepository.instance.resetForTesting(catalog ?? ProfileCatalog.fresh());
  RemoteSourceRepository.resetImportQueueForTesting();
  ImportProgressBus.clear();
  final navigator = GlobalKey<NavigatorState>();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    navigatorKey: navigator,
    locale: const Locale('fr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (_, child) => TvScaledViewport(child: child!),
    home: child,
  ));
  await tester.pumpAndSettle();
  return navigator;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('Ajouter au D-pad crée le profil puis lie la liste du formulaire',
      (tester) async {
    String? target;
    await _show(tester, TvProfilePickerScreen(
      sourceBuilderForTesting: (id) {
        target = id;
        return SingleChildScrollView(
            child: TvSourceEntryForm(
          targetProfileId: id,
          importPlaylistForTesting: (_, __) async => _saved(71),
        ));
      },
    ));
    final add = find.byKey(const ValueKey<String>('tv-profile-add'));
    expect(add, findsOneWidget);
    Focus.of(tester.element(find.text('Ajouter'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Sport');
    final l10n = AppLocalizations.of(tester.element(find.byType(TextField)));
    await tester.tap(find.text(l10n.buttonSave));
    await tester.pumpAndSettle();
    expect(target, isNotNull);
    expect(ProfileRepository.instance.active.id, target);
    expect(ProfileRepository.instance.active.playlistIds, isEmpty);
    expect(find.byType(TvSourceEntryForm), findsOneWidget);
    await _fill(tester, OpenEntryMode.xtream);
    _submit(tester);
    await tester.pumpAndSettle();
    expect(ProfileRepository.instance.profileById(target!)!.playlistIds,
        <int>[71]);
    expect(
        ProfileRepository.instance.profileById(ProfileIds.origin)!.playlistIds,
        isNull);
  });

  testWidgets(
      'annuler le nom ne crée rien ; annuler la source garde un profil vide',
      (tester) async {
    final nav = await _show(tester, const TvProfilePickerScreen());
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(ProfileRepository.instance.catalog.profiles, hasLength(1));
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Cinéma');
    final l10n = AppLocalizations.of(tester.element(find.byType(TextField)));
    await tester.tap(find.text(l10n.buttonSave));
    await tester.pumpAndSettle();
    expect(find.byType(TvAddSourceScreen), findsOneWidget);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(ProfileRepository.instance.catalog.profiles, hasLength(2));
    expect(ProfileRepository.instance.active.playlistIds, isEmpty);
    expect(find.byType(TvProfilePickerScreen), findsOneWidget);
  });

  testWidgets('Ajouter depuis Enfants demande le PIN avant toute création',
      (tester) async {
    final nav = await _show(tester, const TvProfilePickerScreen(),
        catalog: _catalog(kids: true));
    final l10n =
        AppLocalizations.of(tester.element(find.byType(TvProfilePickerScreen)));
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.tvEnterParentalCode), findsOneWidget);
    expect(find.text(l10n.tvNewProfile), findsNothing);
    expect(ProfileRepository.instance.catalog.profiles, hasLength(3));
    expect(ProfileRepository.instance.active.id, 'p2');
    expect(find.byType(TvAddSourceScreen), findsNothing);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(ProfileRepository.instance.catalog.profiles, hasLength(3));
    expect(ProfileRepository.instance.active.id, 'p2');
  });

  testWidgets('le profil vide ouvre sa liste depuis Réglages → Profils',
      (tester) async {
    await _show(tester, const TvShell(child: TvProfilesScreen()),
        catalog: _catalog());
    final action = find.text('Listes du profil');
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TvAddSourceScreen>(find.byType(TvAddSourceScreen))
            .targetProfileId,
        'p2');
  });

  for (final mode in <OpenEntryMode>[OpenEntryMode.xtream, OpenEntryMode.m3u]) {
    testWidgets('$mode : un changement pendant la file ne déplace pas la liste',
        (tester) async {
      await _show(
          tester,
          Scaffold(
              body: SingleChildScrollView(
                  child: TvSourceEntryForm(
            initialMode: mode,
            importPlaylistForTesting: (_, __) async => _saved(72),
          ))),
          catalog: _catalog());
      final waiting = Completer<void>();
      final preceding =
          RemoteSourceRepository.runUserImport<void>(() => waiting.future);
      await _fill(tester, mode);
      _submit(tester);
      await tester.pump();
      await ProfileRepository.instance.activate('p3', leaveAllowed: true);
      waiting.complete();
      await preceding;
      await tester.pumpAndSettle();
      expect(
          ProfileRepository.instance.profileById('p2')!.playlistIds, <int>[72]);
      expect(
          ProfileRepository.instance.profileById('p3')!.playlistIds, isEmpty);
      expect(ProfileRepository.instance.active.id, 'p3');
    });
  }

  testWidgets('la cible du fichier est capturée avant le sélecteur Android',
      (tester) async {
    final pick = Completer<LocalM3uPick>();
    await _show(
        tester,
        Scaffold(
            body: SingleChildScrollView(
                child: TvSourceEntryForm(
          pickLocalFileForTesting: () => pick.future,
          importLocalPlaylistForTesting: (_, __) async =>
              _saved(73, type: PlaylistType.m3u),
        ))),
        catalog: _catalog());
    await tester.tap(find.byKey(const ValueKey<String>('tv-source-file')));
    await tester.pump();
    await ProfileRepository.instance.activate('p3', leaveAllowed: true);
    pick.complete(
        const LocalM3uPick(LocalM3uPickStatus.ok, path: '/fixture/list.m3u'));
    await tester.pumpAndSettle();
    expect(
        ProfileRepository.instance.profileById('p2')!.playlistIds, <int>[73]);
    expect(ProfileRepository.instance.profileById('p3')!.playlistIds, isEmpty);
  });

  testWidgets(
      'profil supprimé pendant import : aucun transfert vers le profil actif',
      (tester) async {
    final importing = Completer<Playlist>();
    int added = 0;
    await _show(
        tester,
        Scaffold(
            body: SingleChildScrollView(
                child: TvSourceEntryForm(
          targetProfileId: 'p2',
          importPlaylistForTesting: (_, __) => importing.future,
          onAdded: () => added++,
        ))),
        catalog: _catalog());
    await _fill(tester, OpenEntryMode.xtream);
    _submit(tester);
    await tester.pump();
    ProfileRepository.instance
        .resetForTesting(_catalog(active: 'p3', second: false));
    importing.complete(_saved(74));
    await tester.pumpAndSettle();
    expect(ProfileRepository.instance.profileById('p2'), isNull);
    expect(ProfileRepository.instance.profileById('p3')!.playlistIds, isEmpty);
    expect(
        ProfileRepository.instance.profileById(ProfileIds.origin)!.playlistIds,
        isNull);
    expect(added, 0);
    expect(find.text('Ce profil n’existe plus. La liste n’a pas été associée.'),
        findsOneWidget);
  });

  testWidgets('quatre profils : cartes conservées, aucun cinquième ajout',
      (tester) async {
    var catalog = ProfileCatalog.fresh();
    for (var i = 2; i <= 4; i++) {
      catalog = catalog.add(name: 'Profil $i', isKids: false, nowMs: i)!;
    }
    await _show(tester, const TvProfilePickerScreen(),
        catalog: catalog, size: const Size(390, 844));
    expect(find.byKey(const ValueKey<String>('tv-profile-add')), findsNothing);
    expect(find.text('Plus tard'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
