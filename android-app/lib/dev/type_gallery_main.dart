// Point d'entrée de la galerie typographique, uniquement pour les captures
// d'émulateur. La box de production reste `lib/main_tv.dart`.
// Aucune playlist, aucune adresse, aucun identifiant.

import 'package:flutter/material.dart';

import '../core/theme/bundled_fonts.dart';
import '../features/tv/core/tv_app_tokens.dart';
import '../features/tv/core/tv_tokens.dart';
import '../features/tv/presentation/tv_app.dart' show kTvDesignWidth;
import '../features/tv/presentation/tv_scaled_viewport.dart';
import 'type_gallery.dart';

void main() {
  configureTvFontLoading();
  runApp(const _GalleryApp());
}

class _GalleryApp extends StatelessWidget {
  const _GalleryApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: TvTokens.bg,
        extensions: const <ThemeExtension<dynamic>>[TvAppTokens()],
      ),
      // Même canevas 1280 que la box : l'émulateur téléphone ne doit pas
      // mesurer les textes en dp de mobile.
      builder: (BuildContext context, Widget? child) {
        return TvScaledViewport(
          designWidth: kTvDesignWidth,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const Scaffold(
        body: SafeArea(child: TypeGallery()),
      ),
    );
  }
}
