import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Le plugin réel délègue à cette interface ; le faux vérifie ses options.
// ignore: depend_on_referenced_packages
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/cast/data/cast_platform.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/security/data/adult_access.dart';
import 'package:tv_king/features/security/data/app_pin_settings.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';

class _Biometrics extends LocalAuthPlatform {
  bool hardware = true;
  bool succeeds = true;
  Object? capabilityError;
  Object? authError;
  List<BiometricType> enrolled = <BiometricType>[BiometricType.fingerprint];
  int checks = 0;
  int prompts = 0;
  AuthenticationOptions? options;
  String? reason;
  final Completer<void> entered = Completer<void>();
  Completer<bool>? result;

  @override
  Future<bool> deviceSupportsBiometrics() async {
    checks++;
    if (capabilityError != null) throw capabilityError!;
    return hardware;
  }

  @override
  Future<List<BiometricType>> getEnrolledBiometrics() async => enrolled;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    prompts++;
    this.options = options;
    reason = localizedReason;
    if (!entered.isCompleted) entered.complete();
    if (authError != null) throw authError!;
    if (result != null) return result!.future;
    return succeeds;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel capability =
      MethodChannel('com.sevenmotion.zuno/cast-capability');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late LocalAuthPlatform original;
  late _Biometrics biometrics;
  int pins = 0;

  Future<bool> correctPin() async {
    pins++;
    return AppPinSettings.instance.verify('3718');
  }

  Future<AdultAccessGrant?> authenticate() async {
    final AdultAccessGrant? grant = await authenticateAdultAccess(
      reason: 'Confirme l’accès Adultes',
      confirmPin: correctPin,
    );
    if (grant != null) addTearDown(grant.dispose);
    return grant;
  }

  setUp(() async {
    original = LocalAuthPlatform.instance;
    biometrics = _Biometrics();
    LocalAuthPlatform.instance = biometrics;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ProfileRepository.instance.resetForTesting(ProfileCatalog.fresh());
    await ParentalControls.instance.load();
    await AppPinSettings.instance.setPin('3718');
    pins = 0;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(capability, (_) async => true);
    await CastPlatform.initializeZuno();
  });

  tearDown(() {
    LocalAuthPlatform.instance = original;
    messenger.setMockMethodCallHandler(capability, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
      'téléphone inscrit : authentification biométrique seule, aucune donnée stockée',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final grant = await authenticate();
    expect(grant?.isValid, isTrue);
    expect(biometrics.prompts, 1);
    expect(biometrics.reason, 'Confirme l’accès Adultes');
    expect(biometrics.options?.biometricOnly, isTrue);
    expect(biometrics.options?.stickyAuth, isFalse);
    expect(biometrics.options?.useErrorDialogs, isFalse);
    expect(biometrics.options?.sensitiveTransaction, isTrue);
    expect(pins, 0);
    expect(prefs.getKeys(), keys);
  });

  test('annulation/refus biométrique ne propose pas le PIN', () async {
    biometrics.succeeds = false;
    expect(await authenticate(), isNull);
    expect(pins, 0);
  });

  for (final String code in <String>[
    'LockedOut',
    'PermanentlyLockedOut',
    'NotAvailable',
    'no_fragment_activity',
    'auth_in_progress'
  ]) {
    test('erreur $code reste verrouillée sans repli', () async {
      biometrics.authError = PlatformException(code: code);
      expect(await authenticate(), isNull);
      expect(pins, 0);
    });
  }

  test('Android renvoie inscription vide en lockout : aucun contournement PIN',
      () async {
    biometrics.enrolled = <BiometricType>[];
    biometrics.authError = PlatformException(code: 'LockedOut');
    expect(await authenticate(), isNull);
    expect(biometrics.prompts, 1);
    expect(pins, 0);
  });

  test('capteur absent : même PIN que les réglages', () async {
    biometrics.hardware = false;
    expect((await authenticate())?.isValid, isTrue);
    expect(biometrics.prompts, 0);
    expect(pins, 1);
  });

  test('aucune biométrie inscrite confirmée par le plugin : PIN autorisé',
      () async {
    biometrics.enrolled = <BiometricType>[];
    biometrics.authError = PlatformException(code: 'NotEnrolled');
    expect((await authenticate())?.isValid, isTrue);
    expect(pins, 1);
    expect(biometrics.options?.biometricOnly, isTrue);
  });

  test('inscription retirée pendant un dialogue déjà disponible : pas de repli',
      () async {
    biometrics.authError = PlatformException(code: 'NotEnrolled');
    expect(await authenticate(), isNull);
    expect(pins, 0);
  });

  test('détection impossible n’est pas une preuve d’absence de capteur',
      () async {
    biometrics.capabilityError = MissingPluginException();
    expect(await authenticate(), isNull);
    expect(biometrics.prompts, 0);
    expect(pins, 0);
  });

  test('vraie TV : aucun appel biométrique, PIN des réglages requis', () async {
    messenger.setMockMethodCallHandler(capability, (_) async => false);
    await CastPlatform.initializeZuno();
    expect((await authenticate())?.isValid, isTrue);
    expect(biometrics.checks, 0);
    expect(pins, 1);
    final denied = await authenticateAdultAccess(
      reason: 'Fixture',
      confirmPin: () => AppPinSettings.instance.verify('1234'),
    );
    expect(denied, isNull);
  });

  test('profil Enfants refuse avant tout dialogue', () async {
    final cat =
        ProfileCatalog.fresh().add(name: 'Enfants', isKids: true, nowMs: 1)!;
    ProfileRepository.instance
        .resetForTesting(cat.activate(cat.profiles.last.id)!);
    expect(await authenticate(), isNull);
    expect(biometrics.checks, 0);
    expect(pins, 0);
  });

  test('mode enfants persisté refuse même avant chargement du notifier',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(ProfileKeys.kidsMode('p1'), true);
    ParentalControls.instance.kidsMode.value = false;
    expect(await authenticate(), isNull);
    expect(biometrics.checks, 0);
    expect(pins, 0);
  });

