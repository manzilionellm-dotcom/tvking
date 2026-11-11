import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/novatube_content_policy.dart';
import 'package:tv_king/core/app/novatube_private_features.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/cinema/data/watch_progress.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/security/data/adult_access.dart';
import 'package:tv_king/features/security/data/adult_biometric_auth.dart';
import 'package:tv_king/features/security/data/app_pin_settings.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';
import 'package:tv_king/features/tv/data/home_shelves.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_common.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_screen.dart';
import 'package:tv_king/features/vod/data/download_repository.dart';

class _FakeBiometrics implements AdultBiometricAuthenticator {
  AdultBiometricResult result = AdultBiometricResult.authenticated;
  Completer<AdultBiometricResult>? pending;
  final Completer<void> started = Completer<void>();
  int calls = 0;
  int cancellations = 0;
  bool throwsError = false;

  @override
  Future<AdultBiometricResult> authenticate({required String reason}) async {
    calls++;
    if (!started.isCompleted) started.complete();
    if (throwsError) throw StateError('fixture');
    if (pending != null) return pending!.future;
    return result;
  }

  @override
  Future<void> cancel() async {
    cancellations++;
    // Le succès peut arriver APRÈS une annulation : les tests vérifient que
    // le jeton invalidé suffit à refuser cette réponse native tardive.
  }
}

class _FakeLocalAuthentication extends LocalAuthentication {
  bool hardware = true;
  List<BiometricType> enrolled = <BiometricType>[BiometricType.strong];
  bool accepted = true;
  Object? failure;
  Completer<bool>? capabilityPending;
  final Completer<void> capabilityStarted = Completer<void>();
  Completer<bool>? pending;
  final Completer<void> started = Completer<void>();
  int authenticateCalls = 0;
  int stopCalls = 0;
  int deviceSupportCalls = 0;
  AuthenticationOptions? capturedOptions;
  String? capturedReason;

  @override
  Future<bool> get canCheckBiometrics async {
    if (!capabilityStarted.isCompleted) capabilityStarted.complete();
    if (capabilityPending != null) return capabilityPending!.future;
    return hardware;
  }

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => enrolled;

  @override
  Future<bool> isDeviceSupported() async {
    deviceSupportCalls++;
    return true;
  }

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object> authMessages = const <Object>[],
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    authenticateCalls++;
    capturedOptions = options;
    capturedReason = localizedReason;
    if (!started.isCompleted) started.complete();
    final Object? problem = failure;
    if (problem != null) throw problem;
    if (pending != null) return pending!.future;
    return accepted;
  }

  @override
  Future<bool> stopAuthentication() async {
    stopCalls++;
    return true;
  }
}

