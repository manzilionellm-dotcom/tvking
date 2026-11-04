// Les points @visibleForTesting de google_fonts 6.3.3 permettent de vider son
// cache mémoire et de bloquer son client HTTP. Les fontes et le bundle restent
// réels : aucun faux FontLoader ni faux octet de police n'est utilisé.
// ignore_for_file: implementation_imports

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_fonts/src/google_fonts_base.dart' as font_loader;
import 'package:google_fonts/src/google_fonts_descriptor.dart';
import 'package:google_fonts/src/google_fonts_family_with_variant.dart';
import 'package:google_fonts/src/google_fonts_variant.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:tv_king/core/theme/app_text_styles.dart';
import 'package:tv_king/core/theme/bundled_fonts.dart';
import 'package:tv_king/features/tv/core/tv_app_tokens.dart';
import 'package:tv_king/features/tv/core/tv_type.dart';

class _NoFontHttpClient extends http.BaseClient {
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    throw StateError('Le test interdit tout téléchargement de police.');
  }
}

class _EmptyAssetManifest implements AssetManifest {
  @override
  List<String> listAssets() => const <String>[];

  @override
  List<AssetMetadata>? getAssetVariants(String key) => null;
}

class _NoFontDiskCache extends PathProviderPlatform {
  int requests = 0;

