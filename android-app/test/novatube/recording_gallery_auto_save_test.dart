// Sauvegarde AUTOMATIQUE d'un REC terminé dans la galerie du téléphone.
// Le canal natif est simulé : on vérifie ce que Dart lui demande (nom du MP4,
// une seule copie à la fois, aucun doublon, erreurs remontées sans exception).
// Aucun flux, compte ou vidéo réelle : chemins fictifs uniquement.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/recordings/data/gallery_exporter.dart';
import 'package:tv_king/features/recordings/data/recording_gallery_auto_save.dart';
import 'package:tv_king/features/tv/presentation/tv_recording_messages.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

const MethodChannel _gallery = MethodChannel('com.manzilionellm.tvking/gallery');
const String _first = '/fixture/Recordings/chaine-20261111-120000.ts';
const String _second = '/fixture/Recordings/chaine-20261111-130000.ts';

/// Simule le natif : comme le vrai GalleryExporter.kt, il refuse un export
/// pendant qu'un autre tourne (`EXPORT_IN_PROGRESS`). Chaque appel reste en
/// attente jusqu'à ce que le test le termine via [finish].
class _FakeNative {
  final List<Map<Object?, Object?>> calls = <Map<Object?, Object?>>[];
  final List<Completer<Object?>> pending = <Completer<Object?>>[];
  bool busy = false;
  int maxParallel = 0;
  int _active = 0;

  /// Code d'erreur à renvoyer au lieu d'un succès (null = succès).
  String? failWith;

  /// true = le natif reste « occupé » pour toujours.
  bool alwaysBusy = false;

  Future<Object?> handle(MethodCall call) async {
    final Map<Object?, Object?> args = call.arguments as Map<Object?, Object?>;
    calls.add(<Object?, Object?>{'method': call.method, ...args});
    if (busy || alwaysBusy) {
      throw PlatformException(code: 'EXPORT_IN_PROGRESS');
    }
    busy = true;
    _active++;
    if (_active > maxParallel) maxParallel = _active;
    final Completer<Object?> done = Completer<Object?>();
    pending.add(done);
    try {
      await done.future;
      if (failWith != null) throw PlatformException(code: failWith!);
      return true;
    } finally {
      _active--;
      busy = false;
    }
  }

  /// Termine l'export natif le plus ancien encore en attente.
  Future<void> finish() async {
    await _until(() => pending.isNotEmpty);
    pending.removeAt(0).complete(null);
    await _flush();
  }
}

