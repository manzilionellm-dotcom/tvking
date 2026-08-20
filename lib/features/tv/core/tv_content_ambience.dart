// =========================================================
//  tv_content_ambience.dart — De l'affiche à l'ambiance (Caméléon, organe 2)
// =========================================================
//  Fait le pont entre une image de contenu (affiche de film, logo) et
//  l'ambiance de fond : décode une MINIATURE, extrait la couleur dominante
//  (K-means OKLab, chameleon_extractor) dans un ISOLATE, et nourrit
//  TvAmbience avec le résultat GOUVERNÉ.
//
//  BUDGET PETITE BOX, non négociable :
//    • le décodage est fait à taille RÉDUITE (96×54 via ResizeImage) —
//      jamais l'affiche pleine résolution (une jaquette 2000×3000 en
//      rawRgba, c'est 24 Mo : mortel sur un stick 1 Go) ;
//    • l'extraction (≈ 1 300 points, 8 itérations) part en isolate via
//      compute() : zéro jank sur le thread UI ;
//    • best-effort intégral : le moindre échec laisse simplement
//      l'ambiance neutre de l'univers — jamais d'erreur visible.
// =========================================================
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../../core/color/chameleon_extractor.dart';
import '../../../core/color/oklab.dart';
import 'tv_ambience.dart';

/// Point d'entrée pour les tests : extraction pure sur octets, exécutée en
/// isolate par [feedAmbienceFromImage]. Top-level : contrat de compute().
Oklch? extractGovernedForCompute((Uint8List, int, int) args) =>
    extractDominantColor(args.$1, args.$2, args.$3).governed;

/// Jeton de génération : si l'utilisateur enchaîne deux fiches plus vite
/// que le décodage, seule l'extraction la PLUS RÉCENTE nourrit l'ambiance.
int _generation = 0;

/// Extrait la couleur du contenu depuis [provider] et la donne à
/// [TvAmbience]. À appeler à l'ouverture d'une fiche ; l'appelant DOIT
/// appeler `TvAmbience.instance.feedContentAccent(null)` à sa fermeture.
Future<void> feedAmbienceFromImage(ImageProvider provider) async {
  // Tests widget : AUCUNE extraction — le réseau y est interdit et le
  // gestionnaire de cache d'images pose des timers (→ « A Timer is still
  // pending » en fin de test). Le moteur, lui, est verrouillé en pur Dart
  // (chameleon_extractor_test) ; ici on ne shunte que le câblage.
  if (const bool.fromEnvironment('FLUTTER_TEST')) return;
  final int gen = ++_generation;
  try {
    // Décodage MINIATURE : ResizeImage demande au décodeur une cible de
    // 96×54 — le coût mémoire est celui d'une vignette, pas d'une jaquette.
    final ImageStream stream = ResizeImage(
      provider,
      width: 96,
      height: 54,
      policy: ResizeImagePolicy.fit,
    ).resolve(ImageConfiguration.empty);

    final Completer<ui.Image> done = Completer<ui.Image>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        if (!done.isCompleted) done.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (Object e, StackTrace? _) {
        if (!done.isCompleted) {
          done.completeError(e);
        }
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    final ui.Image image;
    try {
      image = await done.future.timeout(const Duration(seconds: 6));
    } finally {
      // removeListener d'un listener déjà retiré = no-op : couvre le cas
      // « ni image ni erreur » (timeout) sans jamais laisser d'abonnement.
      stream.removeListener(listener);
    }

    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final int w = image.width, h = image.height;
    image.dispose();
    if (data == null) return;

    // Extraction hors du thread UI (les octets sont transférés, pas copiés
    // pixel à pixel par nous : compute s'en charge).
    final Oklch? governed = await compute(
      extractGovernedForCompute,
      (
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        w,
        h,
      ),
    );

    // Une fiche plus récente a pris la main pendant le calcul : on jette.
    if (gen != _generation) return;
    TvAmbience.instance.feedContentAccent(governed);
  } catch (_) {
    // Best-effort : affiche illisible / réseau lent → l'ambiance neutre
    // de l'univers reste en place, et c'est très bien comme ça.
  }
}