  @override
  Future<String?> getApplicationSupportPath() async {
    requests++;
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late http.Client previousClient;
  late PathProviderPlatform previousPathProvider;
  late bool previousFetching;
  late _NoFontHttpClient noNetwork;
  late _NoFontDiskCache noDiskCache;

  setUp(() {
    previousClient = font_loader.httpClient;
    previousPathProvider = PathProviderPlatform.instance;
    previousFetching = GoogleFonts.config.allowRuntimeFetching;
    noNetwork = _NoFontHttpClient();
    font_loader.httpClient = noNetwork;
    font_loader.clearCache();
    font_loader.assetManifest = null;
    // Un cache de la machine ne doit jamais masquer un asset oublié. Le
    // chargeur 6.3.3 traite l'absence de répertoire comme un cache vide.
    // L'interface est remplacée quel que soit le plugin de la machine de test.
    noDiskCache = _NoFontDiskCache();
    PathProviderPlatform.instance = noDiskCache;
    GoogleFonts.config.allowRuntimeFetching = true;
    configureTvFontLoading();
  });

  tearDown(() {
    font_loader.httpClient = previousClient;
    PathProviderPlatform.instance = previousPathProvider;
    font_loader.assetManifest = null;
    font_loader.clearCache();
    GoogleFonts.config.allowRuntimeFetching = previousFetching;
    noNetwork.close();
  });

  testWidgets('les 14 variantes réelles se chargent sans réseau ni cache disque',
      (tester) async {
    late List<TextStyle> styles;
    await tester.runAsync(() async {
      expect(GoogleFonts.config.allowRuntimeFetching, isFalse);
      final manifest = jsonDecode(
        await rootBundle.loadString('assets/fonts/provenance.json'),
      ) as Map<String, dynamic>;
      final fonts = manifest['fonts'] as List<dynamic>;
      final assets = await AssetManifest.loadFromAssetBundle(rootBundle);
      expect(fonts, hasLength(14));
      // Le vrai AssetManifest généré par Flutter doit contenir chaque fichier.
      // La vérification Python indépendante contrôle également leurs SHA-256.
      for (final raw in fonts) {
        final font = raw as Map<String, dynamic>;
        final path = font['asset'] as String;
        expect(assets.listAssets(), contains(path), reason: path);
        final bytes = await rootBundle.load(path);
        expect(bytes.lengthInBytes, font['bytes'], reason: path);
      }

      const palette = TvAppTokens();
      // L'inventaire embarqué reste chargé fichier par fichier : les rôles
      // TV ne demandent plus Oswald ni les graisses 600/800 d'Inter, mais
      // ces fichiers doivent encore s'ouvrir hors ligne.
      styles = <TextStyle>[
        for (final weight in const <FontWeight>[
          FontWeight.w400,
          FontWeight.w500,
          FontWeight.w600,
          FontWeight.w700,
          FontWeight.w800,
        ])
          GoogleFonts.inter(fontSize: 20, fontWeight: weight),
        GoogleFonts.oswald(fontSize: 20, fontWeight: FontWeight.w500),
        GoogleFonts.oswald(fontSize: 20, fontWeight: FontWeight.w600),
        GoogleFonts.jetBrainsMono(fontSize: 20, fontWeight: FontWeight.w400),
        GoogleFonts.jetBrainsMono(fontSize: 20, fontWeight: FontWeight.w600),
        AppTextStyles.maisonSection,
        AppTextStyles.maisonHeroTitle,
        AppTextStyles.maisonProgram,
        AppTextStyles.maisonChannelName,
        AppTextStyles.maisonCta,
      ];
      final TextStyle display = palette.display(48);
      final TextStyle uiBold = palette.ui(48, weight: FontWeight.w700);
      expect(display.fontFamily, uiBold.fontFamily);
      expect(display.fontWeight, FontWeight.w700);
      expect(display.height, 1.25);
      expect(display.letterSpacing, 0);
      final TextStyle medium = palette.ui(20, weight: FontWeight.w500);
      final TextStyle semi = palette.ui(20, weight: FontWeight.w600);
      expect(semi.fontWeight, FontWeight.w500);
      expect(semi.fontFamily, medium.fontFamily);
      expect(palette.ui(20, weight: FontWeight.w800).fontWeight, FontWeight.w700);
      final TextStyle clock = palette.figure(20);
      expect(clock.fontFamily, medium.fontFamily);
      expect(
        clock.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(palette.mono(20).fontWeight, FontWeight.w600);
      expect(palette.mono(13).fontSize, 14);
      final TextTheme theme = TvType.material(const Color(0xFFF0EDE9));
      expect(theme.bodySmall!.fontSize, greaterThanOrEqualTo(14));
      expect(theme.labelSmall!.fontSize, greaterThanOrEqualTo(14));
      expect(theme.bodyLarge!.letterSpacing, 0);
      expect(theme.bodyLarge!.height, 24 / 16);
      expect(theme.labelSmall!.letterSpacing, 0.5);
      // Même construction que le thème TV ; elle ne doit demander aucune
      // variante cachée qui aurait été oubliée dans l'inventaire ci-dessus.
      GoogleFonts.interTextTheme(ThemeData(useMaterial3: true).textTheme);
      await GoogleFonts.pendingFonts();
      expect(styles.map((style) => style.fontFamily).toSet(), hasLength(14));
      expect(noNetwork.requests, 0);
      expect(noDiskCache.requests, 0);
    });

    // On soumet les styles au vrai moteur Flutter après FontLoader, sans
    // substituer Ahem ou accepter silencieusement une erreur de chargement.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              for (int i = 0; i < styles.length; i++)
                Text('Réglages • Activation • 0123456789 ($i)', style: styles[i]),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(noNetwork.requests, 0);
  });

  test('un asset absent échoue explicitement au lieu de télécharger', () async {
    font_loader.assetManifest = _EmptyAssetManifest();
    final descriptor = GoogleFontsDescriptor(
      familyWithVariant: const GoogleFontsFamilyWithVariant(
        family: 'Inter',
        googleFontsVariant: GoogleFontsVariant(
          fontWeight: FontWeight.w400,
          fontStyle: FontStyle.normal,
        ),
      ),
      file: GoogleFontsFile(
        'ecdb53099b1a68cd24c6900ea5beeafec81bd3c8cb9d0f3c51b9986583ba3982',
        303384,
      ),
    );
    await expectLater(
      font_loader.loadFontIfNecessary(descriptor),
      throwsA(isA<Exception>().having(
        (error) => error.toString(),
        'message',
        contains('Inter-Regular.ttf'),
      )),
    );
    expect(noNetwork.requests, 0);
    expect(noDiskCache.requests, 1);
  });

  test('les cinq licences originales sont exposées une seule fois', () async {
    registerBundledFontLicenses();
    registerBundledFontLicenses();
    const families = <String>{
      'Inter', 'Oswald', 'JetBrains Mono', 'Bricolage Grotesque', 'Manrope',
    };
    final found = <String, int>{};
    await for (final entry in LicenseRegistry.licenses) {
      for (final family in entry.packages.where(families.contains)) {
        found[family] = (found[family] ?? 0) + 1;
        final text = entry.paragraphs.map((paragraph) => paragraph.text).join('\n');
        expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'));
        if (family == 'Manrope') {
          expect(text, contains('Copyright 2018'));
          expect(text, contains('Copyright 2019'));
        }
      }
    }
    expect(found, <String, int>{for (final family in families) family: 1});
  });
}