void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();
  late AdultAccess access;
  late _FakeBiometrics biometrics;

  setUp(() async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ActiveProfile.instance.set('p1');
    await ParentalControls.instance.load();
    biometrics = _FakeBiometrics();
    access = AdultAccess.forTesting(supported: true, biometrics: biometrics);
    await access.load();
  });

  tearDown(() => access.dispose());

  Future<bool> enable() =>
      access.enableWithBiometrics(consent: true, reason: 'fixture +18');

  test(
    'premier lancement fermé : consentement obligatoire avant biométrie',
    () async {
      expect(access.enabled.value, isFalse);
      expect(access.canAccess, isFalse);
      expect(
        await access.enableWithBiometrics(consent: false, reason: 'test'),
        isFalse,
      );
      expect(await access.unlockWithBiometrics(reason: 'test'), isFalse);
      expect(biometrics.calls, 0);
    },
  );

  test('un PIN correct ou historique ne donne jamais accès à +18', () async {
    await AppPinSettings.instance.setPin('3579');
    for (final String pin in <String>['0000', '3579', '2580']) {
      expect(await access.enableWithPin(pin), isFalse);
      expect(await access.unlockWithPin(pin), isFalse);
    }
    expect(biometrics.calls, 0);
    expect(access.enabled.value, isFalse);
    expect(access.canAccess, isFalse);
  });

  test(
    'biométrie requise à chaque visite sans création de PIN parental',
    () async {
      expect(await AppPinSettings.instance.hasCustomPin(), isFalse);
      expect(await enable(), isTrue);
      expect(access.canAccess, isTrue);
      expect(biometrics.calls, 1);
      expect(await AppPinSettings.instance.hasCustomPin(), isFalse);
      access.lock();
      expect(access.enabled.value, isTrue);
      expect(access.canAccess, isFalse);
      expect(
        await access.unlockWithBiometrics(reason: 'nouvelle visite'),
        isTrue,
      );
      expect(biometrics.calls, 2);
      await access.disable();
      expect(await access.unlockWithBiometrics(reason: 'désactivé'), isFalse);
      expect(biometrics.calls, 2);
    },
  );

  for (final AdultBiometricResult result in AdultBiometricResult.values.where(
    (value) => value != AdultBiometricResult.authenticated,
  )) {
    test('biométrie $result : activation et ouverture refusées', () async {
      biometrics.result = result;
      expect(await enable(), isFalse);
      expect(access.enabled.value, isFalse);
      expect(access.canAccess, isFalse);
      expect(access.lastBiometricResult, result);
      biometrics.result = AdultBiometricResult.authenticated;
      expect(await enable(), isTrue);
      access.lock();
      biometrics.result = result;
      expect(await access.unlockWithBiometrics(reason: 'test'), isFalse);
      expect(access.enabled.value, isTrue);
      expect(access.canAccess, isFalse);
      expect(access.lastBiometricResult, result);
    });
  }

  test('exception inattendue du service : accès fermé', () async {
    biometrics.throwsError = true;
    expect(await enable(), isFalse);
    expect(access.canAccess, isFalse);
    expect(access.lastBiometricResult, AdultBiometricResult.error);
  });

  test(
    'activation persistante, session jamais persistante après redémarrage',
    () async {
      expect(await enable(), isTrue);
      final AdultAccess reopened = AdultAccess.forTesting(
        supported: true,
        biometrics: _FakeBiometrics(),
      );
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.enabled.value, isTrue);
      expect(reopened.unlocked.value, isFalse);
      expect(reopened.canAccess, isFalse);
    },
  );

  test(
    'changement de profil verrouille immédiatement et isole l’activation',
    () async {
      expect(await enable(), isTrue);
      ActiveProfile.instance.set('p2');
      expect(access.canAccess, isFalse);
      expect(access.unlocked.value, isFalse);
      await access.load();
      expect(access.enabled.value, isFalse);
      expect(
        await access.unlockWithBiometrics(reason: 'profil non activé'),
        isFalse,
      );
      ActiveProfile.instance.set('p1');
      await access.load();
      expect(access.enabled.value, isTrue);
      expect(access.canAccess, isFalse);
    },
  );

  test(
    'changer de profil puis revenir invalide le succès biométrique tardif',
    () async {
      biometrics.pending = Completer<AdultBiometricResult>();
      final Future<bool> opening = enable();
      await biometrics.started.future;
      ActiveProfile.instance.set('p2');
      ActiveProfile.instance.set('p1');
      await access.load();
      biometrics.pending!.complete(AdultBiometricResult.authenticated);
      expect(await opening, isFalse);
      expect(access.enabled.value, isFalse);
      expect(access.canAccess, isFalse);
      expect(biometrics.cancellations, greaterThan(0));
    },
  );

  test(
    'mode enfants ferme une session et empêche tout nouveau prompt',
    () async {
      expect(await enable(), isTrue);
      await ParentalControls.instance.setKidsMode(true);
      expect(access.unlocked.value, isFalse);
      expect(access.canAccess, isFalse);
      expect(await enable(), isFalse);
      expect(await access.unlockWithBiometrics(reason: 'enfants'), isFalse);
      expect(biometrics.calls, 1);
    },
  );

  test('mode enfants pendant le prompt invalide sa réponse tardive', () async {
    biometrics.pending = Completer<AdultBiometricResult>();
    final Future<bool> opening = enable();
    await biometrics.started.future;
    await ParentalControls.instance.setKidsMode(true);
    biometrics.pending!.complete(AdultBiometricResult.authenticated);
    expect(await opening, isFalse);
    expect(access.enabled.value, isFalse);
    expect(access.canAccess, isFalse);
  });

  test('annulation ou retour arrière invalide un succès tardif', () async {
    biometrics.pending = Completer<AdultBiometricResult>();
    final Future<bool> opening = enable();
    await biometrics.started.future;
    access.lock();
    biometrics.pending!.complete(AdultBiometricResult.authenticated);
    expect(await opening, isFalse);
    expect(access.canAccess, isFalse);
    expect(access.enabled.value, isFalse);
    expect(biometrics.cancellations, greaterThan(0));
  });

  test('un seul prompt peut être en attente', () async {
    biometrics.pending = Completer<AdultBiometricResult>();
    final Future<bool> opening = enable();
    await biometrics.started.future;
    expect(await enable(), isFalse);
    expect(biometrics.calls, 1);
    biometrics.pending!.complete(AdultBiometricResult.authenticated);
    expect(await opening, isTrue);
  });

  test(
    'inactive temporaire de BiometricPrompt ne casse pas la vérification',
    () async {
      biometrics.pending = Completer<AdultBiometricResult>();
      final Future<bool> opening = enable();
      await biometrics.started.future;
      access.didChangeAppLifecycleState(AppLifecycleState.inactive);
      biometrics.pending!.complete(AdultBiometricResult.authenticated);
      expect(await opening, isTrue);
      expect(biometrics.cancellations, 0);
    },
  );

  for (final AppLifecycleState state in <AppLifecycleState>[
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.detached,
  ]) {
    test('$state annule le prompt et le retour ne déverrouille rien', () async {
      biometrics.pending = Completer<AdultBiometricResult>();
      final Future<bool> opening = enable();
      await biometrics.started.future;
      access.didChangeAppLifecycleState(state);
      access.didChangeAppLifecycleState(AppLifecycleState.resumed);
      biometrics.pending!.complete(AdultBiometricResult.authenticated);
      expect(await opening, isFalse);
      expect(access.canAccess, isFalse);
      expect(access.enabled.value, isFalse);
    });
  }

  test('mise en arrière-plan ferme aussi une session déjà ouverte', () async {
    expect(await enable(), isTrue);
    access.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(access.canAccess, isFalse);
    expect(access.unlocked.value, isFalse);
    access.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(access.canAccess, isFalse);
    expect(await access.unlockWithBiometrics(reason: 'retour'), isTrue);
    expect(biometrics.calls, 2);
  });

  test(
    'le PIN des autres contrôles parentaux conserve sa limitation d’essais',
    () async {
      await AppPinSettings.instance.setPin('3579');
      for (int i = 0; i < 5; i++) {
        expect(await AppPinSettings.instance.verify('2580'), isFalse);
      }
      expect(await AppPinSettings.instance.verify('3579'), isFalse);
      expect(await AppPinSettings.instance.lockRemainingMs(), greaterThan(0));
      expect(access.canAccess, isFalse);
    },
  );

  test(
    'édition Play impossible à ouvrir, même avec préférences et biométrie',
    () async {
      expect(await enable(), isTrue);
      final _FakeBiometrics playBiometrics = _FakeBiometrics();
      final AdultAccess play = AdultAccess.forTesting(
        supported: false,
        biometrics: playBiometrics,
      );
      addTearDown(play.dispose);
      await play.load();
      expect(play.enabled.value, isFalse);
      expect(
        await play.enableWithBiometrics(consent: true, reason: 'test'),
        isFalse,
      );
      expect(await play.unlockWithBiometrics(reason: 'test'), isFalse);
      expect(await play.enableWithPin('3579'), isFalse);
      expect(await play.unlockWithPin('3579'), isFalse);
      expect(playBiometrics.calls, 0);
      expect(play.canAccess, isFalse);
    },
  );

  group('wrapper local_auth strict dédié à +18', () {
    test('annuler le contrôle du capteur empêche un prompt tardif', () async {
      final _FakeLocalAuthentication native = _FakeLocalAuthentication()
        ..capabilityPending = Completer<bool>();
      final SystemAdultBiometrics wrapper = SystemAdultBiometrics(
        authentication: native,
      );
      final Future<AdultBiometricResult> result = wrapper.authenticate(
        reason: 'test',
      );
      await native.capabilityStarted.future;
      await wrapper.cancel();
      native.capabilityPending!.complete(true);
      expect(await result, AdultBiometricResult.cancelled);
      expect(native.authenticateCalls, 0);
    });

    test(
      'aucun capteur : refus même si un code appareil serait disponible',
      () async {
        final _FakeLocalAuthentication native = _FakeLocalAuthentication()
          ..hardware = false;
        final SystemAdultBiometrics wrapper = SystemAdultBiometrics(
          authentication: native,
        );
        expect(
          await wrapper.authenticate(reason: 'test'),
          AdultBiometricResult.unavailable,
        );
        expect(native.deviceSupportCalls, 0);
        expect(native.authenticateCalls, 0);
      },
    );

    test('capteur sans inscription : aucun prompt ni fallback', () async {
      final _FakeLocalAuthentication native = _FakeLocalAuthentication()
        ..enrolled = <BiometricType>[];
      expect(
        await SystemAdultBiometrics(authentication: native)
            .authenticate(reason: 'test'),
        AdultBiometricResult.notEnrolled,
      );
      expect(native.authenticateCalls, 0);
    });

    test(
      'succès natif : biometricOnly obligatoire, reprise automatique interdite',
      () async {
        final _FakeLocalAuthentication native = _FakeLocalAuthentication();
        expect(
          await SystemAdultBiometrics(authentication: native)
              .authenticate(reason: 'ouvrir +18'),
          AdultBiometricResult.authenticated,
        );
        expect(native.capturedReason, 'ouvrir +18');
        expect(native.capturedOptions!.biometricOnly, isTrue);
        expect(native.capturedOptions!.stickyAuth, isFalse);
        expect(native.capturedOptions!.useErrorDialogs, isFalse);
        expect(native.capturedOptions!.sensitiveTransaction, isTrue);
        expect(native.deviceSupportCalls, 0);
      },
    );

    test('annulation ou refus natif ne devient pas une autorisation', () async {
      final _FakeLocalAuthentication native = _FakeLocalAuthentication()
        ..accepted = false;
      expect(
        await SystemAdultBiometrics(authentication: native)
            .authenticate(reason: 'test'),
        AdultBiometricResult.rejected,
      );
    });

    test('erreurs système et verrouillages restent fermés', () async {
      const Map<String, AdultBiometricResult> expected =
          <String, AdultBiometricResult>{
            'NotAvailable': AdultBiometricResult.unavailable,
            'NotEnrolled': AdultBiometricResult.notEnrolled,
            'PasscodeNotSet': AdultBiometricResult.notEnrolled,
            'LockedOut': AdultBiometricResult.lockedOut,
            'PermanentlyLockedOut': AdultBiometricResult.lockedOut,
            'biometricOnlyNotSupported': AdultBiometricResult.unavailable,
            'unexpected_fixture': AdultBiometricResult.error,
          };
      for (final MapEntry<String, AdultBiometricResult> entry
          in expected.entries) {
        final _FakeLocalAuthentication native = _FakeLocalAuthentication()
          ..failure = PlatformException(code: entry.key);
        expect(
          await SystemAdultBiometrics(authentication: native)
              .authenticate(reason: 'test'),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test(
      'annulation du wrapper refuse même un succès natif déjà en transit',
      () async {
        final _FakeLocalAuthentication native = _FakeLocalAuthentication()
          ..pending = Completer<bool>();
        final SystemAdultBiometrics wrapper = SystemAdultBiometrics(
          authentication: native,
        );
        final Future<AdultBiometricResult> result = wrapper.authenticate(
          reason: 'test',
        );
        await native.started.future;
        await wrapper.cancel();
        native.pending!.complete(true);
        expect(await result, AdultBiometricResult.cancelled);
        expect(native.stopCalls, 1);
      },
    );
  });

  test('import privé distinct de l’autorisation de lecture', () {
    expect(
      NovatubeContentPolicy.canImport(name: 'Fixture', category: '18+'),
      NovatubePrivateFeatures.adultCatalogs,
    );
    expect(
      NovatubeContentPolicy.allows(name: 'Fixture', category: '18+'),
      isFalse,
    );
    expect(
      NovatubeContentPolicy.allows(name: 'Fixture', category: 'Sports'),
      isTrue,
    );
  });

  test('catégorie conservée dans historique, reprise et téléchargements', () {
    const VodPlayItem item = VodPlayItem(
      id: 'fixture',
      isEpisode: false,
      title: 'Titre neutre',
      url: 'https://example.invalid/fixture.mp4',
      categoryKey: '18+',
    );
    final WatchEntry entry = item.toEntry(posMs: 40000, durMs: 600000);
    final WatchEntry restored = WatchEntry.fromJson(entry.toJson())!;
    expect(restored.categoryKey, '18+');
    expect(VodPlayItem.entry(restored).categoryKey, '18+');
    expect(VodPlayItem.entry(restored).isAllowedInPlay, isFalse);
    const Download download = Download(
      id: 'fixture',
      name: 'Titre neutre',
      sourceUrl: 'https://example.invalid/fixture.mp4',
      filePath: '/fixture.mp4',
      status: DownloadStatus.paused,
      receivedBytes: 0,
      totalBytes: 0,
      createdAt: 0,
      category: '18+',
      profileId: 'p2',
    );
    final Download copy = Download.fromMap(download.copyWith().toMap());
    expect(copy.category, '18+');
    expect(copy.profileId, 'p2');
  });

  test('reprise série : la catégorie suit aussi l’épisode suivant', () {
    const WatchEntry entry = WatchEntry(
      id: 'p3:e:901',
      isEpisode: true,
      title: 'Série au nom neutre',
      streamUrl: 'https://example.invalid/episode-1.mp4',
      posMs: 40000,
      durMs: 600000,
      updatedAt: 1,
      sourceKey: 'p3',
      remoteId: '901',
      categoryKey: '+18',
      seriesId: 'p3:s:123',
      season: 1,
      episode: 1,
    );
    final CinemaTitle series = seriesTitleFromEntry(entry);
    expect(series.categoryKey, '+18');
    const CinemaEpisode next = CinemaEpisode(
      id: 'p3:e:902',
      remoteId: '902',
      seriesId: 'p3:s:123',
      season: 1,
      number: 2,
      title: 'Épisode suivant',
      streamUrl: 'https://example.invalid/episode-2.mp4',
      containerExt: 'mp4',
    );
    final VodPlayItem item = VodPlayItem.episode(next, series);
    expect(item.toEntry(posMs: 0, durMs: 600000).categoryKey, '+18');
    expect(item.toVodMovie().category, '+18');
    expect(item.isAllowedInPlay, isFalse);
  });

  test(
    'accueil : catégorie +18 masquée sans cache ou malgré un ancien genre',
    () {
      const Channel cold = Channel(
        id: 'novatube-adult-home-cold-fixture',
        name: 'Chaîne neutre',
        category: '+18',
        streamUrl: 'https://example.invalid/live.ts',
        isLive: true,
      );
      expect(ChannelPrecompute.cachedGenre(cold), isNull);
      expect(hiddenForKids(cold), isTrue);

      // Une actualisation peut réutiliser l’ID d’une ancienne chaîne sportive.
      // La protection doit lire les nouvelles métadonnées, pas ce vieux cache.
      const Channel previous = Channel(
        id: 'novatube-adult-home-refreshed-fixture',
        name: 'Chaîne neutre',
        category: 'Sports',
        streamUrl: 'https://example.invalid/live.ts',
        isLive: true,
      );
      expect(previous.genre, ChannelGenre.sports);
      expect(hiddenForKids(previous), isFalse);
      const Channel refreshed = Channel(
        id: 'novatube-adult-home-refreshed-fixture',
        name: 'Chaîne neutre',
        category: '+18',
        streamUrl: 'https://example.invalid/live.ts',
        isLive: true,
      );
      expect(ChannelPrecompute.cachedGenre(refreshed), ChannelGenre.sports);
      expect(hiddenForKids(refreshed), isTrue);
    },
  );
}
