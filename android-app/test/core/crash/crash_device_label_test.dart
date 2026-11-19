import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/blackbox/black_box.dart';
import 'package:tv_king/core/crash/crash_device_label.dart';

void main() {
  test('API 35 : le plantage nomme le modèle, pas un compte', () {
    final String label = crashDeviceLabel(
      manufacturer: 'NVIDIA',
      model: 'SHIELD Android TV',
      sdk: '35',
    );
    expect(label, 'NVIDIA SHIELD Android TV · API 35');
    final BlackBoxLastExit exit = BlackBoxLastExit(
      brutal: true,
      at: DateTime.utc(2026, 11, 4),
      lastAction: 'zap',
      nativeReason: 'ANR (app figée, tuée par Android)',
      nativeDescription: '',
      pssMb: 420,
      rssMb: 0,
      deviceLabel: label,
    );
    expect(exit.headline, contains('ANR'));
    expect(exit.headline, contains('NVIDIA SHIELD Android TV · API 35'));
    expect(exit.headline, contains('420 Mo'));
    expect(exit.headline, isNot(contains('MAC')));
  });

  test('API 29 : pas de raison native, le modèle reste lisible', () {
    final String label = crashDeviceLabel(
      manufacturer: 'Amazon',
      model: 'AFTMM',
      sdk: '29',
    );
    expect(label, 'Amazon AFTMM · API 29');
    final BlackBoxLastExit exit = BlackBoxLastExit(
      brutal: true,
      at: null,
      lastAction: '',
      nativeReason: '',
      nativeDescription: '',
      pssMb: 0,
      rssMb: 0,
      deviceLabel: label,
    );
    expect(exit.headline, contains('raison inconnue (Android < 11)'));
    expect(exit.headline, contains('Amazon AFTMM · API 29'));
  });

  test('modèle vide : on n\'invente rien ; une URL dans le modèle est masquée',
      () {
    expect(
      crashDeviceLabel(manufacturer: 'X', model: '', sdk: '29'),
      isEmpty,
    );
    expect(
      crashDeviceLabel(
        manufacturer: '',
        model: 'http://user:secret@example.invalid/live/a/b',
        sdk: '35',
      ),
      isNot(contains('secret')),
    );
    expect(
      crashDeviceLabel(
        manufacturer: '',
        model: 'http://user:secret@example.invalid/live/a/b',
        sdk: '35',
      ),
      contains('[lien]'),
    );
  });

  test('sortie normale : la ligne ne devient pas un rapport de plantage', () {
    const BlackBoxLastExit exit = BlackBoxLastExit(
      brutal: false,
      at: null,
      lastAction: '',
      nativeReason: '',
      nativeDescription: '',
      pssMb: 0,
      rssMb: 0,
      deviceLabel: 'Amazon AFTMM · API 29',
    );
    expect(exit.headline, 'Dernière session terminée normalement.');
  });
}