Future<void> _flush() async {
  for (int i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _until(bool Function() condition) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 2)) {
      throw TimeoutException('condition jamais atteinte');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeNative native;
  late RecordingGalleryAutoSave autoSave;

  setUp(() {
    GalleryExporter.resetForTesting();
    native = _FakeNative();
    autoSave = RecordingGalleryAutoSave.forTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_gallery, native.handle);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_gallery, null);
    GalleryExporter.resetForTesting();
  });

  test('un REC terminé part en MP4 dans la galerie, avec son nom', () async {
    final Future<GalleryExportResult> saved = autoSave.save(_first);
    await native.finish();
    final GalleryExportResult result = await saved;

    expect(result.success, isTrue);
    expect(native.calls, <Map<Object?, Object?>>[
      <Object?, Object?>{
        'method': 'exportVideo',
        'srcPath': _first,
        'displayName': 'chaine-20261111-120000.mp4',
      },
    ]);
    expect(GalleryExporter.wasExported(_first), isTrue);
  });

  test('deux REC à la suite : une seule copie native à la fois', () async {
    final Future<GalleryExportResult> first = autoSave.save(_first);
    final Future<GalleryExportResult> second = autoSave.save(_second);
    await _until(() => native.calls.length == 1);
    await _flush();
    // Le 2e attend son tour : il n'a pas encore été envoyé au natif.
    expect(native.calls.length, 1);

    await native.finish();
    await _until(() => native.calls.length == 2);
    await native.finish();

    expect((await first).success, isTrue);
    expect((await second).success, isTrue);
    expect(native.maxParallel, 1);
    expect(native.calls.map((Map<Object?, Object?> c) => c['srcPath']),
        <String>[_first, _second]);
  });

  test('un export manuel en cours : on attend sa fin au lieu d’échouer',
      () async {
    // L'utilisateur exporte un ANCIEN enregistrement depuis la liste.
    final Future<GalleryExportResult> manual = GalleryExporter.exportVideo(
      srcPath: _second,
      displayName: GalleryExporter.displayNameFor(_second),
    );
    await _until(() => native.calls.length == 1);

    // Le REC se termine pendant ce temps : le natif répond « occupé ».
    final Future<GalleryExportResult> auto = autoSave.save(_first);
    await _until(() => native.calls.length == 2);
    expect(native.calls[1]['srcPath'], _first);

    await native.finish(); // fin de l'export manuel
    expect((await manual).success, isTrue);
    await _until(() => native.calls.length == 3);
    await native.finish(); // nouvel essai automatique, réussi

    final GalleryExportResult result = await auto;
    expect(result.success, isTrue);
    expect(native.calls.map((Map<Object?, Object?> c) => c['srcPath']),
        <String>[_second, _first, _first]);
    expect(native.maxParallel, 1);
  });

  test('jamais de doublon : un fichier déjà dans la galerie n’est pas recopié',
      () async {
    final Future<GalleryExportResult> manual = GalleryExporter.exportVideo(
      srcPath: _first,
      displayName: GalleryExporter.displayNameFor(_first),
    );
    await native.finish();
    expect((await manual).success, isTrue);

    final GalleryExportResult result = await autoSave.save(_first);
    expect(result.success, isTrue);
    expect(native.calls.length, 1);
  });

  test('une erreur native est renvoyée sans exception et la file continue',
      () async {
    native.failWith = 'CONVERSION_FAILED';
    final Future<GalleryExportResult> failed = autoSave.save(_first);
    await native.finish();
    final GalleryExportResult result = await failed;
    expect(result.success, isFalse);
    expect(result.errorCode, 'CONVERSION_FAILED');
    expect(GalleryExporter.wasExported(_first), isFalse);

    native.failWith = null;
    final Future<GalleryExportResult> next = autoSave.save(_second);
    await native.finish();
    expect((await next).success, isTrue);
  });

  test('natif bloqué : nombre d’essais borné, puis erreur lisible', () async {
    native.alwaysBusy = true;
    autoSave = RecordingGalleryAutoSave.forTesting(maxBusyRetries: 3);
    final GalleryExportResult result = await autoSave.save(_first);
    expect(result.success, isFalse);
    expect(result.errorCode, 'EXPORT_IN_PROGRESS');
    expect(native.calls.length, 4); // 1 essai + 3 nouveaux essais
  });

  test('sans pont natif (autre plateforme) : échec propre, pas de plantage',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_gallery, null);
    final GalleryExportResult result = await autoSave.save(_first);
    expect(result.success, isFalse);
    expect(result.errorCode, 'NO_CHANNEL');
  });

  testWidgets('textes affichés : succès et erreurs principales',
      (WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (BuildContext c) {
        context = c;
        return const SizedBox();
      }),
    ));
    final AppLocalizations l10n = AppLocalizations.of(context);
    String message(GalleryExportResult r) => tvGalleryExportMessage(context, r);

    expect(message(const GalleryExportResult(success: true)),
        l10n.tvRecordingExportSuccess);
    expect(
        message(const GalleryExportResult(
            success: false, errorCode: 'PERMISSION_DENIED')),
        l10n.tvRecordingExportPermission);
    expect(
        message(const GalleryExportResult(
            success: false, errorCode: 'UNSUPPORTED_CODEC')),
        l10n.tvRecordingExportFormat);
    expect(
        message(const GalleryExportResult(
            success: false, errorCode: 'EXPORT_FAILED')),
        l10n.tvRecordingExportFailed);
    expect(l10n.tvRecordingSavedToGallery('12,0 Mo'),
        contains('galerie du téléphone'));
  });
}
