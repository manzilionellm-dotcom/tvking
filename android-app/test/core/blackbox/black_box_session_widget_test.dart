import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/blackbox/black_box.dart';
import 'package:tv_king/features/tv/presentation/tv_black_box_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  testWidgets(
    'la boîte noire relue après pause affiche le seul ANR concordant et expurge son détail',
    (WidgetTester tester) async {
      // Une origine entièrement synthétique. Les deux premiers événements appartiennent
      // respectivement à un service du paquet et à une ancienne session du lecteur.
      final int now = DateTime.now().millisecondsSinceEpoch;
      final int previousPid = pid + 100;
      const String canary = 'fausse-adresse-ne-doit-pas-apparaitre';
      const String fakeUrl = 'https://fixture.invalid/live/test/$canary/1';
      final Directory root =
          await tester.runAsync(
            () => Directory.systemTemp.createTemp('zuno-black-box-'),
          ) ??
          (throw StateError('Répertoire absent'));
      addTearDown(() => root.delete(recursive: true));
      final PathProviderPlatform oldPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPaths(root.path);
      addTearDown(() => PathProviderPlatform.instance = oldPaths);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      PackageInfo.setMockInitialValues(
        appName: 'ZUNO LAB',
        packageName: 'test.zuno',
        version: '119-lab',
        buildNumber: '1794559152',
        buildSignature: '',
      );
      const MethodChannel channel = MethodChannel(
        'com.manzilionellm.tvking/device',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final Map<String, Object> failure = <String, Object>{
        'reason': 6,
        'reasonName': 'ANR',
        'description': 'Détail $fakeUrl',
        'timestamp': now - 1000,
        'pid': previousPid,
        'isMainProcess': true,
        'isFault': true,
        'pssMb': 42,
        'rssMb': 73,
      };
      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        switch (call.method) {
          case 'getLastExitInfo':
            return <Object>[
              <String, Object>{
                ...failure,
                'reasonName': 'SERVICE_FIXTURE',
                'isMainProcess': false,
              },
              <String, Object>{
                ...failure,
                'reasonName': 'ANCIEN_FIXTURE',
                'timestamp': now - 120000,
              },
              failure,
            ];
          case 'getDeviceInfo':
            return <String, Object>{
              'sdk': 36,
              'model': 'LAB',
              'manufacturer': 'fixture',
            };
          case 'getMemoryInfo':
            return <String, Object>{'totalMb': 1024, 'lowRam': true};
          case 'getProcessMemory':
            return <String, Object>{'pssMb': 42, 'rssMb': 73};
          default:
            return null;
        }
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final File marker = File('${root.path}/blackbox.session');
      await tester.runAsync(() async {
        await marker.writeAsString(
          jsonEncode(<String, Object>{
            'clean': true,
            'at': now - 60000,
            'pid': previousPid,
          }),
        );
        await File('${root.path}/blackbox.last_action')
            .writeAsString('Lecture $fakeUrl');
        await BlackBox.instance.initialize(flavor: 'zuno-lab');
      });
      final last = BlackBox.instance.lastExit!;
      expect(last.nativeReason, 'ANR', reason: 'ZUNO_SORTIE_NON_CORRELEE');
      expect(last.brutal, isTrue);
      expect(last.pssMb, 42);
      expect(last.nativeDescription, isNot(contains(canary)));
      expect(last.lastAction, isNot(contains(canary)));
      final data =
          jsonDecode(marker.readAsStringSync()) as Map<String, dynamic>;
      expect(data['pid'], pid);
      expect(data['version'], '119-lab+1794559152');

      // Le vrai écran Réglages doit rendre le motif hors de la branche « sortie propre ».
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('fr'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(body: TvBlackBoxScreen()),
        ),
      );
      expect(find.textContaining('ANR'), findsWidgets);
      expect(find.textContaining(canary), findsNothing);
      expect(find.textContaining('SERVICE_FIXTURE'), findsNothing);
      expect(find.textContaining('ANCIEN_FIXTURE'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