  test('profil changé pendant le dialogue : ancien succès rejeté', () async {
    final cat =
        ProfileCatalog.fresh().add(name: 'Autre', isKids: false, nowMs: 1)!;
    ProfileRepository.instance.resetForTesting(cat);
    biometrics.result = Completer<bool>();
    final pending = authenticate();
    await biometrics.entered.future;
    await ProfileRepository.instance
        .activate(cat.profiles.last.id, leaveAllowed: true);
    await ProfileRepository.instance.activate('p1', leaveAllowed: true);
    biometrics.result!.complete(true);
    expect(await pending, isNull);
  });

  test(
      'protection activée puis retirée pendant le dialogue : nouvelle demande obligatoire',
      () async {
    biometrics.result = Completer<bool>();
    final pending = authenticate();
    await biometrics.entered.future;
    await ParentalControls.instance.setKidsMode(true);
    await ParentalControls.instance.setKidsMode(false);
    biometrics.result!.complete(true);
    expect(await pending, isNull);
  });

  test('la sortie révoque et les appels dispose/revoke sont idempotents',
      () async {
    final grant = (await authenticate())!;
    int changed = 0;
    grant.addListener(() => changed++);
    grant.revoke();
    grant.revoke();
    expect(grant.isValid, isFalse);
    expect(changed, 1);
    grant.dispose();
    grant.revoke();
    grant.dispose();
  });

  test('une nouvelle liste du même profil révoque immédiatement le grant',
      () async {
    final cat =
        ProfileCatalog.fresh().add(name: 'Adulte', isKids: false, nowMs: 1)!;
    final id = cat.profiles.last.id;
    ProfileRepository.instance.resetForTesting(cat.activate(id)!);
    final grant = (await authenticate())!;
    int changed = 0;
    grant.addListener(() => changed++);
    await ProfileRepository.instance.attachPlaylist(id, 19);
    expect(grant.isValid, isFalse);
    expect(changed, 1);
  });

  test(
      'une protection nouvelle invalide définitivement une autorisation existante',
      () async {
    final grant = (await authenticate())!;
    await ParentalControls.instance.setKidsMode(true);
    expect(grant.isValid, isFalse);
    await ParentalControls.instance.setKidsMode(false);
    expect(grant.isValid, isFalse);
  });

  test('deux gestes simultanés ne lancent pas deux dialogues', () async {
    biometrics.result = Completer<bool>();
    final pending = authenticate();
    await biometrics.entered.future;
    expect(await authenticate(), isNull);
    expect(biometrics.prompts, 1);
    biometrics.result!.complete(true);
    expect((await pending)?.isValid, isTrue);
  });
}
