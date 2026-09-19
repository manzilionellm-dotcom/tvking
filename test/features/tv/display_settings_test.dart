// =========================================================
//  display_settings_test.dart — Marge d'écran automatique (19/09/2026)
// =========================================================
//  Photo du propriétaire : sur une Sony Bravia d'ancienne génération,
//  la carte du haut à droite et le bouton « J'en profite » sortaient de
//  l'écran. Le réglage de marge existait, à 0 %, caché dans Réglages.
//  Décision : « il faut que l'app s'adapte partout ».
//
//  Ce que ces tests verrouillent :
//    • une BOX ANDROID neuve part avec la zone sûre Android TV (5 %) ;
//    • un choix du client — même 0 % — n'est JAMAIS écrasé ;
//    • un PC Windows ne reçoit pas de cadre noir (défaut 0 %) ;
//    • pendant la lecture, la marge est « plein écran » et le compteur
//      de lecteurs superposés ne retombe qu'au DERNIER fermé.
//
//  Si un patch futur remet `?? 0` dans load(), la première assertion
//  saute : c'est voulu.
// =========================================================
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/features/tv/data/display_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final DisplaySettings d = DisplaySettings.instance;

  setUp(() {
    d.reinitialiser();
    AppPlatform.isTv = true; // box, sauf mention contraire
    debugDefaultTargetPlatformOverride = null; // = android sous flutter test
  });

  tearDown(() {
    d.reinitialiser();
    AppPlatform.isTv = false;
    debugDefaultTargetPlatformOverride = null;
  });

  group('défaut de plateforme', () {
    test('box Android, rien de mémorisé → 5 % (zone sûre Android TV)',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await d.load();
      expect(d.overscanPct, DisplaySettings.overscanAuto);
      expect(d.overscanPct, 5, reason: 'le chiffre de la règle Android TV');
      expect(d.overscanFraction, closeTo(0.05, 1e-9));
      expect(d.overscanChoisi, isFalse);
    });

    test('AVANT même load() la box part déjà avec la marge (pas de saut '
        'au premier rendu)', () {
      expect(d.overscanPct, DisplaySettings.overscanAuto);
    });

    test('0 % mémorisé = un CHOIX du client, jamais écrasé par le défaut',
        () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{'tv_overscan_pct': 0});
      await d.load();
      expect(d.overscanPct, 0);
      expect(d.overscanChoisi, isTrue);
    });

    test('3 % mémorisé (box en service) → restitué tel quel', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{'tv_overscan_pct': 3});
      await d.load();
      expect(d.overscanPct, 3);
    });

    test('valeur mémorisée aberrante → bornée à 0..8', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{'tv_overscan_pct': 40});
      await d.load();
      expect(d.overscanPct, DisplaySettings.maxOverscan);
    });

    test('PC Windows → 0 % : un écran d\'ordinateur affiche tout', () async {
      AppPlatform.isTv = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await d.load();
      expect(d.overscanPct, 0);
    });

    test('app TV hors Android (Samsung : Linux sous Tizen) → 0 %', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await d.load();
      expect(d.overscanPct, 0);
    });
  });

  group('réglage par le client', () {
    test('setOverscan borne 0..8 et rend le choix explicite', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await d.setOverscan(12);
      expect(d.overscanPct, 8);
      expect(d.overscanChoisi, isTrue);
      await d.setOverscan(-3);
      expect(d.overscanPct, 0);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('tv_overscan_pct'), 0,
          reason: 'le 0 est GRAVÉ : au prochain boot ce n\'est plus le défaut');
    });
  });

  group('vidéo plein écran', () {
    test('hors lecture : pas de plein écran', () {
      expect(d.videoPleinEcran, isFalse);
    });

    test('un lecteur ouvert → plein écran ; fermé → la marge revient',
        () async {
      d.entrerPleinEcran();
      expect(d.videoPleinEcran, isTrue);
      d.quitterPleinEcran();
      expect(d.videoPleinEcran, isFalse);
    });

    test('deux lecteurs superposés : la marge ne revient qu\'au DERNIER',
        () {
      d.entrerPleinEcran();
      d.entrerPleinEcran();
      d.quitterPleinEcran();
      expect(d.videoPleinEcran, isTrue,
          reason: 'le premier lecteur est encore là');
      d.quitterPleinEcran();
      expect(d.videoPleinEcran, isFalse);
    });

    test('une sortie de trop ne fait pas passer en négatif', () {
      d.quitterPleinEcran();
      expect(d.videoPleinEcran, isFalse);
      d.entrerPleinEcran();
      expect(d.videoPleinEcran, isTrue,
          reason: 'un compteur négatif aurait « avalé » cette entrée');
    });

    test('la notification est différée (jamais pendant le build en cours)',
        () async {
      int n = 0;
      d.addListener(() => n++);
      d.entrerPleinEcran();
      expect(n, 0, reason: 'rien de synchrone : initState est en plein build');
      await Future<void>.delayed(Duration.zero);
      expect(n, 1);
      d.quitterPleinEcran();
      await Future<void>.delayed(Duration.zero);
      expect(n, 2);
    });
  });
}
